mod sys_resources;
mod weather;
mod desktop;
mod usage;
mod watchdog;
mod clipboard;

use std::sync::{Arc, Mutex};
use std::path::{Path, PathBuf};
use tokio::net::{UnixListener, UnixStream};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::mpsc;
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
enum ClientCommand {
    #[serde(rename = "update_weather")]
    UpdateWeather { location: String },
    #[serde(rename = "record_usage")]
    RecordUsage { app_id: String },
    #[serde(rename = "get_top_apps")]
    GetTopApps { limit: usize },
    #[serde(rename = "execute_desktop")]
    ExecuteDesktop { path: String },
    #[serde(rename = "trash_file")]
    TrashFile { path: String },
    #[serde(rename = "get_desktop")]
    GetDesktop,
    #[serde(rename = "get_resources")]
    GetResources,
    #[serde(rename = "init_clipboard")]
    InitClipboard { db_path: String, data_dir: String },
    #[serde(rename = "list_clipboard")]
    ListClipboard { limit: i64, offset: i64 },
    #[serde(rename = "delete_clipboard")]
    DeleteClipboard { id: i64 },
    #[serde(rename = "clear_clipboard")]
    ClearClipboard,
    #[serde(rename = "toggle_pin_clipboard")]
    TogglePinClipboard { id: i64 },
    #[serde(rename = "set_alias_clipboard")]
    SetAliasClipboard { id: i64, alias: String },
    #[serde(rename = "swap_clipboard")]
    SwapClipboard { id1: i64, id2: i64 },
    #[serde(rename = "copy_to_clipboard")]
    CopyToClipboard { id: i64 },
    #[serde(rename = "get_content_clipboard")]
    GetContentClipboard { id: i64 },
}

#[derive(Serialize, Clone, Debug)]
struct ServerEvent<T> {
    r#type: String,
    data: T,
}

struct AppState {
    sys_monitor: sys_resources::SysMonitor,
    usage_tracker: usage::UsageTracker,
    desktop_items: Vec<desktop::DesktopItem>,
    clients: Vec<mpsc::UnboundedSender<String>>,
    clipboard_mgr: Option<Arc<clipboard::ClipboardManager>>,
}

type SharedState = Arc<Mutex<AppState>>;

