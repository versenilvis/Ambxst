pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    property bool popupOpen: notifPopup.isOpen

    property bool isVerticalLayout: false
    readonly property bool isCurrentLayout: isVerticalLayout === (bar.orientation === "vertical")

    Connections {
        target: GlobalStates
        function onToggleNotifications() {
            if (!root.isCurrentLayout) return;
            if (root.bar.screen && Hyprland.focusedMonitor && root.bar.screen.name !== Hyprland.focusedMonitor.name) return;
            notifPopup.toggle();
        }
    }

    readonly property int notifCount: Notifications.list.length
    readonly property string badgeText: notifCount >= 99 ? "99" : notifCount.toString()

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    // main button
    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: Notifications.silent ? Icons.bellZ : Icons.bell
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Styling.srItem("overprimary")

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        // notification count badge
        Rectangle {
            visible: root.notifCount > 0
            width: root.notifCount >= 10 ? 18 : 14
            height: 14
            radius: 7
            color: Colors.red
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 2
            anchors.rightMargin: 2

            Text {
                anchors.centerIn: parent
                text: root.badgeText
                font.family: Config.defaultFont
                font.pixelSize: 8
                font.weight: Font.Bold
                color: "#ffffff"
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            onClicked: notifPopup.toggle()
        }

        StyledToolTip {
            show: root.isHovered && !root.popupOpen
            tooltipText: root.notifCount > 0 ? root.notifCount + " notification" + (root.notifCount > 1 ? "s" : "") : "Notification center"
        }
    }

    // notification popup matching calendar popup structure
    BarPopup {
        id: notifPopup
        anchorItem: buttonBg
        bar: root.bar
        variant: "transparent"
        popupPadding: 0
        horizontalAlignment: "right"
        shadowMargin: 8

        contentWidth: 380
        contentHeight: Math.max(300, (root.bar.screen?.height ?? Screen.height) - (root.vertical ? 48 : 64))

        NotifCenterCard {
            id: notifCard
            width: notifPopup.contentWidth
            height: notifPopup.contentHeight
        }
    }
}
