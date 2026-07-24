use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Serialize, Deserialize};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ClipboardItem {
    pub id: i64,
    pub content_hash: String,
    pub mime_type: String,
    pub preview: String,
    pub full_content: String,
    pub is_image: i32,
    pub binary_path: String,
    pub size: i64,
    pub pinned: i32,
    pub alias: Option<String>,
    pub display_index: Option<i32>,
    pub created_at: i64,
    pub updated_at: i64,
}

pub struct ClipboardManager {
    data_dir: PathBuf,
    conn: Arc<Mutex<Connection>>,
}

impl ClipboardManager {
    pub fn new(db_path: &Path, data_dir: &Path) -> Result<Self, rusqlite::Error> {
        if let Some(parent) = db_path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::create_dir_all(data_dir);

        let conn = Connection::open(db_path)?;
        conn.busy_timeout(std::time::Duration::from_millis(5000))?;
        
        conn.execute_batch("
            pragma journal_mode = WAL;
            pragma synchronous = NORMAL;
            pragma busy_timeout = 5000;
            pragma cache_size = 2000;
            pragma mmap_size = 0;
            pragma foreign_keys = ON;
        ")?;

        conn.execute_batch("
            create table if not exists clipboard_items (
                id integer primary key autoincrement,
                content_hash text not null unique,
                mime_type text not null default 'text/plain',
                preview text not null,
                full_content text,
                is_image integer not null default 0,
                binary_path text,
                size integer not null default 0,
                pinned integer not null default 0,
                alias text,
                display_index integer,
                created_at integer not null,
                updated_at integer not null
            );
            create index if not exists idx_content_hash on clipboard_items(content_hash);
            create index if not exists idx_created_at on clipboard_items(created_at desc);
            create index if not exists idx_is_image on clipboard_items(is_image);
            create index if not exists idx_pinned on clipboard_items(pinned desc);
            create index if not exists idx_display_index on clipboard_items(pinned desc, display_index asc);

            create virtual table if not exists clipboard_fts using fts5(
                preview, full_content, content=clipboard_items, content_rowid=id
            );
            create trigger if not exists clipboard_items_ai after insert on clipboard_items begin
                insert into clipboard_fts(rowid, preview, full_content) values (new.id, new.preview, new.full_content);
            end;
            create trigger if not exists clipboard_items_ad after delete on clipboard_items begin
                delete from clipboard_fts where rowid = old.id;
            end;
            create trigger if not exists clipboard_items_au after update on clipboard_items begin
                delete from clipboard_fts where rowid = old.id;
                insert into clipboard_fts(rowid, preview, full_content) values (new.id, new.preview, new.full_content);
            end;
        ")?;

        Ok(Self {
            data_dir: data_dir.to_path_buf(),
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    pub fn list(&self, limit: i64, offset: i64) -> Result<Vec<ClipboardItem>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("
            select id, content_hash, mime_type, preview, '',
                   is_image, coalesce(binary_path, ''), size, pinned, alias,
                   display_index, created_at, updated_at
            from clipboard_items
            order by pinned desc, updated_at desc
            limit ?1 offset ?2
        ")?;
        let rows = stmt.query_map(params![limit, offset], |row| {
            Ok(ClipboardItem {
                id: row.get(0)?,
                content_hash: row.get(1)?,
                mime_type: row.get(2)?,
                preview: row.get(3)?,
                full_content: row.get(4)?,
                is_image: row.get(5)?,
                binary_path: row.get(6)?,
                size: row.get(7)?,
                pinned: row.get(8)?,
                alias: row.get(9)?,
                display_index: row.get(10)?,
                created_at: row.get(11)?,
                updated_at: row.get(12)?,
            })
        })?;
        let mut items = Vec::new();
        for r in rows {
            items.push(r?);
        }
        Ok(items)
    }

    pub fn get_full_content(&self, id: i64) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("
            select coalesce(full_content, ''), is_image, coalesce(binary_path, '')
            from clipboard_items where id=?1
        ")?;
        let res: Option<(String, i32, String)> = stmt.query_row(params![id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        }).optional()?;

        match res {
            Some((content, is_image, binary_path)) => {
                if is_image == 0 && !binary_path.is_empty() {
                    let s = fs::read_to_string(&binary_path)?;
                    Ok(s)
                } else {
                    Ok(content)
                }
            }
            None => Ok(String::new()),
        }
    }

    pub fn delete(&self, id: i64) -> Result<Option<String>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        let res: Option<(String, String)> = conn.query_row(
            "select content_hash, coalesce(binary_path, '') from clipboard_items where id=?1",
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?))
        ).optional()?;

        if let Some((hash, binary_path)) = res {
            conn.execute("delete from clipboard_items where id=?1", params![id])?;
            if !binary_path.is_empty() {
                let _ = fs::remove_file(binary_path);
            }
            Ok(Some(hash))
        } else {
            Ok(None)
        }
    }

    pub fn clear(&self) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("select coalesce(binary_path, '') from clipboard_items where pinned=0")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut paths = Vec::new();
        for r in rows {
            let p = r?;
            if !p.is_empty() {
                paths.push(p);
            }
        }
        conn.execute("delete from clipboard_items where pinned=0", [])?;
        for p in paths {
            let _ = fs::remove_file(p);
        }
        Ok(())
    }

    pub fn toggle_pin(&self, id: i64) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "update clipboard_items set pinned = case when pinned=1 then 0 else 1 end where id=?1",
            params![id]
        )?;
        Ok(())
    }

    pub fn set_alias(&self, id: i64, alias: Option<String>) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        if let Some(ref a) = alias {
            if a.is_empty() {
                conn.execute("update clipboard_items set alias=null where id=?1", params![id])?;
            } else {
                conn.execute("update clipboard_items set alias=?1 where id=?2", params![alias, id])?;
            }
        } else {
            conn.execute("update clipboard_items set alias=null where id=?1", params![id])?;
        }
        Ok(())
    }

    pub fn swap(&self, id1: i64, id2: i64) -> Result<(), rusqlite::Error> {
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;
        let idx1: Option<i32> = tx.query_row(
            "select display_index from clipboard_items where id=?1",
            params![id1],
            |row| row.get(0)
        ).optional()?.flatten();
        let idx2: Option<i32> = tx.query_row(
            "select display_index from clipboard_items where id=?1",
            params![id2],
            |row| row.get(0)
        ).optional()?.flatten();

        tx.execute("update clipboard_items set display_index=?1 where id=?2", params![idx2, id1])?;
        tx.execute("update clipboard_items set display_index=?1 where id=?2", params![idx1, id2])?;
        tx.commit()?;
        Ok(())
    }

    pub fn get_item(&self, id: i64) -> Result<Option<ClipboardItem>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("
            select id, content_hash, mime_type, preview, coalesce(full_content, ''),
                   is_image, coalesce(binary_path, ''), size, pinned, alias,
                   display_index, created_at, updated_at
            from clipboard_items where id = ?1
        ")?;
        let res = stmt.query_row(params![id], |row| {
            Ok(ClipboardItem {
                id: row.get(0)?,
                content_hash: row.get(1)?,
                mime_type: row.get(2)?,
                preview: row.get(3)?,
                full_content: row.get(4)?,
                is_image: row.get(5)?,
                binary_path: row.get(6)?,
                size: row.get(7)?,
                pinned: row.get(8)?,
                alias: row.get(9)?,
                display_index: row.get(10)?,
                created_at: row.get(11)?,
                updated_at: row.get(12)?,
            })
        }).optional()?;

        match res {
            Some(mut item) => {
                if item.is_image == 0 && !item.binary_path.is_empty() {
                    if let Ok(s) = fs::read_to_string(&item.binary_path) {
                        item.full_content = s;
                    }
                }
                Ok(Some(item))
            }
            None => Ok(None),
        }
    }

    pub fn insert_text(&self, content: &str, mime_type: &str) -> Result<bool, rusqlite::Error> {
        let hash = format!("{:x}", md5::compute(content));
        let ts = chrono_ms();

        let conn = self.conn.lock().unwrap();
        let mut check_stmt = conn.prepare("select count(*) from clipboard_items where content_hash = ?1")?;
        let exists: i64 = check_stmt.query_row(params![hash], |row| row.get(0))?;
        if exists > 0 {
            conn.execute(
                "update clipboard_items set updated_at = ?1, display_index = 0 where content_hash = ?2",
                params![ts, hash]
            )?;
            // return true to notify client of item order update
            return Ok(true);
        }

        let preview = make_preview(content, mime_type);
        let mut stored_content = content.to_string();
        let mut binary_path = String::new();

        if content.len() > 10240 {
            let filename = format!("clipboard_text_{}.txt", ts);
            let full_path = self.data_dir.join(filename);
            if fs::write(&full_path, content).is_ok() {
                binary_path = full_path.to_string_lossy().to_string();
                stored_content = truncate_string_bytes(content, 10240);
            }
        }

        conn.execute("
            insert into clipboard_items
              (content_hash, mime_type, preview, full_content, is_image, binary_path, size, pinned, display_index, created_at, updated_at)
            values (?1, ?2, ?3, ?4, 0, ?5, ?6, 0, 0, ?7, ?8)
        ", params![
            hash,
            mime_type,
            preview,
            stored_content,
            binary_path,
            content.len() as i64,
            ts,
            ts
        ])?;

        let _ = self.prune_internal(&conn);
        Ok(true)
    }

    pub fn insert_image(&self, data: &[u8], mime_type: &str) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
        let hash = format!("{:x}", md5::compute(data));
        let ts = chrono_ms();

        let conn = self.conn.lock().unwrap();
        let mut check_stmt = conn.prepare("select count(*) from clipboard_items where content_hash = ?1")?;
        let exists: i64 = check_stmt.query_row(params![hash], |row| row.get(0))?;
        if exists > 0 {
            conn.execute(
                "update clipboard_items set updated_at = ?1, display_index = 0 where content_hash = ?2",
                params![ts, hash]
            )?;
            // return true to notify client of item order update
            return Ok(true);
        }

        let ext = mime_to_ext(mime_type);
        let filename = format!("clipboard_{}.{}", ts, ext);
        let full_path = self.data_dir.join(filename);

        fs::write(&full_path, data)?;

        let path_str = full_path.to_string_lossy().to_string();

        conn.execute("
            insert into clipboard_items
              (content_hash, mime_type, preview, full_content, is_image, binary_path, size, pinned, display_index, created_at, updated_at)
            values (?1, ?2, '[Image]', '', 1, ?3, ?4, 0, 0, ?5, ?6)
        ", params![
            hash,
            mime_type,
            path_str,
            data.len() as i64,
            ts,
            ts
        ])?;

        let _ = self.prune_internal(&conn);
        Ok(true)
    }

    fn prune_internal(&self, conn: &Connection) -> Result<(), rusqlite::Error> {
        let mut stmt = conn.prepare("
            select id, coalesce(binary_path, ''), is_image
            from clipboard_items
            where pinned = 0
            order by updated_at desc
            limit -1 offset ?1
        ")?;
        let rows = stmt.query_map(params![500], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })?;

        let mut ids = Vec::new();
        let mut paths = Vec::new();
        for r in rows {
            let (id, path) = r?;
            ids.push(id);
            if !path.is_empty() {
                paths.push(path);
            }
        }

        for id in ids {
            conn.execute("delete from clipboard_items where id=?1", params![id])?;
        }

        for p in paths {
            let _ = fs::remove_file(p);
        }

        let _ = conn.execute("vacuum", []);
        Ok(())
    }
}