fn init_clipboard_if_needed(state: &SharedState, _db_path: Option<&str>, _data_dir: Option<&str>) {
    let mut s = state.lock().unwrap();
    if s.clipboard_mgr.is_none() {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/verse".to_string());
        let default_db = format!("{}/.local/share/Ambxst/clipboard.db", home);
        let default_bin = format!("{}/.local/share/Ambxst/clipboard-data", home);
        let db_p = Path::new(&default_db).to_path_buf();
        let bin_p = Path::new(&default_bin).to_path_buf();
        match clipboard::ClipboardManager::new(&db_p, &bin_p) {
            Ok(mgr) => {
                let mgr_arc = Arc::new(mgr);
                s.clipboard_mgr = Some(mgr_arc.clone());

                let state_clone = state.clone();
                let (tx, mut rx) = mpsc::unbounded_channel::<()>();
                clipboard::spawn_watcher(mgr_arc, tx);

                tokio::spawn(async move {
                    while let Some(()) = rx.recv().await {
                        let items = {
                            let s_guard = state_clone.lock().unwrap();
                            if let Some(ref m) = s_guard.clipboard_mgr {
                                m.list(50, 0).ok()
                            } else {
                                None
                            }
                        };
                        if let Some(items_list) = items {
                            let event = ServerEvent {
                                r#type: "clipboard".to_string(),
                                data: items_list,
                            };
                            if let Ok(msg) = serde_json::to_string(&event) {
                                let mut s_guard = state_clone.lock().unwrap();
                                broadcast_message(&mut s_guard.clients, msg);
                            }
                        }
                    }
                });
            }
            Err(e) => {
                eprintln!("failed to init clipboard manager: {}", e);
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "linux")]
    unsafe {
        libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
    }

    // determine socket path
    let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/tmp"));
    let lock_path = Path::new(&runtime_dir).join("ambxst-daemon.lock");
    let my_pid = std::process::id();

    if let Ok(content) = std::fs::read_to_string(&lock_path) {
        if let Ok(old_pid) = content.trim().parse::<i32>() {
            if old_pid > 0 && old_pid as u32 != my_pid {
                println!("Killing old ambxst-daemon instance (PID {})", old_pid);
                unsafe { libc::kill(old_pid, libc::SIGTERM); }
                std::thread::sleep(std::time::Duration::from_millis(200));
                unsafe { libc::kill(old_pid, libc::SIGKILL); }
            }
        }
    }

    let _ = std::process::Command::new("killall").arg("-q").arg("wl-paste").status();

    use std::os::unix::io::AsRawFd;
    let lock_file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .open(&lock_path)?;
    let _ = unsafe { libc::flock(lock_file.as_raw_fd(), libc::LOCK_EX) };
    let _ = std::fs::write(&lock_path, format!("{}", my_pid));

    let socket_path = Path::new(&runtime_dir).join("ambxst-daemon.sock");

    // clean up old socket
    if socket_path.exists() {
        let _ = std::fs::remove_file(&socket_path);
    }

    let listener = UnixListener::bind(&socket_path)?;
    println!("ambxst-daemon listening on {}", socket_path.display());

    // setup shared state
    let state = Arc::new(Mutex::new(AppState {
        sys_monitor: sys_resources::SysMonitor::new(),
        usage_tracker: usage::UsageTracker::new(),
        desktop_items: Vec::new(),
        clients: Vec::new(),
        clipboard_mgr: None,
    }));

    init_clipboard_if_needed(&state, None, None);

    // start dbus watchdog
    watchdog::spawn_dbus_watchdog();

    // start desktop watcher
    let state_clone = state.clone();
    let mut desktop_watcher = desktop::DesktopWatcher::new(move |items| {
        let mut s = state_clone.lock().unwrap();
        s.desktop_items = items.clone();
        
        // broadcast desktop update
        let event = ServerEvent {
            r#type: "desktop".to_string(),
            data: items,
        };
        if let Ok(msg) = serde_json::to_string(&event) {
            broadcast_message(&mut s.clients, msg);
        }
    });
    if let Err(e) = desktop_watcher.start() {
        eprintln!("failed to start desktop watcher: {}", e);
    }
    let desktop_watcher = Arc::new(desktop_watcher);

    // spawn resource monitor loop
    let state_clone = state.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(2));
        loop {
            interval.tick().await;
            let mut s = state_clone.lock().unwrap();
            
            // default monitor root partition /
            let stats = s.sys_monitor.get_stats(&["/".to_string()]);
            let event = ServerEvent {
                r#type: "system_resources".to_string(),
                data: stats,
            };
            if let Ok(msg) = serde_json::to_string(&event) {
                broadcast_message(&mut s.clients, msg);
            }
        }
    });

    // accept client connections
    loop {
        if let Ok((stream, _)) = listener.accept().await {
            let state = state.clone();
            let desktop_watcher = desktop_watcher.clone();
            tokio::spawn(async move {
                handle_client(stream, state, desktop_watcher).await;
            });
        }
    }
}

fn broadcast_message(clients: &mut Vec<mpsc::UnboundedSender<String>>, msg: String) {
    let msg_with_newline = format!("{}\n", msg);
    clients.retain(|tx| {
        tx.send(msg_with_newline.clone()).is_ok()
    });
}

