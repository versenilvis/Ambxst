use zbus::{Connection, dbus_proxy};
use tokio::sync::mpsc;
use serde::Serialize;
use futures::stream::StreamExt;

#[dbus_proxy(
    interface = "org.freedesktop.NetworkManager",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager"
)]
trait NetworkManager {
    #[dbus_proxy(property)]
    fn state(&self) -> zbus::Result<u32>;
}

#[derive(Serialize, Clone, Debug)]
pub struct NetworkStateEvent {
    pub r#type: String,
}

pub async fn monitor_network(tx: mpsc::Sender<String>) -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::system().await?;
    let proxy = NetworkManagerProxy::new(&connection).await?;

    let mut state_changed = proxy.receive_state_changed().await;

    while let Some(_) = state_changed.next().await {
        let event = NetworkStateEvent {
            r#type: "network_changed".to_string(),
        };
        if let Ok(msg) = serde_json::to_string(&event) {
            let _ = tx.send(format!("{}\n", msg)).await;
        }
    }

    Ok(())
}
