import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.bar.workspaces
import qs.config
import "../../defaultview/media_detector.js" as MediaDetector

Item {
    id: root
    implicitWidth: 570
    implicitHeight: 190

    readonly property var player: MprisController.activePlayer
    readonly property bool isPlaying: (player?.playbackState === MprisPlaybackState.Playing) || (player?.isPlaying === true)
    readonly property real position: player?.position ?? 0.0
    readonly property real length: player?.length ?? 1.0

    readonly property var detectedInfo: MediaDetector.detectMedia(player, typeof HyprlandData !== "undefined" ? HyprlandData.windowList : [])

    readonly property string mediaArtUrl: {
        if (player?.trackArtUrl && player.trackArtUrl !== "") {
            return player.trackArtUrl;
        }
        let domain = detectedInfo?.domain || "";
        if (domain && domain !== "") {
            return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(domain) + "&sz=128";
        }
        return "";
    }
    readonly property bool hasArtwork: mediaArtUrl !== ""
    readonly property bool hasValidTrack: player !== null && (isPlaying || (player.trackTitle && player.trackTitle.trim() !== "" && player.trackTitle !== "Unknown Title" && player.trackTitle !== "Unknown Track" && player.trackTitle !== "Unknown"))

    readonly property bool isYouTube: {
        if (!player) return false;
        let id = (player.identity || "").toLowerCase();
        let dbus = (player.dbusName || "").toLowerCase();
        let title = ((detectedInfo?.title || "") + " " + (player.trackTitle || "")).toLowerCase();
        let artist = ((detectedInfo?.artist || "") + " " + (player.trackArtist || "")).toLowerCase();
        let art = (player.trackArtUrl || "").toLowerCase();
        let domain = detectedInfo?.domain || "";

        if (domain === "youtube.com") return true;
        if (artist.includes("vevo") || title.includes("vevo")) return true;
        if (artist.includes("youtube") || title.includes("youtube") || id.includes("youtube") || dbus.includes("youtube")) return true;
        if (art.includes("ytimg") || art.includes("youtube.com") || art.includes("ggpht.com")) return true;
        return false;
    }
    readonly property bool isSpotify: {
        if (!player) return false;
        let id = (player.identity || "").toLowerCase();
        let dbus = (player.dbusName || "").toLowerCase();
        let domain = detectedInfo?.domain || "";
        return domain === "spotify.com" || id.includes("spotify") || dbus.includes("spotify");
    }

    function formatTime(seconds) {
        const total = Math.floor(seconds || 0);
        const mins = Math.floor(total / 60);
        const secs = total % 60;
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    Timer {
        running: root.isPlaying && root.visible
        interval: 500
        repeat: true
        onTriggered: {
            player?.positionChanged();
        }
    }

    signal openMenu()

    onVisibleChanged: {
        if (visible && (!root.hasValidTrack || !root.isPlaying)) {
            Qt.callLater(() => root.openMenu());
        }
    }

    // blurred artwork gradient background
    Item {
        anchors.fill: parent
        z: -1
        clip: true

        Image {
            id: bgArtwork
            anchors.fill: parent
            source: root.mediaArtUrl
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
            opacity: root.hasArtwork ? 0.48 : 0.0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: 300 }
            }
        }

        // subtle dark gradient overlay
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.hasArtwork ? Qt.rgba(0.06, 0.08, 0.15, 0.58) : Qt.rgba(0.08, 0.10, 0.16, 0.95) }
                GradientStop { position: 0.45; color: root.hasArtwork ? Qt.rgba(0.03, 0.04, 0.07, 0.78) : Qt.rgba(0.05, 0.06, 0.10, 0.98) }
                GradientStop { position: 1.0; color: root.hasArtwork ? Qt.rgba(0.01, 0.02, 0.04, 0.92) : Qt.rgba(0.03, 0.04, 0.06, 1.0) }
            }
        }

        // subtle top gloss reflection
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(1, 1, 1, 0.14)
        }
    }

    // active player view
    RowLayout {
        anchors.fill: parent
        spacing: 18
        visible: root.hasValidTrack

        // squircle album art with badge
        Item {
            Layout.preferredWidth: 144
            Layout.preferredHeight: 144
            Layout.alignment: Qt.AlignVCenter

            // soft artwork ambient glow behind album art
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 22
                color: root.isYouTube ? "#ff0000" : (root.isSpotify ? "#1db954" : Colors.primary)
                opacity: 0.18
                z: -1
            }

            Rectangle {
                id: artContainer
                anchors.fill: parent
                radius: 18
                color: "#181b26"
                clip: true

                Image {
                    id: albumArt
                    anchors.fill: parent
                    source: root.mediaArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: root.hasArtwork
                }

                // fallback when no artwork
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0.2, 0.25, 0.35, 0.4)
                    visible: !root.hasArtwork

                    Text {
                        anchors.centerIn: parent
                        text: Icons.player
                        font.family: Icons.font
                        font.pixelSize: 42
                        color: Qt.rgba(1, 1, 1, 0.4)
                    }
                }

                // subtle inner gloss border
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }
            }

            // app/service logo overlay at bottom right
            Rectangle {
                id: logoBadge
                width: root.isYouTube ? 30 : 26
                height: root.isYouTube ? 22 : 26
                radius: root.isYouTube ? 6 : 13
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -5
                anchors.bottomMargin: -5
                color: root.isYouTube ? "#FF0000" : (root.isSpotify ? "#1DB954" : "#1a1e28")
                border.width: 1.5
                border.color: "#0a0c10"
                clip: true

                // YouTube play triangle
                Canvas {
                    id: ytCanvas
                    visible: root.isYouTube
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    antialiasing: true
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.fillStyle = "#ffffff";
                        ctx.beginPath();
                        ctx.moveTo(3, 2);
                        ctx.lineTo(10, 6);
                        ctx.lineTo(3, 10);
                        ctx.closePath();
                        ctx.fill();
                    }
                    Component.onCompleted: requestPaint()
                    Connections {
                        target: root
                        function onIsYouTubeChanged() { ytCanvas.requestPaint(); }
                    }
                }

                Text {
                    visible: !root.isYouTube
                    anchors.centerIn: parent
                    text: root.isSpotify ? Icons.spotify : Icons.player
                    font.family: Icons.font
                    font.pixelSize: 13
                    color: "#ffffff"
                    textFormat: Text.RichText
                }
            }
        }

        // track metadata & controls
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Item { Layout.fillHeight: true } // Top spacer

            // title & menu button row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: (root.detectedInfo.title && root.detectedInfo.title !== "Unknown Track" && root.detectedInfo.title !== "") ? root.detectedInfo.title : (root.player?.trackTitle || "Unknown Title")
                        font.family: Styling.defaultFont
                        font.pixelSize: 18
                        font.bold: true
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: (root.detectedInfo.artist && root.detectedInfo.artist !== "Unknown Artist" && root.detectedInfo.artist !== "") ? root.detectedInfo.artist : (root.player?.trackArtist || "Unknown Artist")
                        font.family: Styling.defaultFont
                        font.pixelSize: 13
                        color: Qt.rgba(1, 1, 1, 0.55)
                        elide: Text.ElideRight
                    }
                }

                // 2x2 grid menu button matching mockup
                Item {
                    id: menuGridBtn
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: menuGridHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 3

                        Repeater {
                            model: 4
                            Rectangle {
                                width: 7
                                height: 7
                                radius: 2.2
                                color: "transparent"
                                border.width: 1.6
                                border.color: menuGridHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                            }
                        }
                    }

                    HoverHandler { id: menuGridHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openMenu()
                    }
                }
            }

            // player timeline matching hover state
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                PositionSlider {
                    id: positionSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    player: root.player
                    hasArtwork: root.hasArtwork
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: root.formatTime(root.position)
                        font.family: Styling.defaultFont
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.formatTime(root.length)
                        font.family: Styling.defaultFont
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }
                }
            }


            // transport controls row
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 24

                // previous button
                Item {
                    width: 32
                    height: 32

                    Text {
                        anchors.centerIn: parent
                        text: Icons.previous
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: prevHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                    }

                    HoverHandler { id: prevHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.player?.previous()
                    }
                }

                // play / pause button (prominent circular pill)
                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: playBtnHover.hovered ? "#e0e7ff" : "#ffffff"
                    scale: playBtnArea.pressed ? 0.92 : 1.0

                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: root.isPlaying ? Icons.pause : Icons.play
                        font.family: Icons.font
                        font.pixelSize: 20
                        color: "#0a0c10"
                    }

                    HoverHandler { id: playBtnHover }
                    MouseArea {
                        id: playBtnArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.player?.togglePlaying()
                    }
                }

                // next button
                Item {
                    width: 32
                    height: 32

                    Text {
                        anchors.centerIn: parent
                        text: Icons.next
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: nextHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                    }

                    HoverHandler { id: nextHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.player?.next()
                    }
                }
            }

            Item { Layout.fillHeight: true } // Bottom spacer
        }
    }

    // fallback when no media is playing (Apple Ambient card)
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
        visible: !root.hasValidTrack

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 52
                height: 52
                radius: 26
                color: Qt.rgba(1, 1, 1, 0.08)

                Text {
                    anchors.centerIn: parent
                    text: Icons.player
                    font.family: Icons.font
                    font.pixelSize: 24
                    color: Qt.rgba(1, 1, 1, 0.45)
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No Media Playing"
                    font.family: Styling.defaultFont
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Play a song in Spotify, YouTube or your browser"
                    font.family: Styling.defaultFont
                    font.pixelSize: 12
                    color: Qt.rgba(1, 1, 1, 0.45)
                }
            }
        }
    }
}
