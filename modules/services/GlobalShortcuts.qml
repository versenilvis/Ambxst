import QtQuick
import Quickshell.Hyprland._GlobalShortcuts
import qs.modules.globals
import qs.modules.services
import qs.config
import qs.modules.bar.workspaces

import Quickshell.Io

Item {
    id: root

    readonly property string appId: "ambxst"
    readonly property string ipcPipe: "/tmp/ambxst_ipc.pipe"

    // High-performance Pipe Listener (Daemon mode)
    // Creates a named pipe and listens for commands continuously
    Process {
        id: pipeListener
        command: ["bash", Qt.resolvedUrl("../../scripts/ipc_listener.sh").toString().replace("file://", "")]
        running: true
        
        stdout: SplitParser {
            onRead: data => {
                const cmd = data.trim();
                if (cmd !== "") {
                    root.run(cmd);
                }
            }
        }
    }

    function run(command) {
        console.log("IPC run command received:", command);
        switch (command) {
            // Dashboard / Command Palette
            case "dashboard-widgets": toggleCommandPalette(0); break;
            case "dashboard-controls": toggleDashboardTab(1); break;
            case "dashboard-clipboard": toggleCommandPalette(1); break;
            case "dashboard-emoji": toggleCommandPalette(2); break;
            case "dashboard-notes": toggleDashboardWithPrefix(Config.prefix.notes + " "); break;
            
            // System
            case "overview": toggleSimpleModule("overview"); break;
            case "powermenu": toggleSimpleModule("powermenu"); break;
            case "tools": toggleSimpleModule("tools"); break;
            case "config": GlobalStates.settingsVisible = !GlobalStates.settingsVisible; break;
            case "screenshot": GlobalStates.screenshotToolVisible = true; break;
            case "screenrecord": GlobalStates.screenRecordToolVisible = true; break;
            case "lens": 
                Screenshot.captureMode = "lens";
                GlobalStates.screenshotToolVisible = true;
                break;
            case "lockscreen": GlobalStates.lockscreenVisible = true; break;
            
            // Media
            case "media-seek-backward": seekActivePlayer(-mediaSeekStepMs); break;
            case "media-seek-forward": seekActivePlayer(mediaSeekStepMs); break;
            case "media-play-pause": 
                if (MprisController.canTogglePlaying) MprisController.togglePlaying();
                break;
            case "media-next": MprisController.next(); break;
            case "media-prev": MprisController.previous(); break;
            
            // Bar
            case "toggle-bar": toggleBarPinned(); break;
            case "update-windows": HyprlandData.updateWindowList(); break;
            case "notifications":
            case "notification-center":
                GlobalStates.toggleNotifications();
                break;
            case "calendar":
                GlobalStates.toggleCalendar();
                break;
                
            default: console.warn("Unknown IPC command:", command);
        }
    }

    IpcHandler {
        target: "ambxst"

        function run(command: string) {
            root.run(command);
        }
    }

    function toggleSimpleModule(moduleName) {
        if (Visibilities.currentActiveModule === moduleName) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule(moduleName);
        }
    }

    function toggleBarPinned() {
        const panels = Visibilities.barPanels;
        const screenNames = Object.keys(panels);
        for (let i = 0; i < screenNames.length; i++) {
            const p = panels[screenNames[i]];
            if (p && typeof p.pinned !== 'undefined') {
                p.pinned = !p.pinned;
            }
        }
    }

    function toggleCommandPalette(tabIndex) {
        if (GlobalStates.commandPaletteVisible) {
            if (GlobalStates.commandPaletteTab === tabIndex) {
                GlobalStates.commandPaletteVisible = false;
            } else {
                GlobalStates.commandPaletteTab = tabIndex;
            }
        } else {
            GlobalStates.commandPaletteTab = tabIndex;
            GlobalStates.commandPaletteVisible = true;
        }
    }

    function toggleDashboardTab(tabIndex) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        // Special handling for widgets tab (launcher)
        if (tabIndex === 0) {
            if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === "") {
                // Only toggle off if we're already in launcher without prefix
                Visibilities.setActiveModule("");
                return;
            }
            
            // Otherwise, always go to launcher (clear any prefix and ensure tab 0)
            GlobalStates.dashboardCurrentTab = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("dashboard");
            }
            return;
        }
        
        // For other tabs, normal toggle behavior
        if (isActive && GlobalStates.dashboardCurrentTab === tabIndex) {
            Visibilities.setActiveModule("");
            return;
        }

        GlobalStates.dashboardCurrentTab = tabIndex;
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
        }
    }

    function toggleDashboardWithPrefix(prefix) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        // Check if dashboard is already open with this prefix
        if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === prefix) {
            // Toggle off - close dashboard
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        // Always go to widgets tab first
        GlobalStates.dashboardCurrentTab = 0;
        
        if (!isActive) {
            // Open dashboard first, then set prefix after a brief delay
            Visibilities.setActiveModule("dashboard");
            Qt.callLater(() => {
                GlobalStates.launcherSearchText = prefix;
            });
        } else {
            // Dashboard already open, just set the prefix
            GlobalStates.launcherSearchText = prefix;
        }
    }

    function seekActivePlayer(offset) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) {
            return;
        }

        const maxLength = typeof player.length === "number" && !isNaN(player.length)
                ? player.length
                : Number.MAX_SAFE_INTEGER;
        const clamped = Math.max(0, Math.min(maxLength, player.position + offset));
        player.position = clamped;
    }

    GlobalShortcut {
        appid: root.appId
        name: "overview"
        description: "Toggle window overview"

        onPressed: toggleSimpleModule("overview")
    }

    GlobalShortcut {
        appid: root.appId
        name: "powermenu"
        description: "Toggle power menu"

        onPressed: toggleSimpleModule("powermenu")
    }

    GlobalShortcut {
        appid: root.appId
        name: "tools"
        description: "Toggle tools menu"

        onPressed: toggleSimpleModule("tools")
    }

    GlobalShortcut {
        appid: root.appId
        name: "screenshot"
        description: "Open screenshot tool"

        onPressed: GlobalStates.screenshotToolVisible = true
    }

    GlobalShortcut {
        appid: root.appId
        name: "screenrecord"
        description: "Open screen record tool"

        onPressed: GlobalStates.screenRecordToolVisible = true
    }

    GlobalShortcut {
        appid: root.appId
        name: "lens"
        description: "Open Google Lens (screenshot)"

        onPressed: {
            Screenshot.captureMode = "lens";
            GlobalStates.screenshotToolVisible = true;
        }
    }

    // command palette tab shortcuts
    GlobalShortcut {
        appid: root.appId
        name: "dashboard-widgets"
        description: "Open command palette (apps)"

        onPressed: toggleCommandPalette(0)
    }

    GlobalShortcut {
        appid: root.appId
        name: "dashboard-clipboard"
        description: "Open command palette (clipboard)"

        onPressed: toggleCommandPalette(1)
    }

    GlobalShortcut {
        appid: root.appId
        name: "dashboard-emoji"
        description: "Open command palette (emoji)"

        onPressed: toggleCommandPalette(2)
    }


    GlobalShortcut {
        appid: root.appId
        name: "dashboard-notes"
        description: "Open dashboard notes (via prefix)"

        onPressed: toggleDashboardWithPrefix(Config.prefix.notes + " ")
    }

    GlobalShortcut {
        appid: root.appId
        name: "dashboard-controls"
        description: "Open dashboard controls tab"

        onPressed: toggleDashboardTab(1)
    }

    // Media player shortcuts
    GlobalShortcut {
        appid: root.appId
        name: "media-seek-backward"
        description: "Seek backward in media player"

        onPressed: seekActivePlayer(-mediaSeekStepMs)
    }

    GlobalShortcut {
        appid: root.appId
        name: "media-seek-forward"
        description: "Seek forward in media player"

        onPressed: seekActivePlayer(mediaSeekStepMs)
    }

    GlobalShortcut {
        appid: root.appId
        name: "media-play-pause"
        description: "Toggle play/pause in media player"

        onPressed: {
            if (MprisController.canTogglePlaying) {
                MprisController.togglePlaying();
            }
        }
    }

    GlobalShortcut {
        appid: root.appId
        name: "toggle-bar"
        description: "Toggle bar visibility (pin/unpin)"

        onPressed: toggleBarPinned()
    }
}