fn chrono_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn make_preview(content: &str, mime_type: &str) -> String {
    if mime_type == "text/uri-list" {
        let uri = content.trim();
        let first_uri = uri.lines().next().unwrap_or(uri);
        if first_uri.starts_with("file://") {
            let path = Path::new(&first_uri[7..]);
            if let Some(filename) = path.file_name() {
                return format!("[File] {}", filename.to_string_lossy());
            }
        }
    }
    truncate_string_bytes(content, 100)
}

fn truncate_string_bytes(s: &str, limit: usize) -> String {
    if s.len() <= limit {
        return s.to_string();
    }
    if limit <= 3 {
        return s[..limit].to_string();
    }
    let mut truncated = &s[..limit - 3];
    while !truncated.is_empty() && std::str::from_utf8(truncated.as_bytes()).is_err() {
        truncated = &truncated[..truncated.len() - 1];
    }
    format!("{}...", truncated)
}

fn mime_to_ext(mime: &str) -> &'static str {
    match mime {
        "image/png" => "png",
        "image/jpeg" | "image/jpg" => "jpg",
        "image/gif" => "gif",
        "image/webp" => "webp",
        "image/bmp" => "bmp",
        _ => "img",
    }
}

pub fn spawn_watcher(
    manager: Arc<ClipboardManager>,
    on_change: mpsc::UnboundedSender<()>,
) {
    tokio::spawn(async move {
        loop {
            let mut cmd = tokio::process::Command::new("wl-paste");
            cmd.args(&["--watch", "echo", "CLIPBOARD_CHANGE"])
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::null());
            unsafe {
                cmd.pre_exec(|| {
                    libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                    Ok(())
                });
            }
            let mut child = match cmd.spawn() {
                Ok(child) => child,
                Err(e) => {
                    eprintln!("failed to start wl-paste --watch: {}, retrying in 2s", e);
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }
            };

            let stdout = child.stdout.take().unwrap();
            let reader = BufReader::new(stdout);
            let mut lines = reader.lines();
            
            let mut debounce_task: Option<tokio::task::JoinHandle<()>> = None;

            while let Ok(Some(line)) = lines.next_line().await {
                if line.trim() == "CLIPBOARD_CHANGE" {
                    let mgr = manager.clone();
                    let tx = on_change.clone();

                    if let Some(task) = debounce_task.take() {
                        task.abort();
                    }

                    debounce_task = Some(tokio::spawn(async move {
                        // Wait for spammy events to settle and payload to be ready
                        tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;
                        
                        match check_and_insert(&mgr).await {
                            Ok(inserted) => {
                                if inserted {
                                    let _ = tx.send(());
                                }
                            }
                            Err(e) => {
                                eprintln!("clipboard check/insert error: {}", e);
                            }
                        }
                    }));
                }
            }

            let _ = child.kill().await;
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        }
    });
}

