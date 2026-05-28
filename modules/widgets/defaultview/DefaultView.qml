import QtQuick
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.services
import qs.modules.notch
import qs.modules.components
import qs.config

Item {
    id: root
    anchors.top: parent.top
    focus: false

    // Layout constants
    readonly property int notificationPadding: 16
    readonly property int notificationPaddingBottom: 12
    readonly property int notificationPaddingTop: 12

    // State
    readonly property bool hasActiveNotifications: Notifications.popupList.length > 0
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    property bool notchHovered: false
    property bool isNavigating: false

    HoverHandler {
        id: contentHoverHandler
    }

    readonly property bool expandedState: contentHoverHandler.hovered || notchHovered || isNavigating || Visibilities.playerMenuOpen

    property real mainRowMargin: (Config.notchTheme === "island" && hasActiveNotifications) ? 64 : 16

    Behavior on mainRowMargin {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    // Computed dimensions
    //     readonly property real mainRowContentWidth: 200 + userInfo.width + separator1.width + separator2.width + notifIndicator.width + (mainRow.spacing * 4) + mainRowMargin
    readonly property real mainRowContentWidth: 180
    readonly property real mainRowHeight: Config.showBackground ? (Config.notchTheme === "island" ? 36 : 44) : (Config.notchTheme === "island" ? 36 : 40)
    readonly property real notificationMinWidth: expandedState ? 450 : 380
    readonly property real notificationContainerHeight: notificationView.implicitHeight + notificationPaddingTop + notificationPaddingBottom

    implicitWidth: Math.round(notchContainer.notificationExpanded
        ? Math.max(notificationMinWidth + (notificationPadding * 2), mainRowContentWidth)
        : mainRowContentWidth)

    implicitHeight: notchContainer.notificationExpanded ? notificationContainerHeight : mainRowHeight

    Behavior on implicitWidth {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: notchContainer.notificationExpanded ? Config.animDuration * 2.0 : Config.animDuration * 1.3
            easing.type: Easing.OutQuart
        }
    }

    Behavior on implicitHeight {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: notchContainer.notificationExpanded ? Config.animDuration * 2.0 : Config.animDuration * 1.3
            easing.type: Easing.OutQuart
        }
    }

    Keys.onPressed: event => {
        if (expandedState && activePlayer) {
            if (event.key === Qt.Key_Space) {
                activePlayer.togglePlaying();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left && activePlayer.canSeek) {
                activePlayer.position = Math.max(0, activePlayer.position - 10);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right && activePlayer.canSeek) {
                activePlayer.position = Math.min(activePlayer.length, activePlayer.position + 10);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up && activePlayer.canGoPrevious) {
                activePlayer.previous();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down && activePlayer.canGoNext) {
                activePlayer.next();
                event.accepted = true;
            }
        }
    }

    Item {
        anchors.fill: parent

        // mainRow - ẩn khi có notification
        Row {
            id: mainRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - mainRowMargin
            height: mainRowHeight
            spacing: 4

            opacity: hasActiveNotifications ? 0 : 1
            visible: opacity > 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: hasActiveNotifications ? Config.animDuration * 0.2 : Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }


        }

        // notification container - drop xuống từ trên
        Item {
            id: notificationContainer
            width: parent.width
            height: notificationContainerHeight
            anchors.verticalCenter: parent.verticalCenter

            // drop từ trên xuống - sync với bung ra của notchRect
            anchors.verticalCenterOffset: notchContainer.notificationExpanded ? 0 : -12

            Behavior on anchors.verticalCenterOffset {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: [0.175, 0.885, 0.32, 1.4, 1.0, 1.0]
                }
            }

            opacity: notchContainer.notificationExpanded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: notchContainer.notificationExpanded ? Config.animDuration * 0.35 : Config.animDuration * 0.5
                    easing.type: Easing.OutQuart
                }
            }

            NotchNotificationView {
                id: notificationView
                anchors.fill: parent
                anchors.topMargin: notificationPaddingTop
                anchors.leftMargin: notificationPadding
                anchors.rightMargin: notificationPadding
                anchors.bottomMargin: notificationPaddingBottom
                notchHovered: expandedState
                onIsNavigatingChanged: root.isNavigating = isNavigating
            }
        }
    }
}
