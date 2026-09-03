//@ pragma UseQApplication
//@ pragma ShellId Ambxst
//@ pragma DataDir $BASE/Ambxst
//@ pragma StateDir $BASE/Ambxst

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.bar
import qs.modules.bar.workspaces
import qs.modules.notifications
import qs.modules.widgets.settings
import qs.modules.widgets.commandpalette
import qs.modules.notch
import qs.modules.widgets.overview
import qs.modules.services
import qs.modules.corners
import qs.modules.components
import qs.modules.desktop
import qs.modules.lockscreen
import qs.modules.dock
import qs.modules.globals
import qs.config
import "modules/tools"

ShellRoot {
    id: root

    ContextMenu {
        id: contextMenu
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        Component.onCompleted: Visibilities.setContextMenu(contextMenu)
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: wallpaperLoader
            active: true
            required property ShellScreen modelData
            sourceComponent: Wallpaper {
                screen: wallpaperLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: desktopLoader
            active: Config.desktop?.enabled ?? false
            required property ShellScreen modelData
            sourceComponent: Desktop {
                screen: desktopLoader.modelData
            }
        }
    }

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        Loader {
            id: barLoader
            
            // force reload when position changes to prevent artifacts
            property bool _active: true
            active: _active

            property string configBarPosition: Config.bar?.position ?? "top"
            onConfigBarPositionChanged: {
                if (Config.initialLoadComplete && Config.bar) {
                    barLoader._active = false;
                    barReloadTimer.restart();
                }
            }

            Timer {
                id: barReloadTimer
                interval: 100
                onTriggered: barLoader._active = true
            }

            required property ShellScreen modelData
            sourceComponent: Bar {
                screen: barLoader.modelData
            }
        }
    }

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        Loader {
            id: notchLoader
            // defer notch creation so it renders above the bar (both use WlrLayer.Overlay)
            active: false
            required property ShellScreen modelData
            sourceComponent: NotchWindow {
                screen: notchLoader.modelData
            }

            Component.onCompleted: Qt.callLater(function() { notchLoader.active = true })
        }
    }

    // Overview popup window (separate from notch)
    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        Loader {
            id: overviewLoader
            active: Config.overview?.enabled ?? true
            required property ShellScreen modelData
            sourceComponent: OverviewPopup {
                screen: overviewLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: cornersLoader
            active: true
            required property ShellScreen modelData
            sourceComponent: ScreenCorners {
                screen: cornersLoader.modelData
            }
        }
    }

    // Resource rings pinned to the right edge, shown only on an empty workspace
    Variants {
        model: Quickshell.screens

        Loader {
            id: resourceWidgetLoader
            active: Config.desktop?.resourceWidget ?? true
            required property ShellScreen modelData
            sourceComponent: ResourceWidget {
                modelData: resourceWidgetLoader.modelData
            }
        }
    }

    // Application Dock - only load when enabled and not integrated
    Loader {
        id: dockLoader
        active: (Config.dock?.enabled ?? false) && (Config.dock?.theme ?? "default") !== "integrated"
        sourceComponent: Dock {}
    }

    // Secure lockscreen using WlSessionLock
    WlSessionLock {
        id: sessionLock
        locked: GlobalStates.lockscreenVisible

        LockScreen {
            // WlSessionLockSurface creates automatically for each screen
        }
    }

    GlobalShortcuts {
        id: globalShortcuts
    }

    HyprlandConfig {
        id: hyprlandConfig
    }

    HyprlandKeybinds {
        id: hyprlandKeybinds
    }

    // Ambxst Settings floating window
    Settings {
        id: settingsWindow
    }

    CommandPalette {
        id: commandPalette
    }

    // Screenshot Tool
    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotLoader
            active: GlobalStates.screenshotToolVisible
            required property ShellScreen modelData
            sourceComponent: ScreenshotTool {
                targetScreen: screenshotLoader.modelData
            }
        }
    }

    // Screenshot Overlay (Preview)
    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotOverlayLoader
            active: true
            required property ShellScreen modelData
            sourceComponent: ScreenshotOverlay {
                targetScreen: screenshotOverlayLoader.modelData
            }
        }
    }


    // Screen Record Tool
    Loader {
        id: screenRecordLoader
        active: true
        source: "modules/tools/ScreenrecordTool.qml"
        
        property bool screenRecordVisible: GlobalStates.screenRecordToolVisible
        onScreenRecordVisibleChanged: {
            if (screenRecordLoader.status === Loader.Ready && screenRecordLoader.item) {
                if (GlobalStates.screenRecordToolVisible) {
                    screenRecordLoader.item.open();
                } else {
                    screenRecordLoader.item.close();
                }
            }
        }
    }

    // Mirror Tool
    Loader {
        id: mirrorLoader
        active: true
        source: "modules/tools/MirrorWindow.qml"
    }

    // Force initialization of control services at startup
    QtObject {
        id: serviceInitializer
        
        Component.onCompleted: {
            // Reference the services to force their creation
            let _ = DaemonClient.daemonConnected
            _ = NightLightService.active
            _ = GameModeService.toggled
            _ = CaffeineService.inhibit
            _ = IdleService.lockCmd // Force init
            _ = ClipboardService.cachedList
        }
    }

    Process {
        id: notificationSoundProc
    }

    Connections {
        target: Notifications
        ignoreUnknownSignals: true
        enabled: Notifications != null
        function onNotify(notification) {
            if (!Notifications.popupInhibited) {
                // play sound for incoming notifications
                notificationSoundProc.command = ["mpv", "--no-video", "--volume=35", Quickshell.env("HOME") + "/Ambxst/assets/notification/ringtone.mp3"]
                notificationSoundProc.startDetached()
            }
        }
    }
}