async fn check_and_insert(manager: &ClipboardManager) -> Result<bool, String> {
    let mut types = Vec::new();
    for attempt in 0..3 {
        if let Ok(t) = wl_paste_list_types().await {
            if !t.is_empty() {
                types = t;
                break;
            }
        }
        tokio::time::sleep(tokio::time::Duration::from_millis(40 * (attempt + 1))).await;
    }

    if types.is_empty() {
        return Ok(false);
    }

    for mime in &types {
        if mime.starts_with("image/") {
            if let Ok(data) = wl_paste_bytes(mime).await {
                if !data.is_empty() {
                    return manager.insert_image(&data, mime).map_err(|e| e.to_string());
                }
            }
        }
    }

    if types.iter().any(|m| m == "text/uri-list") {
        if let Ok(uri_list) = wl_paste("text/uri-list").await {
            if !uri_list.is_empty() {
                let cleaned = uri_list.replace('\r', "");
                return manager.insert_text(&cleaned, "text/uri-list").map_err(|e| e.to_string());
            }
        }
    }

    for mime in &["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING"] {
        if types.iter().any(|m| m == mime) {
            if let Ok(text) = wl_paste(mime).await {
                if !text.is_empty() {
                    let cleaned = text.replace('\r', "");
                    return manager.insert_text(&cleaned, "text/plain").map_err(|e| e.to_string());
                }
            }
        }
    }

    for mime in &types {
        if mime.starts_with("text/") {
            if let Ok(text) = wl_paste(mime).await {
                if !text.is_empty() {
                    let cleaned = text.replace('\r', "");
                    return manager.insert_text(&cleaned, mime).map_err(|e| e.to_string());
                }
            }
        }
    }

    Ok(false)
}

