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
        color: root.isHovered ? "#1b1b26" : "#13131c"
        border.color: root.isCritical ? Colors.red : (root.isHovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
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
            spacing: 6

            // top header row
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                spacing: 6

                // app icon or web favicon
                Item {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20

                    NotificationAppIcon {
                        id: appIconFallback
                        anchors.fill: parent
                        size: 20
                        scale: 1
                        radius: 5
                        appIcon: root.effectiveAppIcon
                        image: ""
                        summary: root.notifData?.summary ?? ""
                        urgency: root.notifData?.urgency ?? NotificationUrgency.Normal
                        visible: !faviconRect.visible
                    }

                    Rectangle {
                        id: faviconRect
                        anchors.fill: parent
                        radius: 5
                        color: "#0a0a12"
                        visible: root.faviconUrl !== "" && faviconImage.status === Image.Ready

                        Image {
                            id: faviconImage
                            anchors.fill: parent
                            anchors.margins: 2
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            source: root.faviconUrl
                        }
                    }
                }

                Text {
                    text: root.displayAppName
                    font.family: Config.theme.font ?? Config.defaultFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: root.isCritical ? Colors.red : Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.7)
                    elide: Text.ElideRight
                    Layout.maximumWidth: 160
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

                // single dismiss button, visible on hover
                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    opacity: root.isHovered ? 1 : 0
                    visible: opacity > 0
                    color: closeHover.containsMouse ? (closeHover.pressed ? Qt.rgba(1, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.14)) : Qt.rgba(1, 1, 1, 0.06)

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
                        color: closeHover.containsMouse ? Colors.red : Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.6)
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

            // summary title
            Text {
                Layout.fillWidth: true
                visible: (root.notifData?.summary ?? "") !== ""
                text: root.notifData?.summary ?? ""
                font.family: Config.theme.font ?? Config.defaultFont
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Colors.overBackground
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
                color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.65)
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
                lineHeight: 1.15
                linkColor: Styling.srItem("overprimary")
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // optional attached image
            ClippingRectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                visible: (root.notifData?.image ?? "") !== "" && !root.notifData.image.includes("/tmp/")
                radius: 8
                color: "#0a0a0f"

                Image {
                    anchors.fill: parent
                    source: root.notifData?.image ?? ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                }
            }
        }
    }
}
