pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.notifications
import qs.config

Item {
    id: root

    readonly property var chronologicalList: {
        const raw = Notifications.list || [];
        return raw.slice().sort((a, b) => (b.time || 0) - (a.time || 0));
    }

    // smooth wheel scroll state
    property real targetContentY: 0
    property bool isWheelScrolling: false

    Timer {
        id: resetWheelScrollingTimer
        interval: 220
        onTriggered: root.isWheelScrolling = false
    }

    Connections {
        target: notificationList
        function onContentYChanged() {
            if (!root.isWheelScrolling) {
                root.targetContentY = notificationList.contentY;
            }
        }
    }

    Behavior on targetContentY {
        enabled: root.isWheelScrolling
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    onTargetContentYChanged: {
        if (root.isWheelScrolling) {
            notificationList.contentY = targetContentY;
        }
    }

    function discardAllWithAnimation() {
        const children = notificationList.contentItem.children;
        if (!children || children.length === 0) {
            Notifications.discardAllNotifications();
            return;
        }

        let hasAnim = false;
        for (let i = 0; i < children.length; i++) {
            if (children[i] && children[i].dismissWithAnimation) {
                children[i].dismissWithAnimation();
                hasAnim = true;
            }
        }

        if (hasAnim) {
            discardAllTimer.restart();
        } else {
            Notifications.discardAllNotifications();
        }
    }

    Timer {
        id: discardAllTimer
        interval: 200
        repeat: false
        onTriggered: Notifications.discardAllNotifications()
    }

    // empty state
    Column {
        anchors.centerIn: parent
        spacing: 14
        visible: root.chronologicalList.length === 0

        Image {
            source: Qt.resolvedUrl("../../assets/ambxst/ambxst-logo.svg")
            opacity: 0.14
            sourceSize.width: 52
            sourceSize.height: 52
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            layer.enabled: true
            layer.effect: MultiEffect {
                brightness: 1.0
                colorization: 1.0
                colorizationColor: Colors.overBackground
            }
        }

        Text {
            text: "No notifications"
            font.family: Config.theme.font ?? Config.defaultFont
            font.pixelSize: Config.theme.fontSize
            font.weight: Font.Medium
            color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.35)
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // chronological notification list
    ListView {
        id: notificationList
        anchors.fill: parent
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: root.chronologicalList.length > 0

        model: root.chronologicalList

        // subtle scroll bar
        ScrollBar.vertical: ScrollBar {
            id: scrollBar
            policy: ScrollBar.AsNeeded
            width: 4
            contentItem: Rectangle {
                implicitWidth: 4
                radius: 2
                color: scrollBar.pressed ? Qt.rgba(1, 1, 1, 0.4) : (scrollBar.hovered ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12))
            }
        }

        delegate: NotifCardItem {
            required property var modelData
            required property int index
            width: notificationList.width
            notifData: modelData
        }
    }

    // smooth wheel scroll handler
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true

        onWheel: wheel => {
            if (notificationList.contentHeight > notificationList.height) {
                root.isWheelScrolling = true;
                resetWheelScrollingTimer.restart();
                const maxScroll = Math.max(0, notificationList.contentHeight - notificationList.height);
                const step = wheel.angleDelta.y * 1.5;
                root.targetContentY = Math.max(0, Math.min(maxScroll, root.targetContentY - step));
                wheel.accepted = true;
            } else {
                wheel.accepted = false;
            }
        }
    }
}
