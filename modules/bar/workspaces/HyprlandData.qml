pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.globals

Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var monitors: []

    // Update window list when Hyprland layout becomes ready
    Connections {
        ignoreUnknownSignals: true
        enabled: GlobalStates != null
        target: GlobalStates

        function onHyprlandLayoutReadyChanged() {
            if (GlobalStates.hyprlandLayoutReady) {
                root.updateWindowList()
            }
        }
    }

    Timer {
        id: debounceTimer
        interval: 30
        repeat: false
        onTriggered: {
            getClients.running = true
            getMonitors.running = true
        }
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            // only poll if the system layout is ready
            if (GlobalStates.hyprlandLayoutReady) {
                root.updateWindowList()
            }
        }
    }

    function updateWindowList() {
        debounceTimer.restart()
    }

    Component.onCompleted: {
        updateWindowList()
    }

    Connections {
        ignoreUnknownSignals: true
        enabled: Hyprland != null
        target: Hyprland

        function onRawEvent(event) {
            const ignoredEvents = [
                "activewindow", "focusedmon", "monitoradded", 
                "createworkspace", "destroyworkspace", "moveworkspace", 
                "activespecial", "windowtitle"
            ];
            if (ignoredEvents.includes(event.name)) return ;
            updateWindowList()
        }
    }

    Process {
        id: getClients
        command: ["bash", "-c", "hyprctl clients -j | jq -c"]
        stdout: SplitParser {
            onRead: (data) => {
                root.windowList = JSON.parse(data)
                let tempWinByAddress = {}
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i]
                    tempWinByAddress[win.address] = win
                }
                root.windowByAddress = tempWinByAddress
                root.addresses = root.windowList.map((win) => win.address)
            }
        }
    }
    Process {
        id: getMonitors
        command: ["bash", "-c", "hyprctl monitors -j | jq -c"]
        stdout: SplitParser {
            onRead: (data) => {
                root.monitors = JSON.parse(data)
            }
        }
    }
}