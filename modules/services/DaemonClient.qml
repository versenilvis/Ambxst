pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // status properties
    property var socket: null
    property bool daemonConnected: socket ? socket.connected : false

    // incoming event signals
    signal systemResourcesReceived(var data)
    signal desktopReceived(var data)
    signal topAppsReceived(var data)
    signal clipboardReceived(var data)
    signal clipboardContentReceived(string itemId, string content)
    signal appSearchResultsReceived(var data)
    signal linkPreviewReceived(var data)
    signal networkChanged()

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
    function connectSocket() {
        if (socket) {
            socket.connected = false;
            socket.destroy();
            socket = null;
        }

        socket = Qt.createQmlObject(`
            import Quickshell.Io;
            Socket {
                path: "${Quickshell.env("XDG_RUNTIME_DIR")}/ambxst-daemon.sock"
                connected: false
                parser: SplitParser {
                    splitMarker: "\\n"
                    onRead: text => {
                        root.handleSocketRead(text);
                    }
                }
                onError: error => {
                    console.warn("DaemonClient: Socket error: " + error);
                    socket.connected = false;
                }
            }
        `, root);

        socket.connected = true;
    }

    function handleSocketRead(text) {
        const raw = text.trim();
        if (raw.length === 0) return;

        try {
            const event = JSON.parse(raw);
            if (event && event.type) {
                switch (event.type) {
                    case "system_resources":
                        root.systemResourcesReceived(event.data);
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
                    case "app_search_results":
                        root.appSearchResultsReceived(event.data);
                        break;
                    case "link_preview":
                        root.linkPreviewReceived(event.data);
                        break;
                    case "network_changed":
                        root.networkChanged();
                        break;
                }
            }
        } catch (e) {
            console.warn("DaemonClient: JSON parse error:", e);
        }
    }

    // reconnect loop
    property Timer reconnectTimer: Timer {
        interval: 2000
        running: !root.daemonConnected
        repeat: true
        onTriggered: {
            root.connectSocket();
        }
    }

    // helper function to send command to daemon
    function sendCommand(cmdObj) {
        if (socket && socket.connected) {
            socket.write(JSON.stringify(cmdObj) + "\n");
            socket.flush();
        } else {
            console.warn("DaemonClient: Cannot send command, socket not connected");
        }
    }

    function searchApps(query) {
        sendCommand({
            type: "search_apps",
            query: query
        });
    }

    function fetchLinkPreview(url) {
        sendCommand({
            type: "fetch_link_preview",
            url: url
        });
    }

    function colorpicker() {
        sendCommand({ type: "colorpicker" });
    }

    function ocr(langs) {
        sendCommand({
            type: "ocr",
            langs: langs || ["eng"]
        });
    }

    function qrScan() {
        sendCommand({ type: "qr_scan" });
    }

    Component.onCompleted: {
        root.connectSocket();
    }
}
