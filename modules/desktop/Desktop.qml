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
import qs.modules.globals
import qs.config

PanelWindow {
    id: desktop

    property int barSize: 44
    property string barPosition: ["top", "bottom", "left", "right"].includes(Config.bar.position) ? Config.bar.position : "top"
    property string selectedPath: ""
    property var selectedPaths: []
    property bool isGroupDraggingIcons: false
    property point iconGroupOffset: Qt.point(0, 0)
    property real iconGroupMinDx: 0
    property real iconGroupMaxDx: 0
    property real iconGroupMinDy: 0
    property real iconGroupMaxDy: 0
    property rect iconGroupStartBounds: Qt.rect(0, 0, 0, 0)

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
    WlrLayershell.keyboardFocus: (visible && WidgetService.isInteracting && !GlobalStates.commandPaletteVisible) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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

        focus: desktop.visible

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier)) {
                if (event.key === Qt.Key_Z) {
                    if (event.modifiers & Qt.ShiftModifier) {
                        WidgetService.redo();
                    } else {
                        WidgetService.undo();
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Y) {
                    WidgetService.redo();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Escape) {
                WidgetService.clearSelection();
                desktop.selectedPath = "";
                desktop.selectedPaths = [];
                event.accepted = true;
            }
        }

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

        readonly property int screenW: desktop.screen ? desktop.screen.width : (desktop.width > 500 ? desktop.width : 1920)
        readonly property int screenH: desktop.screen ? desktop.screen.height : (desktop.height > 500 ? desktop.height : 1080)

        property int effectiveWidth: {
            if (desktop.barPosition === "left" || desktop.barPosition === "right") {
                return screenW - desktop.barSize - 32;
            }
            return screenW - 32;
        }

        property int effectiveHeight: {
            if (desktop.barPosition === "top" || desktop.barPosition === "bottom") {
                return screenH - desktop.barSize - 32;
            }
            return screenH - 32;
        }

        property int maxRows: Math.max(1, Math.floor(effectiveHeight / cellHeight))
        property int maxColumns: Math.max(1, Math.floor(effectiveWidth / cellWidth))

        onMaxRowsChanged: {
            if (maxRows >= 4) DesktopService.maxRows = maxRows;
        }
        onMaxColumnsChanged: {
            if (maxColumns >= 8) DesktopService.maxColumns = maxColumns;
        }

        Component.onCompleted: {
            if (maxRows >= 4) DesktopService.maxRows = maxRows;
            if (maxColumns >= 8) DesktopService.maxColumns = maxColumns;
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

        // background click and marquee selection area
        MouseArea {
            id: backgroundMouseArea
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            property bool isSelecting: false
            property point selectStart: Qt.point(0, 0)
            property point selectCurrent: Qt.point(0, 0)
            property var baseSelection: []
            property var baseIconSelection: []

            onPressed: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    desktop.selectedPath = "";
                    selectStart = Qt.point(mouse.x, mouse.y);
                    selectCurrent = Qt.point(mouse.x, mouse.y);
                    isSelecting = false;
                    const additive = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                    if (!additive) {
                        WidgetService.clearSelection();
                        desktop.selectedPaths = [];
                    }
                    baseSelection = WidgetService.selectedWidgetIds.slice();
                    baseIconSelection = desktop.selectedPaths.slice();
                } else if (mouse.button === Qt.RightButton) {
                    desktop.selectedPath = "";
                    desktop.selectedPaths = [];
                    WidgetService.clearSelection();
                    desktop.openDesktopMenu();
                }
            }

            onPositionChanged: mouse => {
                if (!(mouse.buttons & Qt.LeftButton)) return;
                selectCurrent = Qt.point(mouse.x, mouse.y);
                const dx = Math.abs(selectCurrent.x - selectStart.x);
                const dy = Math.abs(selectCurrent.y - selectStart.y);
                if (!isSelecting && dx < 4 && dy < 4) return;
                isSelecting = true;

                const rx = Math.min(selectStart.x, selectCurrent.x);
                const ry = Math.min(selectStart.y, selectCurrent.y);
                const rw = Math.abs(selectCurrent.x - selectStart.x);
                const rh = Math.abs(selectCurrent.y - selectStart.y);
                const additive = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                WidgetService.selectWidgetsInRect(rx, ry, rw, rh, additive, baseSelection);

                let nextIcons = additive ? baseIconSelection.slice() : [];
                for (let i = 0; i < DesktopService.items.count; i++) {
                    const entry = DesktopService.items.get(i);
                    const ix = entry.posX >= 0 ? entry.posX : (entry.col * iconContainer.cellWidth);
                    const iy = entry.posY >= 0 ? entry.posY : (entry.row * iconContainer.cellHeight);
                    const iw = iconContainer.cellWidth;
                    const ih = iconContainer.cellHeight;
                    const hits = ix < (rx + rw) && (ix + iw) > rx && iy < (ry + rh) && (iy + ih) > ry;
                    if (hits && nextIcons.indexOf(entry.path) === -1) {
                        nextIcons.push(entry.path);
                    }
                }
                desktop.selectedPaths = nextIcons;
            }

            onReleased: {
                isSelecting = false;
                baseSelection = [];
                baseIconSelection = [];
            }
        }

        // marquee selection rectangle
        Rectangle {
            visible: backgroundMouseArea.isSelecting
            x: Math.min(backgroundMouseArea.selectStart.x, backgroundMouseArea.selectCurrent.x)
            y: Math.min(backgroundMouseArea.selectStart.y, backgroundMouseArea.selectCurrent.y)
            width: Math.abs(backgroundMouseArea.selectCurrent.x - backgroundMouseArea.selectStart.x)
            height: Math.abs(backgroundMouseArea.selectCurrent.y - backgroundMouseArea.selectStart.y)
            radius: 6
            color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.16)
            border.color: Colors.primary
            border.width: 1
            z: 25
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
                required property real posX
                required property real posY
                required property int index

                width: iconContainer.cellWidth
                height: iconContainer.cellHeight
                z: (dragArea.draggingActive || followGroupDrag) ? 100 : 1

                property int targetX: posX >= 0 ? Math.max(0, Math.min(Math.max(0, iconContainer.width - width), Math.round(posX))) : (col * iconContainer.cellWidth)
                property int targetY: posY >= 0 ? Math.max(0, Math.min(Math.max(0, iconContainer.height - height), Math.round(posY))) : (row * iconContainer.cellHeight)
                property real dragOffsetX: 0
                property real dragOffsetY: 0
                readonly property bool isMultiSelected: desktop.selectedPaths.indexOf(iconDelegate.path) !== -1
                readonly property bool followGroupDrag: desktop.isGroupDraggingIcons && isMultiSelected

                x: targetX + (followGroupDrag ? desktop.iconGroupOffset.x : dragOffsetX)
                y: targetY + (followGroupDrag ? desktop.iconGroupOffset.y : dragOffsetY)

                Behavior on x {
                    enabled: !dragArea.draggingActive && !iconDelegate.followGroupDrag && Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on y {
                    enabled: !dragArea.draggingActive && !iconDelegate.followGroupDrag && Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                scale: (dragArea.draggingActive || followGroupDrag) ? 1.05 : 1.0
                opacity: (dragArea.draggingActive || followGroupDrag) ? 0.85 : 1.0

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
                    isSelected: desktop.selectedPath === iconDelegate.path || iconDelegate.isMultiSelected
                    isHovered: dragArea.containsMouse
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true

                    property bool draggingActive: false
                    property bool groupMode: false
                    property point startMouse: Qt.point(0, 0)

                    onPressed: mouse => {
                        if (mouse.button !== Qt.LeftButton) return;
                        WidgetService.isInteracting = true;
                        startMouse = mapToItem(iconContainer, mouse.x, mouse.y);
                        draggingActive = false;
                        groupMode = iconDelegate.isMultiSelected && desktop.selectedPaths.length > 1;
                        if (groupMode) {
                            let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
                            for (let i = 0; i < DesktopService.items.count; i++) {
                                const entry = DesktopService.items.get(i);
                                if (desktop.selectedPaths.indexOf(entry.path) !== -1) {
                                    const ex = entry.posX >= 0 ? Math.max(0, Math.min(Math.max(0, iconContainer.width - iconContainer.cellWidth), Math.round(entry.posX))) : (entry.col * iconContainer.cellWidth);
                                    const ey = entry.posY >= 0 ? Math.max(0, Math.min(Math.max(0, iconContainer.height - iconContainer.cellHeight), Math.round(entry.posY))) : (entry.row * iconContainer.cellHeight);
                                    if (ex < minX) minX = ex;
                                    if (ex > maxX) maxX = ex;
                                    if (ey < minY) minY = ey;
                                    if (ey > maxY) maxY = ey;
                                }
                            }
                            desktop.iconGroupMinDx = -minX;
                            desktop.iconGroupMaxDx = Math.max(0, (iconContainer.width - iconContainer.cellWidth) - maxX);
                            desktop.iconGroupMinDy = -minY;
                            desktop.iconGroupMaxDy = Math.max(0, (iconContainer.height - iconContainer.cellHeight) - maxY);
                            desktop.iconGroupStartBounds = Qt.rect(minX, minY, (maxX - minX) + iconContainer.cellWidth, (maxY - minY) + iconContainer.cellHeight);
                        }
                    }

                    onPositionChanged: mouse => {
                        if (!(mouse.buttons & Qt.LeftButton)) return;
                        const cur = mapToItem(iconContainer, mouse.x, mouse.y);
                        let dx = cur.x - startMouse.x;
                        let dy = cur.y - startMouse.y;
                        if (!draggingActive && Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
                        draggingActive = true;

                        const axisLock = ((mouse.modifiers & Qt.ShiftModifier) !== 0) || ((Qt.application.keyboardModifiers & Qt.ShiftModifier) !== 0);
                        if (axisLock) {
                            if (Math.abs(dx) >= Math.abs(dy)) dy = 0;
                            else dx = 0;
                        }

                        if (groupMode) {
                            desktop.isGroupDraggingIcons = true;
                            let clampedDx = Math.max(desktop.iconGroupMinDx, Math.min(desktop.iconGroupMaxDx, dx));
                            let clampedDy = Math.max(desktop.iconGroupMinDy, Math.min(desktop.iconGroupMaxDy, dy));
                            const b = desktop.iconGroupStartBounds;
                            const snapped = WidgetService.computeSnapForMove(
                                "", b.x + clampedDx, b.y + clampedDy, b.width, b.height,
                                10, true, iconContainer.cellWidth, iconContainer.cellHeight, desktop.selectedPaths
                            );
                            if (!(axisLock && dx === 0)) {
                                clampedDx = Math.max(desktop.iconGroupMinDx, Math.min(desktop.iconGroupMaxDx, snapped.x - b.x));
                            }
                            if (!(axisLock && dy === 0)) {
                                clampedDy = Math.max(desktop.iconGroupMinDy, Math.min(desktop.iconGroupMaxDy, snapped.y - b.y));
                            }
                            desktop.iconGroupOffset = Qt.point(clampedDx, clampedDy);
                        } else {
                            const maxX = Math.max(0, iconContainer.width - iconDelegate.width);
                            const maxY = Math.max(0, iconContainer.height - iconDelegate.height);
                            const rawX = Math.max(0, Math.min(maxX, iconDelegate.targetX + dx));
                            const rawY = Math.max(0, Math.min(maxY, iconDelegate.targetY + dy));
                            const snapped = WidgetService.computeSnapForMove(
                                iconDelegate.path, rawX, rawY, iconDelegate.width, iconDelegate.height,
                                10, true, iconContainer.cellWidth, iconContainer.cellHeight
                            );
                            const finalX = Math.max(0, Math.min(maxX, (axisLock && dx === 0) ? iconDelegate.targetX : snapped.x));
                            const finalY = Math.max(0, Math.min(maxY, (axisLock && dy === 0) ? iconDelegate.targetY : snapped.y));
                            iconDelegate.dragOffsetX = finalX - iconDelegate.targetX;
                            iconDelegate.dragOffsetY = finalY - iconDelegate.targetY;
                        }
                    }

                    onClicked: mouse => {
                        if (draggingActive) return;
                        if (mouse.button === Qt.LeftButton) {
                            if (desktop.selectedPath === iconDelegate.path) {
                                desktop.safeOpenFile(iconDelegate.path, iconDelegate.isDesktopFile);
                            } else {
                                desktop.selectedPath = iconDelegate.path;
                                desktop.selectedPaths = [];
                                WidgetService.clearSelection();
                            }
                        } else if (mouse.button === Qt.RightButton) {
                            desktop.selectedPath = iconDelegate.path;
                            desktop.selectedPaths = [];
                            desktop.openItemMenu(iconDelegate.path, iconDelegate.name, iconDelegate.isDesktopFile);
                        }
                    }

                    onDoubleClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            desktop.safeOpenFile(iconDelegate.path, iconDelegate.isDesktopFile);
                        }
                    }

                    onReleased: {
                        WidgetService.isInteracting = false;
                        if (draggingActive) {
                            draggingActive = false;
                            if (groupMode && desktop.isGroupDraggingIcons) {
                                const dx = desktop.iconGroupOffset.x;
                                const dy = desktop.iconGroupOffset.y;
                                desktop.isGroupDraggingIcons = false;
                                desktop.iconGroupOffset = Qt.point(0, 0);
                                DesktopService.moveGroupFreePositions(desktop.selectedPaths, dx, dy, iconContainer.cellWidth, iconContainer.cellHeight);
                            } else {
                                desktop.selectedPaths = [];
                                const newX = iconDelegate.targetX + iconDelegate.dragOffsetX;
                                const newY = iconDelegate.targetY + iconDelegate.dragOffsetY;
                                iconDelegate.dragOffsetX = 0;
                                iconDelegate.dragOffsetY = 0;
                                DesktopService.updateFreePosition(iconDelegate.path, newX, newY, iconContainer.cellWidth, iconContainer.cellHeight);
                            }
                        }
                        groupMode = false;
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

        Repeater {
            model: WidgetService.photoWidgets
            delegate: PhotoWidget {
                required property var modelData
                widgetData: modelData
                z: 2
            }
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
            text: "Add Photo Widget...",
            icon: Icons.image,
            isSeparator: false,
            onTriggered: function() {
                WidgetService.browseAndAddPhotoWidget(32, 300);
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

        if (WidgetService.canUndo || WidgetService.canRedo) {
            menuItems.push({
                isSeparator: true,
                text: ""
            });
            if (WidgetService.canUndo) {
                menuItems.push({
                    text: "Undo",
                    icon: Icons.arrowCounterClockwise,
                    isSeparator: false,
                    onTriggered: function() {
                        WidgetService.undo();
                    }
                });
            }
            if (WidgetService.canRedo) {
                menuItems.push({
                    text: "Redo",
                    icon: Icons.sync,
                    isSeparator: false,
                    onTriggered: function() {
                        WidgetService.redo();
                    }
                });
            }
        }

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