async fn handle_client(
    stream: UnixStream,
    state: SharedState,
    desktop_watcher: Arc<desktop::DesktopWatcher>,
) {
    let (rx, mut tx) = stream.into_split();
    let reader = BufReader::new(rx);
    let mut lines = reader.lines();

    // setup channel for sending events to this specific client
    let (client_tx, mut client_rx) = mpsc::unbounded_channel::<String>();
    
    // add to client list and send initial state
    {
        let mut s = state.lock().unwrap();
        s.clients.push(client_tx.clone());

        // send initial desktop items
        let event = ServerEvent {
            r#type: "desktop".to_string(),
            data: s.desktop_items.clone(),
        };
        if let Ok(msg) = serde_json::to_string(&event) {
            let _ = client_tx.send(format!("{}\n", msg));
        }

        // send initial top apps
        let top_apps = s.usage_tracker.get_top_apps(15);
        let event = ServerEvent {
            r#type: "top_apps".to_string(),
            data: top_apps,
        };
        if let Ok(msg) = serde_json::to_string(&event) {
            let _ = client_tx.send(format!("{}\n", msg));
        }
    }

    // task for writing outgoing events to the socket
    tokio::spawn(async move {
        while let Some(msg) = client_rx.recv().await {
            if tx.write_all(msg.as_bytes()).await.is_err() {
                break;
            }
        }
    });

    // read incoming commands from client
    while let Ok(Some(line)) = lines.next_line().await {
        if let Ok(cmd) = serde_json::from_str::<ClientCommand>(&line) {
            match cmd {
                ClientCommand::UpdateWeather { location } => {
                    let client_tx = client_tx.clone();
                    tokio::spawn(async move {
                        let data = weather::fetch_weather(&location).await;
                        let event = ServerEvent {
                            r#type: "weather".to_string(),
                            data,
                        };
                        if let Ok(msg) = serde_json::to_string(&event) {
                            let _ = client_tx.send(format!("{}\n", msg));
                        }
                    });
                }
                ClientCommand::RecordUsage { app_id } => {
                    let mut s = state.lock().unwrap();
                    s.usage_tracker.record_usage(app_id);
                    
                    // broadcast new top apps
                    let top_apps = s.usage_tracker.get_top_apps(15);
                    let event = ServerEvent {
                        r#type: "top_apps".to_string(),
                        data: top_apps,
                    };
                    if let Ok(msg) = serde_json::to_string(&event) {
                        // send to all clients
                        broadcast_message(&mut s.clients, msg);
                    }
                }
                ClientCommand::GetTopApps { limit } => {
                    let s = state.lock().unwrap();
                    let top_apps = s.usage_tracker.get_top_apps(limit);
                    let event = ServerEvent {
                        r#type: "top_apps".to_string(),
                        data: top_apps,
                    };
                    if let Ok(msg) = serde_json::to_string(&event) {
                        let _ = client_tx.send(format!("{}\n", msg));
                    }
                }
                ClientCommand::ExecuteDesktop { path } => {
                    desktop_watcher.execute_file(&path);
                }
                ClientCommand::TrashFile { path } => {
                    desktop_watcher.trash_file(&path);
                }
                ClientCommand::GetDesktop => {
                    let s = state.lock().unwrap();
                    let event = ServerEvent {
                        r#type: "desktop".to_string(),
                        data: s.desktop_items.clone(),
                    };
                    if let Ok(msg) = serde_json::to_string(&event) {
                        let _ = client_tx.send(format!("{}\n", msg));
                    }
                }
                ClientCommand::GetResources => {
                    let mut s = state.lock().unwrap();
                    let stats = s.sys_monitor.get_stats(&["/".to_string()]);
                    let event = ServerEvent {
                        r#type: "system_resources".to_string(),
                        data: stats,
                    };
                    if let Ok(msg) = serde_json::to_string(&event) {
                        let _ = client_tx.send(format!("{}\n", msg));
                    }
                }
                ClientCommand::InitClipboard { .. } => {
                    init_clipboard_if_needed(&state, None, None);
                    let s = state.lock().unwrap();
                    if let Some(ref mgr) = s.clipboard_mgr {
                        if let Ok(items) = mgr.list(50, 0) {
                            let event = ServerEvent {
                                r#type: "clipboard".to_string(),
                                data: items,
                            };
                            if let Ok(msg) = serde_json::to_string(&event) {
                                let _ = client_tx.send(format!("{}\n", msg));
                            }
                        }
                    }
                }
                ClientCommand::ListClipboard { limit, offset } => {
                    init_clipboard_if_needed(&state, None, None);
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        let client_tx = client_tx.clone();
                        tokio::spawn(async move {
                            if let Ok(items) = mgr.list(limit, offset) {
                                let event = ServerEvent {
                                    r#type: "clipboard".to_string(),
                                    data: items,
                                };
                                if let Ok(msg) = serde_json::to_string(&event) {
                                    let _ = client_tx.send(format!("{}\n", msg));
                                }
                            }
                        });
                    }
                }
                ClientCommand::DeleteClipboard { id } => {
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        let state_clone = state.clone();
                        tokio::spawn(async move {
                            if let Ok(Some(hash)) = mgr.delete(id) {
                                clipboard::clear_system_clipboard_if_matches(&hash);
                                if let Ok(items) = mgr.list(50, 0) {
                                    let event = ServerEvent {
                                        r#type: "clipboard".to_string(),
                                        data: items,
                                    };
                                    if let Ok(msg) = serde_json::to_string(&event) {
                                        let mut s = state_clone.lock().unwrap();
                                        broadcast_message(&mut s.clients, msg);
                                    }
                                }
                            }
                        });
                    }
                }
                ClientCommand::ClearClipboard => {
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        let state_clone = state.clone();
                        tokio::spawn(async move {
                            if mgr.clear().is_ok() {
                                if let Ok(items) = mgr.list(50, 0) {
                                    let event = ServerEvent {
                                        r#type: "clipboard".to_string(),
                                        data: items,
                                    };
                                    if let Ok(msg) = serde_json::to_string(&event) {
                                        let mut s = state_clone.lock().unwrap();
                                        broadcast_message(&mut s.clients, msg);
                                    }
                                }
                            }
                        });
                    }
                }
                ClientCommand::TogglePinClipboard { id } => {
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        let state_clone = state.clone();
                        tokio::spawn(async move {
                            if mgr.toggle_pin(id).is_ok() {
                                if let Ok(items) = mgr.list(50, 0) {
                                    let event = ServerEvent {
                                        r#type: "clipboard".to_string(),
                                        data: items,
                                    };
                                    if let Ok(msg) = serde_json::to_string(&event) {
                                        let mut s = state_clone.lock().unwrap();
                                        broadcast_message(&mut s.clients, msg);
                                    }
                                }
                            }
                        });
                    }
                }
                ClientCommand::SetAliasClipboard { id, alias } => {
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        let state_clone = state.clone();
                        tokio::spawn(async move {
                            if mgr.set_alias(id, Some(alias)).is_ok() {
                                if let Ok(items) = mgr.list(50, 0) {
                                    let event = ServerEvent {
                                        r#type: "clipboard".to_string(),
                                        data: items,
                                    };
                                    if let Ok(msg) = serde_json::to_string(&event) {
                                        let mut s = state_clone.lock().unwrap();
                                        broadcast_message(&mut s.clients, msg);
                                    }
                                }
                            }
                        });
                    }
                }
                ClientCommand::SwapClipboard { id1, id2 } => {
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        let state_clone = state.clone();
                        tokio::spawn(async move {
                            if mgr.swap(id1, id2).is_ok() {
                                if let Ok(items) = mgr.list(50, 0) {
                                    let event = ServerEvent {
                                        r#type: "clipboard".to_string(),
                                        data: items,
                                    };
                                    if let Ok(msg) = serde_json::to_string(&event) {
                                        let mut s = state_clone.lock().unwrap();
                                        broadcast_message(&mut s.clients, msg);
                                    }
                                }
                            }
                        });
                    }
                }
                ClientCommand::CopyToClipboard { id } => {
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        tokio::spawn(async move {
                            if let Ok(Some(item)) = mgr.get_item(id) {
                                let _ = clipboard::copy_to_clipboard(&item).await;
                            }
                        });
                    }
                }
                ClientCommand::GetContentClipboard { id } => {
                    let mgr = {
                        let s = state.lock().unwrap();
                        s.clipboard_mgr.clone()
                    };
                    if let Some(mgr) = mgr {
                        let client_tx = client_tx.clone();
                        tokio::spawn(async move {
                            if let Ok(content) = mgr.get_full_content(id) {
                                let event = ServerEvent {
                                    r#type: "clipboard_content".to_string(),
                                    data: serde_json::json!({
                                        "id": id.to_string(),
                                        "content": content
                                    }),
                                };
                                if let Ok(msg) = serde_json::to_string(&event) {
                                    let _ = client_tx.send(format!("{}\n", msg));
                                }
                            }
                        });
                    }
                }
            }
        }
    }
}
