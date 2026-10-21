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

    // Styling
    property bool hasCardBackground: true
    property int cornerRadius: 20
    property color cardBg: "#0c0c11"
    property color cardBorder: Qt.rgba(1, 1, 1, 0.08)

    // Interaction states
    readonly property bool isHovered: hoverArea.containsMouse
    readonly property bool isDragging: dragArea.drag.active

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
        enabled: !root.isDragging && Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on y {
        enabled: !root.isDragging && Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    // Load saved position from WidgetService
    function applyPosition() {
        let pos = WidgetService.getPosition(root.widgetId, root.defaultX, root.defaultY);
        root.x = pos.x;
        root.y = pos.y;
        root.locked = pos.locked;
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
        if (WidgetService.positionsLoaded) {
            root.applyPosition();
        }
    }

    // Optional card background
    Rectangle {
        id: cardBgRect
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1
        visible: root.hasCardBackground
    }

    // Background drag mouse area
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        drag.target: (root.draggable && !root.locked) ? root : null
        drag.axis: Drag.XAndYAxis
        drag.threshold: 8
        drag.minimumX: 0
        drag.maximumX: root.parent ? Math.max(0, root.parent.width - root.width) : 1920
        drag.minimumY: 0
        drag.maximumY: root.parent ? Math.max(0, root.parent.height - root.height) : 1080

        onReleased: {
            if (drag.active) {
                WidgetService.setPosition(root.widgetId, root.x, root.y, root.locked);
            }
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
                        WidgetService.setPosition(root.widgetId, root.x, root.y, root.locked);
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
