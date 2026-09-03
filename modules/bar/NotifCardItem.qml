pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.notifications
import qs.config
import "../notifications/notification_utils.js" as NotificationUtils

Item {
    id: root

    required property var notifData

    readonly property bool isHovered: cardMouseArea.containsMouse || closeHover.containsMouse
    readonly property bool isCritical: notifData && notifData.urgency === NotificationUrgency.Critical
    readonly property string timeStr: NotificationUtils.getFriendlyNotifTimeString(notifData?.time ?? 0)
    readonly property string processedBody: NotificationUtils.processNotificationBody(notifData?.body ?? "", notifData?.appName ?? "")

    // website info detection
    readonly property var websiteInfo: NotificationUtils.getWebsiteInfo(root.notifData?.body ?? "", root.notifData?.summary ?? "", root.notifData?.appName ?? "")
    readonly property string displayAppName: websiteInfo.name || (root.notifData?.appName || "System")
    readonly property string faviconUrl: websiteInfo.favicon || ""

    // resolve fallback icon name when appIcon is empty
    readonly property string effectiveAppIcon: {
        if (root.notifData?.appIcon) return root.notifData.appIcon;
        const app = (root.notifData?.appName || "").toLowerCase();
        if (app.includes("grimblast") || app.includes("screenshot")) return "camera-photo";
        if (app.includes("helium")) return "helium";
        if (app.includes("chrome")) return "google-chrome";
        if (app.includes("brave")) return "brave-browser";
        if (app.includes("firefox")) return "firefox";
        return app;
    }

    implicitWidth: parent ? parent.width : 360
    implicitHeight: cardRect.implicitHeight
    height: implicitHeight

    Behavior on implicitHeight {
        enabled: Config.animDuration > 0
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Behavior on opacity {
        enabled: Config.animDuration > 0
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    function dismissWithAnimation() {
        dismissAnim.start();
    }

    ParallelAnimation {
        id: dismissAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: cardRect; property: "scale"; to: 0.92; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "implicitHeight"; to: 0; duration: 180; easing.type: Easing.OutCubic }
        onFinished: {
            if (root.notifData) {
                Notifications.discardNotification(root.notifData.id);
            }
        }
    }

    Rectangle {
        id: cardRect
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: mainLayout.implicitHeight + 20

        radius: 14
        color: root.isHovered ? "#161616" : "#0d0d0d"
        border.color: root.isCritical ? Colors.red : (root.isHovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08))
        border.width: 1
        clip: true

        Behavior on color {
            enabled: Config.animDuration > 0
            ColorAnimation { duration: 120 }
        }

        Behavior on border.color {
            enabled: Config.animDuration > 0
            ColorAnimation { duration: 120 }
        }

        // click card to trigger action without auto-discarding
        MouseArea {
            id: cardMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    root.dismissWithAnimation();
                } else if (mouse.button === Qt.LeftButton && root.notifData) {
                    // pass false to autoDiscard so notification remains in history
                    Notifications.attemptInvokeAction(root.notifData.id, "default", false);
                }
            }
        }

        ColumnLayout {
            id: mainLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            // top header row
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                spacing: 6

                Text {
                    text: root.displayAppName
                    font.family: Config.theme.font ?? Config.defaultFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: root.isCritical ? Colors.red : Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.6)
                    elide: Text.ElideRight
                    Layout.maximumWidth: 180
                }

                Text {
                    text: "•"
                    font.pixelSize: 10
                    color: Qt.rgba(1, 1, 1, 0.25)
                    visible: root.timeStr !== ""
                }

                Text {
                    text: root.timeStr
                    font.family: Config.theme.font ?? Config.defaultFont
                    font.pixelSize: 10
                    color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.45)
                    visible: root.timeStr !== ""
                }

                Item { Layout.fillWidth: true }

                // single dismiss button, always visible with subtle opacity, pops on hover
                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    opacity: root.isHovered ? 1.0 : 0.4
                    color: closeHover.containsMouse ? (closeHover.pressed ? Qt.rgba(1, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.14)) : (root.isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: 120 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.cancel || "✕"
                        font.family: Icons.font
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: closeHover.containsMouse ? Colors.red : (root.isHovered ? Colors.overBackground : Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.6))
                    }

                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissWithAnimation()
                    }
                }
            }

            // main content row with avatar and message
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.alignment: Qt.AlignTop

                // avatar or app icon
                Item {
                    id: avatarContainer
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignTop

                    NotificationAppIcon {
                        anchors.fill: parent
                        size: 40
                        radius: (root.notifData?.image ?? "") !== "" ? 20 : 10
                        appIcon: root.faviconUrl || root.effectiveAppIcon
                        image: root.notifData?.image ?? ""
                        summary: root.notifData?.summary ?? ""
                        urgency: root.notifData?.urgency ?? NotificationUrgency.Normal
                    }
                }

                // text column
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Layout.alignment: Qt.AlignTop

                    // summary title
                    Text {
                        Layout.fillWidth: true
                        visible: (root.notifData?.summary ?? "") !== ""
                        text: root.notifData?.summary ?? ""
                        font.family: Config.theme.font ?? Config.defaultFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: (root.notifData?.image ?? "") !== "" ? Styling.srItem("overprimary") : Colors.overBackground
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    // notification body
                    Text {
                        Layout.fillWidth: true
                        visible: root.processedBody !== ""
                        text: root.processedBody
                        font.family: Config.theme.font ?? Config.defaultFont
                        font.pixelSize: 12
                        color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.7)
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        lineHeight: 1.15
                        linkColor: Styling.srItem("overprimary")
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }
        }
    }
}
