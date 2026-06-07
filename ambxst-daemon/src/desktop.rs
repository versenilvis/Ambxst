use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use serde::Serialize;
use notify::{Watcher, RecursiveMode, EventKind};

#[derive(Serialize, Clone, Debug)]
pub struct DesktopItem {
    pub name: String,
    pub path: String,
    pub r#type: String,
    pub icon: String,
    pub is_desktop_file: bool,
    pub sort_order: i32,
}

pub struct DesktopWatcher {
    desktop_dir: PathBuf,
    cache_dir: PathBuf,
    on_change: Arc<dyn Fn(Vec<DesktopItem>) + Send + Sync>,
    _watcher: Option<notify::RecommendedWatcher>,
}

impl DesktopWatcher {
    pub fn new<F>(on_change: F) -> Self
    where
        F: Fn(Vec<DesktopItem>) + Send + Sync + 'static,
    {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
        let desktop_env = std::env::var("XDG_DESKTOP_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| Path::new(&home).join("Desktop"));

        let cache_base = std::env::var("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| Path::new(&home).join(".cache"));
        let cache_dir = cache_base.join("quickshell").join("desktop_thumbnails");

        let _ = fs::create_dir_all(&cache_dir);

        Self {
            desktop_dir: desktop_env,
            cache_dir,
            on_change: Arc::new(on_change),
            _watcher: None,
        }
    }

    pub fn start(&mut self) -> Result<(), String> {
        let desktop_dir = self.desktop_dir.clone();
        let cache_dir = self.cache_dir.clone();
        let on_change = self.on_change.clone();

        // create desktop directory if missing
        if !desktop_dir.exists() {
            let _ = fs::create_dir_all(&desktop_dir);
        }

        // initial scan
        let items = scan_desktop_dir(&desktop_dir, &cache_dir);
        (on_change)(items);

        let on_change_clone = on_change.clone();
        let desktop_dir_clone = desktop_dir.clone();
        let cache_dir_clone = cache_dir.clone();

        let mut watcher = notify::recommended_watcher(move |res: Result<notify::Event, notify::Error>| {
            if let Ok(event) = res {
                // watch for modifications, creations, deletions
                match event.kind {
                    EventKind::Create(_) | EventKind::Remove(_) | EventKind::Modify(_) => {
                        let items = scan_desktop_dir(&desktop_dir_clone, &cache_dir_clone);
                        (on_change_clone)(items);
                    }
                    _ => {}
                }
            }
        }).map_err(|e| e.to_string())?;

        watcher.watch(&desktop_dir, RecursiveMode::NonRecursive).map_err(|e| e.to_string())?;
        self._watcher = Some(watcher);

        Ok(())
    }

    pub fn execute_file(&self, path_str: &str) {
        let path = Path::new(path_str);
        if path.extension().map(|e| e == "desktop").unwrap_or(false) {
            let _ = Command::new("gio")
                .args(["launch", path_str])
                .spawn();
        } else {
            let _ = Command::new("xdg-open")
                .arg(path_str)
                .spawn();
        }
    }

    pub fn trash_file(&self, path_str: &str) {
        let _ = Command::new("gio")
            .args(["trash", path_str])
            .status();
    }
}

// scan the desktop directory and return sorted items
fn scan_desktop_dir(desktop_dir: &Path, cache_dir: &Path) -> Vec<DesktopItem> {
    let mut items = Vec::new();

    let entries = match fs::read_dir(desktop_dir) {
        Ok(e) => e,
        Err(_) => return items,
    };

    let mut media_to_process = Vec::new();

    for entry in entries.flatten() {
        let path = entry.path();
        let file_name = entry.file_name().to_string_lossy().into_owned();

        if file_name.starts_with('.') {
            continue;
        }

        let is_dir = path.is_dir();
        let path_str = path.to_string_lossy().into_owned();

        if is_dir {
            items.push(DesktopItem {
                name: file_name,
                path: path_str,
                r#type: "folder".to_string(),
                icon: "folder".to_string(),
                is_desktop_file: false,
                sort_order: 0,
            });
        } else if file_name.ends_with(".desktop") {
            let (name, icon) = parse_desktop_file(&path).unwrap_or_else(|| {
                (file_name.clone(), "application-x-executable".to_string())
            });
            items.push(DesktopItem {
                name,
                path: path_str,
                r#type: "application".to_string(),
                icon,
                is_desktop_file: true,
                sort_order: 1,
            });
        } else {
            let file_type = get_file_type(&file_name);
            let icon = get_icon_for_type(&file_type);

            if ["image", "media"].contains(&file_type.as_str()) {
                media_to_process.push((path.clone(), file_type.clone()));
            }

            items.push(DesktopItem {
                name: file_name,
                path: path_str,
                r#type: file_type,
                icon,
                is_desktop_file: false,
                sort_order: 2,
            });
        }
    }

    // sort items
    items.sort_by(|a, b| {
        if a.sort_order != b.sort_order {
            a.sort_order.cmp(&b.sort_order)
        } else {
            a.name.to_lowercase().cmp(&b.name.to_lowercase())
        }
    });

    // spawn background thumbnail generation
    if !media_to_process.is_empty() {
        let cache_dir = cache_dir.to_path_buf();
        tokio::spawn(async move {
            generate_thumbnails(media_to_process, &cache_dir).await;
        });
    }

    items
}

// read name and icon from desktop file
fn parse_desktop_file(path: &Path) -> Option<(String, String)> {
    let content = fs::read_to_string(path).ok()?;
    let mut name = None;
    let mut icon = None;

    for line in content.lines() {
        let line = line.trim();
        if line.starts_with("Name=") {
            name = Some(line[5..].to_string());
        } else if line.starts_with("Icon=") {
            icon = Some(line[5..].to_string());
        }
        if name.is_some() && icon.is_some() {
            break;
        }
    }

    match (name, icon) {
        (Some(n), Some(i)) => Some((n, i)),
        (Some(n), None) => Some((n, "application-x-executable".to_string())),
        _ => None,
    }
}

// determine file category by extension
fn get_file_type(file_name: &str) -> String {
    let ext = Path::new(file_name)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();

    match ext.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "svg" | "bmp" => "image".to_string(),
        "mp4" | "webm" | "mov" | "avi" | "mkv" | "mp3" | "wav" | "ogg" | "flac" => "media".to_string(),
        "pdf" => "pdf".to_string(),
        "txt" | "md" | "log" => "text".to_string(),
        "zip" | "tar" | "gz" | "rar" | "7z" => "archive".to_string(),
        "doc" | "docx" | "odt" => "document".to_string(),
        _ => "file".to_string(),
    }
}

// return default system icon name for category
fn get_icon_for_type(file_type: &str) -> String {
    match file_type {
        "folder" => "folder".to_string(),
        "image" => "image-x-generic".to_string(),
        "media" => "video-x-generic".to_string(),
        "pdf" => "application-pdf".to_string(),
        "text" => "text-x-generic".to_string(),
        "archive" => "package-x-generic".to_string(),
        "document" => "x-office-document".to_string(),
        _ => "text-x-generic".to_string(),
    }
}

// run ffmpeg or convert to generate 64x64 thumbnails
async fn generate_thumbnails(files: Vec<(PathBuf, String)>, cache_dir: &Path) {
    for (path, file_type) in files {
        let ext_str = path.extension().unwrap_or_default().to_string_lossy().to_lowercase();
        let stem = path.file_stem().unwrap_or_default().to_string_lossy();
        let thumb_name = format!("{}.{}.jpg", stem, ext_str);
        let thumb_path = cache_dir.join(thumb_name);

        if thumb_path.exists() {
            if let (Ok(m1), Ok(m2)) = (path.metadata().and_then(|m| m.modified()), thumb_path.metadata().and_then(|m| m.modified())) {
                if m1 <= m2 {
                    continue; // up to date
                }
            }
        }

        let path_str = path.to_string_lossy().into_owned();
        let thumb_str = thumb_path.to_string_lossy().into_owned();

        let is_video = ["mp4", "webm", "mov", "avi", "mkv", "gif"].contains(&ext_str.as_str());

        if is_video {
            let _ = tokio::process::Command::new("ffmpeg")
                .args([
                    "-y",
                    "-i", &path_str,
                    "-ss", "00:00:01",
                    "-vframes", "1",
                    "-vf", "scale=64:64:force_original_aspect_ratio=increase,crop=64:64",
                    "-q:v", "2",
                    "-f", "image2",
                    &thumb_str,
                ])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status()
                .await;
        } else if file_type == "image" {
            let _ = tokio::process::Command::new("convert")
                .args([
                    &path_str,
                    "-resize", "64x64^",
                    "-gravity", "center",
                    "-extent", "64x64",
                    "-quality", "85",
                    &thumb_str,
                ])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status()
                .await;
        }
    }
}

