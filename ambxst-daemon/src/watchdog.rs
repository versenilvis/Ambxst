use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use zbus::Connection;
use futures_util::stream::StreamExt;

fn get_config_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
    let config_dir = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| Path::new(&home).join(".config"));
    config_dir.join("Ambxst").join("config").join("system.json")
}

fn get_command_from_config(key_path: &[&str], default: &str) -> String {
    let path = get_config_path();
    if !path.exists() {
        return default.to_string();
    }

    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return default.to_string(),
    };

    let json: serde_json::Value = serde_json::from_str(&content).unwrap_or(serde_json::Value::Null);
    let mut current = &json;
    for key in key_path {
        current = &current[*key];
    }

    current.as_str().unwrap_or(default).to_string()
}

pub fn spawn_dbus_watchdog() {
    tokio::spawn(async move {
        if let Ok(conn) = Connection::system().await {
            // register match rules on system bus using AddMatch method
            let _ = conn.call_method(
                Some("org.freedesktop.DBus"),
                "/org/freedesktop/DBus",
                Some("org.freedesktop.DBus"),
                "AddMatch",
                &("type='signal',interface='org.freedesktop.login1.Session',member='Lock'",),
            ).await;

            let _ = conn.call_method(
                Some("org.freedesktop.DBus"),
                "/org/freedesktop/DBus",
                Some("org.freedesktop.DBus"),
                "AddMatch",
                &("type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'",),
            ).await;

            let mut stream = zbus::MessageStream::from(conn);
            while let Some(Ok(msg)) = stream.next().await {
                if let Ok(header) = msg.header() {
                    if let (Ok(Some(interface)), Ok(Some(member))) = (header.interface(), header.member()) {
                        let interface_str = interface.as_str();
                        let member_str = member.as_str();

                        if interface_str == "org.freedesktop.login1.Session" && member_str == "Lock" {
                            let cmd = get_command_from_config(&["idle", "general", "lock_cmd"], "ambxst lock");
                            let _ = Command::new("sh").args(["-c", &cmd]).spawn();
                        } else if interface_str == "org.freedesktop.login1.Manager" && member_str == "PrepareForSleep" {
                            if let Ok(body) = msg.body::<(bool,)>() {
                                let going_to_sleep = body.0;
                                if going_to_sleep {
                                    let cmd = get_command_from_config(&["idle", "general", "before_sleep_cmd"], "loginctl lock-session");
                                    let _ = Command::new("sh").args(["-c", &cmd]).spawn();
                                } else {
                                    let cmd = get_command_from_config(&["idle", "general", "after_sleep_cmd"], "ambxst screen on");
                                    if cmd == "ambxst screen on" || cmd == "hyprctl dispatch dpms on" {
                                        // skip duplicate dpms commands
                                    } else {
                                        tokio::spawn(async move {
                                            tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
                                            let _ = Command::new("sh").args(["-c", &cmd]).spawn();
                                        });
                                    }
                                    
                                    tokio::spawn(async move {
                                        tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                                        let _ = Command::new("ambxst").args(["brightness", "-r"]).spawn();
                                    });

                                    if Command::new("nmcli").arg("-v").stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().is_ok() {
                                        tokio::spawn(async move {
                                            tokio::time::sleep(tokio::time::Duration::from_secs(8)).await;
                                            let _ = Command::new("nmcli").args(["radio", "wifi", "off"]).status();
                                            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
                                            let _ = Command::new("nmcli").args(["radio", "wifi", "on"]).status();
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    });
}