async fn wl_paste(mime: &str) -> Result<String, String> {
    for _ in 0..2 {
        let child_fut = tokio::process::Command::new("wl-paste")
            .args(&["--no-newline", "--type", mime])
            .output();

        if let Ok(Ok(out)) = tokio::time::timeout(tokio::time::Duration::from_millis(1500), child_fut).await {
            if out.status.success() {
                return Ok(String::from_utf8_lossy(&out.stdout).to_string());
            }
        }
        tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;
    }
    Err("wl-paste failed or timed out".to_string())
}

async fn wl_paste_bytes(mime: &str) -> Result<Vec<u8>, String> {
    for _ in 0..2 {
        let child_fut = tokio::process::Command::new("wl-paste")
            .args(&["--no-newline", "--type", mime])
            .output();

        if let Ok(Ok(out)) = tokio::time::timeout(tokio::time::Duration::from_millis(1500), child_fut).await {
            if out.status.success() {
                return Ok(out.stdout);
            }
        }
        tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;
    }
    Err("wl-paste bytes failed or timed out".to_string())
}

async fn wl_paste_list_types() -> Result<Vec<String>, String> {
    for _ in 0..2 {
        let child_fut = tokio::process::Command::new("wl-paste")
            .arg("--list-types")
            .output();

        if let Ok(Ok(out)) = tokio::time::timeout(tokio::time::Duration::from_millis(1500), child_fut).await {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout);
                let mut list = Vec::new();
                for line in s.lines() {
                    let trimmed = line.trim();
                    if !trimmed.is_empty() {
                        list.push(trimmed.to_string());
                    }
                }
                if !list.is_empty() {
                    return Ok(list);
                }
            }
        }
        tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;
    }
    Err("wl-paste list types failed or timed out".to_string())
}

