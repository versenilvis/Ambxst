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
    signal fileSearchResultsReceived(var data)
    signal linkPreviewReceived(var data)
    signal networkChanged()
    signal emojiSearchResultsReceived(var data)
    signal emojiGroupsReceived(var data)
    signal powerProfileReceived(var data)

    // spawn daemon process if not already running
    property Process daemonProc: Process {
        id: daemonProc
        running: false
        command: [
            "sh",
            "-c",
            "if ! pgrep -x ambxst-daemon >/dev/null; then if [ -f '" + Quickshell.shellDir + "/bin/ambxst-daemon' ]; then exec '" + Quickshell.shellDir + "/bin/ambxst-daemon'; else exec '" + Quickshell.shellDir + "/ambxst-daemon/target/release/ambxst-daemon'; fi; fi"
        ]
    }

    // socket communication
    function connectSocket() {
        if (!socket) {
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
                    }
                }
            `, root);
        }

        if (socket && !socket.connected) {
            socket.connected = true;
        }
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
                    case "file_search_results":
                        root.fileSearchResultsReceived(event.data);
                        break;
                    case "link_preview":
                        root.linkPreviewReceived(event.data);
                        break;
                    case "network_changed":
                        root.networkChanged();
                        break;
                    case "emoji_search_results":
                        root.emojiSearchResultsReceived(event.data);
                        break;
                    case "emoji_groups":
                        root.emojiGroupsReceived(event.data);
                        break;
                    case "power_profile":
                        root.powerProfileReceived(event.data);
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

    function searchFiles(query) {
        sendCommand({
            type: "search_files",
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
        daemonProc.running = true;
        root.connectSocket();
    }
}
