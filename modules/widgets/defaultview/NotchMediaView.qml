import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.modules.bar.workspaces
import qs.config
import "media_detector.js" as MediaDetector

Item {
    id: notchMediaView

    property var player: MprisController.activePlayer
    property bool expandedState: false

    property bool isPlaying: player?.playbackState === MprisPlaybackState.Playing
    property real position: player?.position ?? 0.0
    property real length: player?.length ?? 1.0

    readonly property var detectedInfo: MediaDetector.detectMedia(player, HyprlandData.windowList)
    readonly property bool hasValidPlayer: player !== null && detectedInfo.title !== "Unknown Track" && detectedInfo.title !== "Unknown" && detectedInfo.title !== ""

    readonly property string mediaArtUrl: {
        let domain = detectedInfo.domain;
        if (domain === "x.com") {
            let clipThumb = getClipboardTweetThumbnail(player);
            if (clipThumb !== "") return clipThumb;
            return "https://www.google.com/s2/favicons?domain=x.com&sz=128";
        }
        if (domain !== "" && domain !== "youtube.com" && domain !== "soundcloud.com" && domain !== "spotify.com") {
            return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(domain) + "&sz=128";
        }
        if (player?.trackArtUrl && player.trackArtUrl !== "") {
            return player.trackArtUrl;
        }
        if (domain && domain !== "") {
            return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(domain) + "&sz=128";
        }
        return "";
    }

    property bool hasArtwork: mediaArtUrl !== ""
    
    function getDisplayArtist(player) {
        return detectedInfo.artist;
    }

    function getMediaDomain(player) {
        return detectedInfo.domain;
    }
    
    function getPlayerIcon(player) {
        if (!player) return Icons.player;
        const dbusName = (player.dbusName || "").toLowerCase();
        const desktopEntry = (player.desktopEntry || "").toLowerCase();
        const identity = (player.identity || "").toLowerCase();

        let domain = detectedInfo.domain;
        if (domain === "youtube.com") return Icons.youtube;
        if (domain === "spotify.com") return Icons.spotify;

        if (dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify"))
            return Icons.spotify;
        if (dbusName.includes("chromium") || dbusName.includes("chrome") || desktopEntry.includes("chromium") || desktopEntry.includes("chrome"))
            return Icons.chromium;
        if (dbusName.includes("firefox") || desktopEntry.includes("firefox"))
            return Icons.firefox;
        if (dbusName.includes("telegram") || desktopEntry.includes("telegram") || identity.includes("telegram"))
            return Icons.telegram;
            
        return Icons.player;
    }
    
    function getDisplayTitle(player) {
        return detectedInfo.title;
    }
    
    // cross-reference clipboard cache to extract tweet video thumbnail if link was copied
    function getClipboardTweetThumbnail(player) {
        if (!player) return "";
        let title = (player.trackTitle || "").toLowerCase();
        if (!title.includes("on x") && !title.includes(" / x") && !title.includes("twitter")) {
            return "";
        }
        
        // clean player title for easier matching
        let cleanPlayerTitle = title
            .replace(/\b(on x|\/ x|twitter)\b/g, "")
            .replace(/https?:\/\/\S+/g, "")
            .replace(/[^a-z0-9]/g, "")
            .trim();
            
        if (cleanPlayerTitle === "") return "";
        
        for (let i = 0; i < ClipboardService.items.length; i++) {
            let item = ClipboardService.items[i];
            if (item.isFile || item.isImage) continue;
            
            let content = item.preview || "";
            if (content.includes("twitter.com") || content.includes("x.com")) {
                let cachedRaw = ClipboardService.linkPreviewCache[item.id];
                if (cachedRaw) {
                    try {
                        let meta = typeof cachedRaw === "string" ? JSON.parse(cachedRaw) : cachedRaw;
                        let tweetText = (meta.title || "").toLowerCase();
                        let cleanTweetText = tweetText
                            .replace(/https?:\/\/\S+/g, "")
                            .replace(/[^a-z0-9]/g, "")
                            .trim();
                            
                        if (cleanTweetText !== "" && (cleanPlayerTitle.includes(cleanTweetText) || cleanTweetText.includes(cleanPlayerTitle))) {
                            if (meta.image) return meta.image;
                        }
                    } catch(e) {}
                }
            }
        }
        return "";
    }
    
    // Target dimensions
    readonly property real collapsedWidth: Config.notchTheme === "island" ? 200 : 230
    readonly property real collapsedHeight: Config.notchTheme === "island" ? 36 : 40
    readonly property real expandedWidth: 380
    readonly property real expandedHeight: 130
    
    implicitWidth: (expandedState && hasValidPlayer) ? expandedWidth : (hasValidPlayer ? collapsedWidth : (Config.notchTheme === "island" ? 180 : 200))
    implicitHeight: (expandedState && hasValidPlayer) ? expandedHeight : collapsedHeight
    
    // Removed double animation: rely on Notch.qml's implicitWidth/Height animation
    // to ensure a smooth, non-clashing transition.

    // Blurred Background based on artwork (Only visible in Expanded State for cleaner look)
    ClippingRectangle {
        anchors.fill: parent
        radius: Styling.radius(-4)
        color: "transparent"
        clip: true
        
        Image {
            id: bgArtwork
            anchors.fill: parent
            source: notchMediaView.mediaArtUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        
        MultiEffect {
            anchors.fill: parent
            source: bgArtwork
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            opacity: hasArtwork && expandedState ? 1.0 : 0.0
            
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
            }
        }
        
        // Dark overlay to ensure text is readable
        Rectangle {
            anchors.fill: parent
            color: Colors.background
            opacity: hasArtwork && expandedState ? 0.7 : 0.0
            
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
            }
        }
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        visible: notchMediaView.hasValidPlayer
        clip: true // Prevent content from bleeding outside notch bounds during animation
        
        // --- COLLAPSED STATE UI (Sleek, Fixed width, Empty Center) ---
        Item {
            // Use fixed dimensions and center it so it doesn't reflow during expansion
            width: collapsedWidth - 16
            height: 26
            anchors.centerIn: parent
            
            opacity: expandedState ? 0.0 : 1.0
            visible: opacity > 0
            
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration * 0.4 }
            }
            
            RowLayout {
                anchors.fill: parent
                spacing: 0
                
                // Circular Album Art (Far Left)
                ClippingRectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                    radius: 13 // Perfect circle
                    color: Colors.surfaceBright
                    
                    Image {
                        id: collapsedArtwork
                        anchors.fill: parent
                        source: notchMediaView.mediaArtUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    
                    RotationAnimator {
                        target: collapsedArtwork.parent
                        from: 0
                        to: 360
                        duration: 8000
                        loops: Animation.Infinite
                        running: notchMediaView.isPlaying && !expandedState
                    }
                }
                
                // Empty Space (Middle)
                Item {
                    Layout.fillWidth: true
                }
                
                // 3-Bar Equalizer (Far Right)
                Row {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    spacing: 4
                    height: 14
                    
                    Repeater {
                        model: 3
                        Rectangle {
                            id: rect
                            width: 4
                            radius: 2
                            color: Colors.primary
                            anchors.verticalCenter: parent.verticalCenter
                            
                            readonly property int targetHeight: (typeof index !== "undefined" && index >= 0 && index < 3) ? [14, 10, 12][index] : 10
                            readonly property int targetDuration: (typeof index !== "undefined" && index >= 0 && index < 3) ? [300, 250, 350][index] : 300
                            
                            property real animHeight: 4
                            
                            SequentialAnimation {
                                loops: Animation.Infinite
                                running: notchMediaView.isPlaying && !expandedState
                                
                                NumberAnimation { 
                                    target: rect
                                    property: "animHeight"
                                    to: rect.targetHeight
                                    duration: rect.targetDuration
                                    easing.type: Easing.InOutSine 
                                }
                                NumberAnimation { 
                                    target: rect
                                    property: "animHeight"
                                    to: 4
                                    duration: rect.targetDuration
                                    easing.type: Easing.InOutSine 
                                }
                            }
                            
                            height: (notchMediaView.isPlaying && !expandedState) ? animHeight : 4
                            
                            Behavior on height {
                                enabled: !notchMediaView.isPlaying
                                NumberAnimation { duration: 300; easing.type: Easing.OutQuart }
                            }
                        }
                    }
                }
            }
        }
        
        // --- EXPANDED STATE UI (Fixed dimensions to prevent jitter) ---
        Item {
            // Fixed dimensions to prevent inner layout reflow during animation
            width: expandedWidth - 32
            height: expandedHeight - 32
            anchors.centerIn: parent
            
            opacity: expandedState ? 1.0 : 0.0
            visible: opacity > 0
            
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
            }
            
            RowLayout {
                anchors.fill: parent
                spacing: 16
                
                // Large Artwork Container
                Item {
                    Layout.preferredWidth: parent.height
                    Layout.preferredHeight: parent.height
                    
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Styling.radius(8)
                        color: Colors.surfaceBright
                        
                        Image {
                            anchors.fill: parent
                            source: notchMediaView.mediaArtUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    
                    // App Logo Overlay
                    Rectangle {
                        id: logoOverlay
                        width: 32
                        height: 32
                        radius: 8
                        color: {
                            if (faviconImage.visible) return "transparent";
                            let icon = notchMediaView.getPlayerIcon(notchMediaView.player);
                            if (icon === Icons.spotify) return "#1DB954";
                            if (icon === Icons.youtube) return "#FF0000";
                            return Colors.surface;
                        }
                        clip: true
                        
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -8
                        anchors.bottomMargin: -8
                        
                        property string domain: notchMediaView.getMediaDomain(notchMediaView.player)
                        property string faviconUrl: domain !== "" ? ("https://www.google.com/s2/favicons?domain=" + encodeURIComponent(domain) + "&sz=64") : ""
                        
                        visible: domain !== "" || notchMediaView.getPlayerIcon(notchMediaView.player) !== Icons.player
                        
                        Image {
                            id: faviconImage
                            anchors.fill: parent
                            source: logoOverlay.faviconUrl
                            visible: status === Image.Ready && source !== ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            visible: !faviconImage.visible
                            text: notchMediaView.getPlayerIcon(notchMediaView.player)
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: "#FFFFFF"
                            textFormat: Text.RichText
                        }
                    }
                }
                
                // Track Info and Controls
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4
                    
                    // Track Title
                    Text {
                        Layout.fillWidth: true
                        text: notchMediaView.getDisplayTitle(notchMediaView.player)
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(3)
                        font.weight: Font.Bold
                        color: Colors.overBackground
                        elide: Text.ElideRight
                    }
                    
                    // Artist Name
                    Text {
                        Layout.fillWidth: true
                        text: notchMediaView.getDisplayArtist(notchMediaView.player)
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(1)
                        color: Qt.darker(Colors.overBackground, 1.2)
                        elide: Text.ElideRight
                    }
                    
                    Item { Layout.fillHeight: true } // Spacer
                    
                    // Controls Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        
                        Item { Layout.fillWidth: true } // Spacer
                        
                        // Previous
                        Text {
                            text: Icons.previous
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: prevHover.hovered ? Colors.primary : Colors.overBackground
                            opacity: notchMediaView.player?.canGoPrevious ? 1.0 : 0.3
                            
                            HoverHandler { id: prevHover; enabled: notchMediaView.player?.canGoPrevious ?? false }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: notchMediaView.player?.previous()
                            }
                        }
                        
                        // Play/Pause
                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: playHover.hovered ? Colors.primary : Colors.surfaceBright
                            
                            Text {
                                anchors.centerIn: parent
                                text: notchMediaView.isPlaying ? Icons.pause : Icons.play
                                font.family: Icons.font
                                font.pixelSize: 18
                                color: playHover.hovered ? Colors.overPrimary : Colors.overBackground
                            }
                            
                            HoverHandler { id: playHover }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: notchMediaView.player?.togglePlaying()
                            }
                        }
                        
                        // Next
                        Text {
                            text: Icons.next
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: nextHover.hovered ? Colors.primary : Colors.overBackground
                            opacity: notchMediaView.player?.canGoNext ? 1.0 : 0.3
                            
                            HoverHandler { id: nextHover; enabled: notchMediaView.player?.canGoNext ?? false }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: notchMediaView.player?.next()
                            }
                        }
                        
                        Item { Layout.fillWidth: true } // Spacer
                    }
                    
                    Item { Layout.fillHeight: true } // Spacer
                    
                    // Progress Bar
                    PositionSlider {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        player: notchMediaView.player
                        hasArtwork: false 
                    }
                }
            }
        }
    }
}