pub async fn copy_to_clipboard(item: &ClipboardItem) -> Result<(), std::io::Error> {
    let mime = if item.mime_type.is_empty() { "text/plain" } else { &item.mime_type };
    if item.is_image == 1 && !item.binary_path.is_empty() {
        let file = fs::read(&item.binary_path)?;
        let mut child = tokio::process::Command::new("wl-copy")
            .args(&["--type", mime])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()?;
        if let Some(mut stdin) = child.stdin.take() {
            use tokio::io::AsyncWriteExt;
            let _ = stdin.write_all(&file).await;
            // drop stdin → EOF → wl-copy serves the data and stays alive as server
        }
    } else {
        let mut child = tokio::process::Command::new("wl-copy")
            .args(&["--type", mime])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()?;
        if let Some(mut stdin) = child.stdin.take() {
            use tokio::io::AsyncWriteExt;
            let _ = stdin.write_all(item.full_content.as_bytes()).await;
        }
        // detach — wl-copy keeps running until another app replaces the selection
        let _ = child;
    }
    Ok(())
}

pub fn clear_system_clipboard_if_matches(hash: &str) {
    let hash_clone = hash.to_string();
    tokio::spawn(async move {
        if let Ok(text) = wl_paste("text/plain").await {
            let cur_hash = format!("{:x}", md5::compute(text));
            if cur_hash == hash_clone {
                let _ = tokio::process::Command::new("wl-copy")
                    .arg("--clear")
                    .output()
                    .await;
            }
        }
    });
}
