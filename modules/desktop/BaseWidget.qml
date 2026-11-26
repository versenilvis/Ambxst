pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    // Unique identifier for position saving and identification
    required property string widgetId

    // Display metadata
    property string title: ""
    property string icon: ""
    property bool showHeader: false

    // Positioning and persistence
    property int defaultX: 32
    property int defaultY: 32
    property bool draggable: true
    property bool locked: false
    property bool persistToWidgetService: true
    property bool disableAnimations: false
    property bool _clamping: false
    property bool _groupMoving: false
    property real savedX: defaultX
    property real savedY: defaultY

    signal positionChangedByUser(real newX, real newY)
    signal lockChangedByUser(bool isLocked)

    // Styling
    property bool hasCardBackground: true
    property int cornerRadius: 20
    property color cardBg: "#0c0c11"
    property color cardBorder: Qt.rgba(1, 1, 1, 0.08)

    // Interaction states
    readonly property bool isHovered: hoverArea.containsMouse
    readonly property bool isDragging: dragArea.draggingActive
    readonly property bool isSelected: WidgetService.selectedWidgetIds.indexOf(root.widgetId) !== -1

    // Main content slot
    default property alias content: contentContainer.data

    scale: isDragging ? 1.02 : 1.0
    opacity: isDragging ? 0.92 : 1.0

    Behavior on scale {
        enabled: Config.animDuration > 0
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    Behavior on opacity {
        enabled: Config.animDuration > 0
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    Behavior on x {
        enabled: !root.isDragging && !root.disableAnimations && !root._clamping && !root._groupMoving && Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on y {
        enabled: !root.isDragging && !root.disableAnimations && !root._clamping && !root._groupMoving && Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    function clampPositionToParent() {
        if (!root.parent || root.parent.width <= 0 || root.parent.height <= 0) return;
        root._clamping = true;
        const maxX = Math.max(0, root.parent.width - root.width);
        const maxY = Math.max(0, root.parent.height - root.height);
        root.x = Math.max(0, Math.min(maxX, root.savedX));
        root.y = Math.max(0, Math.min(maxY, root.savedY));
        root._clamping = false;
    }

    // Load saved position from WidgetService
    function applyPosition() {
        if (!root.persistToWidgetService) return;
        let pos = WidgetService.getPosition(root.widgetId, root.defaultX, root.defaultY);
        root.savedX = pos.x;
        root.savedY = pos.y;
        root.locked = pos.locked;
        root.clampPositionToParent();
    }

    Connections {
        target: root.parent
        ignoreUnknownSignals: true
        function onWidthChanged() {
            if (!root.isDragging && !root.disableAnimations) {
                root.clampPositionToParent();
            }
        }
        function onHeightChanged() {
            if (!root.isDragging && !root.disableAnimations) {
                root.clampPositionToParent();
            }
        }
    }

    Connections {
        target: WidgetService
        function onPositionsReady() {
            if (!root.isDragging) {
                root.applyPosition();
            }
        }
    }

    Component.onCompleted: {
        WidgetService.registerWidget(root.widgetId, root);
        if (WidgetService.positionsLoaded) {
            root.applyPosition();
        }
    }

    Component.onDestruction: {
        WidgetService.unregisterWidget(root.widgetId);
    }

    // Optional card background
    Rectangle {
        id: cardBgRect
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.cardBg
        border.color: root.isSelected ? Colors.primary : root.cardBorder
        border.width: root.isSelected ? 2 : 1
        visible: root.hasCardBackground || root.isSelected
    }

    // Background drag mouse area
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property bool draggingActive: false
        property bool groupDragging: false
        property point startMouse: Qt.point(0, 0)
        property real startX: 0
        property real startY: 0

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton || !root.draggable || root.locked || !root.parent) return;
            startMouse = mapToItem(root.parent, mouse.x, mouse.y);
            startX = root.x;
            startY = root.y;
            draggingActive = false;
            groupDragging = root.isSelected && WidgetService.selectedWidgetIds.length > 1;
            if (!root.isSelected) {
                WidgetService.clearSelection();
            }
            if (groupDragging) {
                WidgetService.beginGroupMove();
            }
        }

        onPositionChanged: mouse => {
            if (!(mouse.buttons & Qt.LeftButton) || !root.draggable || root.locked || !root.parent) return;
            const cur = mapToItem(root.parent, mouse.x, mouse.y);
            let dx = cur.x - startMouse.x;
            let dy = cur.y - startMouse.y;
            if (!draggingActive && Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
            draggingActive = true;

            const axisLock = ((mouse.modifiers & Qt.ShiftModifier) !== 0) || ((Qt.application.keyboardModifiers & Qt.ShiftModifier) !== 0);
            if (axisLock) {
                if (Math.abs(dx) >= Math.abs(dy)) {
                    dy = 0;
                } else {
                    dx = 0;
                }
            }

            if (groupDragging) {
                WidgetService.moveGroupBy(dx, dy);
                return;
            }

            const maxX = Math.max(0, root.parent.width - root.width);
            const maxY = Math.max(0, root.parent.height - root.height);
            const rawX = Math.max(0, Math.min(maxX, startX + dx));
            const rawY = Math.max(0, Math.min(maxY, startY + dy));
            const snapped = WidgetService.computeSnapForMove(root.widgetId, rawX, rawY, root.width, root.height, 10);
            root.x = Math.max(0, Math.min(maxX, (axisLock && dx === 0) ? startX : snapped.x));
            root.y = Math.max(0, Math.min(maxY, (axisLock && dy === 0) ? startY : snapped.y));
        }

        onReleased: {
            if (draggingActive) {
                draggingActive = false;
                if (groupDragging) {
                    groupDragging = false;
                    WidgetService.commitGroupMove();
                    return;
                }
                root.savedX = root.x;
                root.savedY = root.y;
                root.positionChangedByUser(root.x, root.y);
                if (root.persistToWidgetService) {
                    WidgetService.setPosition(root.widgetId, root.x, root.y, root.locked);
                }
            }
            groupDragging = false;
        }

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.openWidgetMenu();
            }
        }
    }

    // Hover tracker for controls
    HoverHandler {
        id: hoverArea
    }

    // Container for widget content
    Item {
        id: contentContainer
        anchors.fill: parent
        z: 1
    }

    // Header bar if enabled
    Item {
        id: headerItem
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        visible: root.showHeader
        z: 2

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8

            Text {
                visible: root.icon !== ""
                text: root.icon
                font.family: Icons.font
                font.pixelSize: 14
                color: Colors.primary
            }

            Text {
                text: root.title
                font.family: Config.theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Colors.overBackground
                Layout.fillWidth: true
            }

            Item {
                width: 24
                height: 24

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: lockMouseArea.containsMouse ? "#20ffffff" : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: root.locked ? Icons.lock : Icons.dragHandle
                    font.family: Icons.font
                    font.pixelSize: 13
                    color: root.locked ? Colors.primary : Colors.outline
                }

                MouseArea {
                    id: lockMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.locked = !root.locked;
                        root.lockChangedByUser(root.locked);
                        if (root.persistToWidgetService) {
                            WidgetService.setPosition(root.widgetId, root.x, root.y, root.locked);
                        }
                    }
                }
            }
        }
    }

    // Floating lock status button in corner when hovered (when showHeader is false)
    Item {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: 26
        height: 26
        visible: !root.showHeader && (root.isHovered || root.locked)
        z: 10
        opacity: root.isHovered ? 1.0 : (root.locked ? 0.35 : 0.0)

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: 150 }
        }

        Rectangle {
            anchors.fill: parent
            radius: 13
            color: quickLockMouseArea.containsMouse ? "#2a2a38" : "#181824"
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
        }

        Text {
            anchors.centerIn: parent
            text: root.locked ? Icons.lock : Icons.dragHandle
            font.family: Icons.font
            font.pixelSize: 12
            color: root.locked ? Colors.primary : Colors.outline
        }

        MouseArea {
            id: quickLockMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.locked = !root.locked;
                WidgetService.setPosition(root.widgetId, root.x, root.y, root.locked);
            }
        }
    }

    function openWidgetMenu() {
        let items = [
            {
                text: root.locked ? "Unlock Position" : "Lock Position",
                icon: root.locked ? Icons.lock : Icons.lock,
                isSeparator: false,
                onTriggered: function() {
                    root.locked = !root.locked;
                    WidgetService.setPosition(root.widgetId, root.x, root.y, root.locked);
                }
            },
            {
                text: "Reset Position",
                icon: Icons.sync,
                isSeparator: false,
                onTriggered: function() {
                    root.x = root.defaultX;
                    root.y = root.defaultY;
                    root.locked = false;
                    WidgetService.resetPosition(root.widgetId);
                }
            }
        ];
        Visibilities.contextMenu.openCustomMenu(items);
    }
}
