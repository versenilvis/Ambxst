pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // status properties
    property bool daemonConnected: socket.connected

    // incoming event signals
    signal systemResourcesReceived(var data)
    signal weatherReceived(var data)
    signal desktopReceived(var data)
    signal topAppsReceived(var data)
    signal clipboardReceived(var data)
    signal clipboardContentReceived(string itemId, string content)

    // spawn daemon process
    property Process daemonProc: Process {
        id: daemonProc
        running: true
        command: [Quickshell.shellDir + "/ambxst-daemon/target/release/ambxst-daemon"]
        
        onExited: exitCode => {
            console.warn("ambxst-daemon exited with code " + exitCode + ". Restarting...");
            restartTimer.start();
        }
    }

    property Timer restartTimer: Timer {
        id: restartTimer
        interval: 1000
        repeat: false
        onTriggered: daemonProc.running = true
    }

    // socket communication
    property Socket socket: Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/ambxst-daemon.sock"
        connected: true

        parser: SplitParser {
            splitMarker: "\n"
            onRead: text => {
                const raw = text.trim();
                if (raw.length === 0) return;

                try {
                    const event = JSON.parse(raw);
                    if (event && event.type) {
                        switch (event.type) {
                            case "system_resources":
                                root.systemResourcesReceived(event.data);
                                break;
                            case "weather":
                                root.weatherReceived(event.data);
                                break;
                            case "desktop":
                                root.desktopReceived(event.data);
                                break;
                            case "top_apps":
                                root.topAppsReceived(event.data);
                                break;
                            case "clipboard":
                                root.clipboardReceived(event.data);
                                break;
                            case "clipboard_content":
                                root.clipboardContentReceived(event.data.id, event.data.content);
                                break;
                        }
                    }
                } catch (e) {
                    console.warn("DaemonClient: JSON parse error:", e);
                }
            }
        }
    }

    // reconnect loop
    property Timer reconnectTimer: Timer {
        interval: 2000
        running: !socket.connected
        repeat: true
        onTriggered: {
            socket.connected = false;
            socket.connected = true;
        }
    }

    // helper function to send command to daemon
    function sendCommand(cmdObj) {
        if (socket.connected) {
            socket.write(JSON.stringify(cmdObj) + "\n");
            socket.flush();
        } else {
            console.warn("DaemonClient: Cannot send command, socket not connected");
        }
    }

    Component.onCompleted: {
        // start daemon and connect socket
    }
}
