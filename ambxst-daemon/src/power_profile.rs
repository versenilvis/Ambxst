use std::collections::HashMap;
use zbus::{Connection, dbus_proxy};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;
use futures::stream::StreamExt;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PowerProfileInfo {
    pub is_available: bool,
    pub current: String,
    pub profiles: Vec<String>,
}

#[dbus_proxy(
    interface = "net.hadess.PowerProfiles",
    default_service = "net.hadess.PowerProfiles",
    default_path = "/net/hadess/PowerProfiles"
)]
trait PowerProfiles {
    #[dbus_proxy(property)]
    fn active_profile(&self) -> zbus::Result<String>;

    #[dbus_proxy(property)]
    fn set_active_profile(&self, profile: &str) -> zbus::Result<()>;

    #[dbus_proxy(property)]
    fn profiles(&self) -> zbus::Result<Vec<HashMap<String, zbus::zvariant::OwnedValue>>>;
}

pub struct PowerProfileManager {}

impl PowerProfileManager {
    pub fn new() -> Self {
        Self {}
    }

    pub async fn get_info(&self) -> PowerProfileInfo {
        let conn = match Connection::system().await {
            Ok(c) => c,
            Err(_) => {
                return PowerProfileInfo {
                    is_available: false,
                    current: String::new(),
                    profiles: Vec::new(),
                };
            }
        };

        let proxy = match PowerProfilesProxy::new(&conn).await {
            Ok(p) => p,
            Err(_) => {
                return PowerProfileInfo {
                    is_available: false,
                    current: String::new(),
                    profiles: Vec::new(),
                };
            }
        };

        let current = proxy.active_profile().await.unwrap_or_default();
        let raw_profiles = proxy.profiles().await.unwrap_or_default();

        let mut profiles = Vec::new();
        for map in raw_profiles {
            if let Some(val) = map.get("Profile") {
                if let zbus::zvariant::Value::Str(s) = &**val {
                    profiles.push(s.to_string());
                }
            }
        }

        // sort in standard order: power-saver, balanced, performance
        let order = ["power-saver", "balanced", "performance"];
        profiles.sort_by(|a, b| {
            let pos_a = order.iter().position(|&x| x == a.as_str()).unwrap_or(99);
            let pos_b = order.iter().position(|&x| x == b.as_str()).unwrap_or(99);
            pos_a.cmp(&pos_b)
        });

        PowerProfileInfo {
            is_available: true,
            current,
            profiles,
        }
    }

    pub async fn set_profile(&self, profile: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let conn = Connection::system().await?;
        let proxy = PowerProfilesProxy::new(&conn).await?;
        proxy.set_active_profile(profile).await?;
        Ok(())
    }
}

pub async fn monitor_power_profiles(tx: mpsc::Sender<String>) -> Result<(), Box<dyn std::error::Error>> {
    let conn = Connection::system().await?;
    let proxy = PowerProfilesProxy::new(&conn).await?;
    let mut changed = proxy.receive_active_profile_changed().await;
    let manager = PowerProfileManager::new();

    while let Some(_) = changed.next().await {
        let info = manager.get_info().await;
        let event = crate::ServerEvent {
            r#type: "power_profile".to_string(),
            data: info,
        };
        if let Ok(msg) = serde_json::to_string(&event) {
            let _ = tx.send(msg).await;
        }
    }
    Ok(())
}
