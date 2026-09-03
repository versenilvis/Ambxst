pragma ComponentBehavior: Bound
import QtQuick
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

    readonly property color cardBg: "#0c0c11"
    readonly property color cardBorder: Qt.rgba(1, 1, 1, 0.08)

    Rectangle {
        id: mainCard
        anchors.fill: parent
        radius: 20
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // header row
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                Text {
                    text: "Notifications"
                    font.family: Config.theme.font ?? Config.defaultFont
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: Colors.overBackground
                }

                Rectangle {
                    visible: Notifications.list.length > 0
                    width: Math.max(20, countText.implicitWidth + 10)
                    height: 18
                    radius: 9
                    color: Qt.rgba(1, 1, 1, 0.08)

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: Notifications.list.length >= 99 ? "99+" : Notifications.list.length.toString()
                        font.family: Config.theme.font ?? Config.defaultFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.7)
                    }
                }

                // spacer pushing buttons to far right
                Item {
                    Layout.fillWidth: true
                }

                // dnd toggle button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: dndHover.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : (Notifications.silent ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.15) : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: Notifications.silent ? Icons.bellZ : Icons.bell
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: Notifications.silent ? Colors.red : Colors.overBackground

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation { duration: Config.animDuration / 2 }
                        }
                    }

                    MouseArea {
                        id: dndHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifications.silent = !Notifications.silent
                    }

                    StyledToolTip {
                        show: dndHover.containsMouse
                        tooltipText: Notifications.silent ? "Do Not Disturb (On)" : "Do Not Disturb (Off)"
                    }
                }

                // clear all button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: clearHover.pressed ? Qt.rgba(1, 0, 0, 0.25) : (clearHover.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: Icons.broom
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: clearHover.pressed ? Colors.red : Colors.overBackground
                    }

                    MouseArea {
                        id: clearHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: notifContent.discardAllWithAnimation()
                    }

                    StyledToolTip {
                        show: clearHover.containsMouse
                        tooltipText: "Clear all notifications"
                    }
                }
            }

            // subtle divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            // notification content list
            NotifCenterContent {
                id: notifContent
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
