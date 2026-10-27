pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.bar.workspaces
import qs.modules.desktop
import qs.modules.services
import qs.modules.theme
import qs.config

PanelWindow {
    id: desktop

    property int barSize: 44
    property string barPosition: ["top", "bottom", "left", "right"].includes(Config.bar.position) ? Config.bar.position : "top"
    property string selectedPath: ""

    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(desktop.screen)
    readonly property int activeWorkspaceId: hyprlandMonitor?.activeWorkspace?.id ?? 1

    // check if the current workspace is empty or only contains floating windows
    readonly property bool isWorkspaceEmptyOrFloating: {
        const windows = HyprlandData.windowList.filter(w => w.workspace.id === activeWorkspaceId);
        return windows.every(w => w.floating === true);
    }

    onIsWorkspaceEmptyOrFloatingChanged: {
        if (!isWorkspaceEmptyOrFloating) {
            desktop.selectedPath = "";
        }
    }

    property real lastOpenTimestamp: 0

    function safeOpenFile(path, isDesktopFile) {
        let now = Date.now();
        if (now - desktop.lastOpenTimestamp < 500) {
            return;
        }
        desktop.lastOpenTimestamp = now;
        if (isDesktopFile) {
            DesktopService.executeDesktopFile(path);
        } else {
            DesktopService.openFile(path);
        }
    }

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    visible: (Config.desktop?.enabled ?? true) && isWorkspaceEmptyOrFloating

    Item {
        id: iconContainer
        anchors.fill: parent
        anchors.margins: 16
        anchors.bottomMargin: desktop.barPosition === "bottom" ? desktop.barSize + 16 : 16
        anchors.topMargin: desktop.barPosition === "top" ? desktop.barSize + 16 : 16
        anchors.leftMargin: desktop.barPosition === "left" ? desktop.barSize + 16 : 16
        anchors.rightMargin: desktop.barPosition === "right" ? desktop.barSize + 16 : 16

        opacity: desktop.isWorkspaceEmptyOrFloating ? 1 : 0
        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutCubic
            }
        }

        property int cellWidth: Config.desktop.iconSize + 48
        property int cellHeight: Config.desktop.iconSize + 56 + Config.desktop.spacingVertical
        property int effectiveWidth: width > 100 ? width : (desktop.screen ? desktop.screen.width - 32 : 1920)
        property int effectiveHeight: height > 100 ? height : (desktop.screen ? desktop.screen.height - (desktop.barSize + 32) : 1080)
        property int maxRows: Math.max(1, Math.floor(effectiveHeight / cellHeight))
        property int maxColumns: Math.max(1, Math.floor(effectiveWidth / cellWidth))

        onMaxRowsChanged: {
            if (maxRows > 1) DesktopService.maxRows = maxRows;
        }
        onMaxColumnsChanged: {
            if (maxColumns > 1) DesktopService.maxColumns = maxColumns;
        }

        Component.onCompleted: {
            if (maxRows > 1) DesktopService.maxRows = maxRows;
            if (maxColumns > 1) DesktopService.maxColumns = maxColumns;
        }

        DropArea {
            id: desktopDropArea
            anchors.fill: parent
            z: 0

            onDropped: drop => {
                if (drop.hasUrls) {
                    let urls = drop.urls;
                    for (let i = 0; i < urls.length; i++) {
                        let urlStr = urls[i].toString();
                        DesktopService.addDroppedUrl(urlStr, drop.x, drop.y, iconContainer.cellWidth, iconContainer.cellHeight);
                    }
                    drop.acceptProposedAction();
                }
            }
        }

        // background click area to deselect or open desktop context menu
        MouseArea {
            id: backgroundMouseArea
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    desktop.selectedPath = "";
                } else if (mouse.button === Qt.RightButton) {
                    desktop.selectedPath = "";
                    desktop.openDesktopMenu();
                }
            }
        }

        Repeater {
            model: DesktopService.items

            delegate: Item {
                id: iconDelegate
                required property string name
                required property string path
                required property string type
                required property string icon
                required property bool isDesktopFile
                required property int col
                required property int row
                required property int index

                width: iconContainer.cellWidth
                height: iconContainer.cellHeight
                z: dragArea.drag.active ? 100 : 1

                property int targetX: col * iconContainer.cellWidth
                property int targetY: row * iconContainer.cellHeight

                x: targetX
                y: targetY

                Behavior on x {
                    enabled: !dragArea.drag.active && Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on y {
                    enabled: !dragArea.drag.active && Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                scale: dragArea.drag.active ? 1.05 : 1.0
                opacity: dragArea.drag.active ? 0.85 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                DesktopIcon {
                    id: iconItem
                    anchors.centerIn: parent
                    width: parent.width - 8
                    height: parent.height - 8

                    itemName: iconDelegate.name
                    itemPath: iconDelegate.path
                    itemType: iconDelegate.type
                    itemIcon: iconDelegate.icon
                    isDesktopFile: iconDelegate.isDesktopFile
                    isSelected: desktop.selectedPath === iconDelegate.path
                    isHovered: dragArea.containsMouse
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true

                    drag.target: iconDelegate
                    drag.axis: Drag.XAndYAxis
                    drag.threshold: 15

                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            if (desktop.selectedPath === iconDelegate.path) {
                                desktop.safeOpenFile(iconDelegate.path, iconDelegate.isDesktopFile);
                            } else {
                                desktop.selectedPath = iconDelegate.path;
                            }
                        } else if (mouse.button === Qt.RightButton) {
                            desktop.selectedPath = iconDelegate.path;
                            desktop.openItemMenu(iconDelegate.path, iconDelegate.name, iconDelegate.isDesktopFile);
                        }
                    }

                    onDoubleClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            desktop.safeOpenFile(iconDelegate.path, iconDelegate.isDesktopFile);
                        }
                    }

                    onReleased: {
                        if (drag.active) {
                            let dropX = iconDelegate.x + iconDelegate.width / 2;
                            let dropY = iconDelegate.y + iconDelegate.height / 2;
                            let targetCol = Math.floor(dropX / iconContainer.cellWidth);
                            let targetRow = Math.floor(dropY / iconContainer.cellHeight);
                            DesktopService.updatePosition(iconDelegate.path, targetCol, targetRow);
                        }
                    }
                }
            }
        }

        // Desktop widgets
        CalendarWidget {
            id: calendarWidget
            z: 2
            visible: Config.desktop?.calendarWidget ?? true
        }
    }

    function openItemMenu(path, name, isDesktopFile) {
        Visibilities.contextMenu.openCustomMenu([
            {
                text: "Open",
                icon: Icons.launch,
                isSeparator: false,
                onTriggered: function() {
                    desktop.safeOpenFile(path, isDesktopFile);
                }
            },
            {
                text: "Show in File Manager",
                icon: Icons.folder,
                isSeparator: false,
                onTriggered: function() {
                    DesktopService.openFileManager();
                }
            },
            {
                isSeparator: true,
                text: ""
            },
            {
                text: "Move to Trash",
                icon: Icons.trash,
                textColor: Colors.overError,
                highlightColor: Colors.error,
                isSeparator: false,
                onTriggered: function() {
                    DesktopService.trashFile(path);
                }
            }
        ], 180, 32, "desktop");
    }

    function openDesktopMenu() {
        let menuItems = [];

        if (!DesktopService.hasItemNamed("Downloads")) {
            menuItems.push({
                text: "Add 'Downloads' Folder",
                icon: Icons.folder,
                isSeparator: false,
                onTriggered: function() {
                    DesktopService.addDownloadsFolder();
                }
            });
        }

        menuItems.push({
            text: "Add Folder Shortcut...",
            icon: Icons.folder,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.browseAndAddFolder();
            }
        });

        menuItems.push({
            text: "Add File Shortcut...",
            icon: Icons.file,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.browseAndAddFile();
            }
        });

        menuItems.push({
            text: "Add App Shortcut...",
            icon: Icons.apps,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.browseAndAddApp();
            }
        });

        menuItems.push({
            isSeparator: true,
            text: ""
        });

        menuItems.push({
            text: "New Folder",
            icon: Icons.folder,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.createNewFolder();
            }
        });

        menuItems.push({
            text: "Open in Terminal",
            icon: Icons.terminal,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.openTerminal();
            }
        });

        menuItems.push({
            text: "Open File Manager",
            icon: Icons.folder,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.openFileManager();
            }
        });

        menuItems.push({
            isSeparator: true,
            text: ""
        });

        menuItems.push({
            text: "Clean Up by Name",
            icon: Icons.sync,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.sortItems(false);
            }
        });

        menuItems.push({
            text: "Clean Up by Kind",
            icon: Icons.sync,
            isSeparator: false,
            onTriggered: function() {
                DesktopService.sortItems(true);
            }
        });

        menuItems.push({
            isSeparator: true,
            text: ""
        });

        menuItems.push({
            text: "Reset Calendar Position",
            icon: Icons.sync,
            isSeparator: false,
            onTriggered: function() {
                WidgetService.resetPosition("calendar");
                if (calendarWidget) {
                    calendarWidget.applyPosition();
                }
            }
        });

        Visibilities.contextMenu.openCustomMenu(menuItems, 220, 32, "desktop");
    }
}
