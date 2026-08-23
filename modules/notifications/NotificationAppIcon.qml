pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.modules.theme
import qs.config

ClippingRectangle {
    id: root
    property string appIcon: ""
    property string summary: ""
    property int urgency: NotificationUrgency.Normal
    property string image: ""
    property real scale: 1
    property real size: 48 * scale
    property real appIconScale: scale
    property real smallAppIconScale: 0.4
    property real appIconSize: size * appIconScale
    property real smallAppIconSize: size * smallAppIconScale
    property bool usingAppIconFallback: false

    implicitWidth: size
    implicitHeight: size
    radius: Styling.radius(-8)
    color: "transparent"

    function getIconSource(iconName) {
        if (!iconName) return "";
        
        // Strip any query parameters like ?fallback=... which break Quickshell icon resolution
        let cleanIcon = iconName;
        let queryIdx = cleanIcon.indexOf('?');
        if (queryIdx !== -1) {
            cleanIcon = cleanIcon.substring(0, queryIdx);
        }
        
        if (cleanIcon.startsWith("file://")) return cleanIcon;
        if (cleanIcon.startsWith("/")) return "file://" + cleanIcon;
        
        // Quickshell uses fallback internally, so we just provide the clean name
        return "image://icon/" + cleanIcon;
    }

    Rectangle {
        anchors.fill: parent
        color: root.urgency == NotificationUrgency.Critical ? Colors.shadow : Colors.surfaceBright
        border.width: root.urgency == NotificationUrgency.Critical ? 2 : 0
        border.color: root.urgency == NotificationUrgency.Critical ? Colors.criticalRed : "transparent"
        radius: root.radius
        visible: root.image == "" && root.appIcon == ""

        Text {
            anchors.centerIn: parent
            text: root.urgency == NotificationUrgency.Critical ? Icons.alert : Icons.bell
            font.family: Icons.font
            font.pixelSize: root.size * 0.5
            color: root.urgency == NotificationUrgency.Critical ? Colors.criticalText : Styling.srItem("overprimary")

            SequentialAnimation on opacity {
                running: root.urgency == NotificationUrgency.Critical && root.visible && root.opacity > 0
                loops: Animation.Infinite
                NumberAnimation {
                    from: 1.0
                    to: 0.5
                    duration: 800
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 0.5
                    to: 1.0
                    duration: 800
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    // Main Image or App Icon
    Image {
        id: mainImage
        anchors.fill: parent
        visible: source != ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        source: {
            if (root.image && !root.usingAppIconFallback) {
                return root.image;
            }
            if (root.appIcon) {
                return root.getIconSource(root.appIcon);
            }
            return "";
        }
        onStatusChanged: {
            if (status === Image.Error && root.image && !root.usingAppIconFallback && root.appIcon) {
                root.usingAppIconFallback = true;
            }
        }
    }

    // App icon overlay badge when showing notification image
    ClippingRectangle {
        id: overlayBadge
        visible: root.image != "" && !root.usingAppIconFallback && root.appIcon != ""
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.smallAppIconSize
        height: root.smallAppIconSize
        radius: root.radius * root.smallAppIconScale

        Image {
            anchors.fill: parent
            source: root.getIconSource(root.appIcon)
            fillMode: Image.PreserveAspectCrop
            smooth: true
        }
    }
}
