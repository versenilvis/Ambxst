pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

Item {
    id: root

    implicitWidth: 570
    implicitHeight: 210

    signal requestBack()
    signal openHydration()

    readonly property var player: MprisController.activePlayer
    readonly property bool isMediaPlaying: player !== null && ((player.playbackState === MprisPlaybackState.Playing) || (player.isPlaying === true)) && (player.trackTitle && player.trackTitle.trim() !== "" && player.trackTitle !== "Unknown Title" && player.trackTitle !== "Unknown Track" && player.trackTitle !== "Unknown")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // top bar: back button (if media active) + title
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 10

            // back button to media view
            Rectangle {
                visible: root.isMediaPlaying
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 16
                color: backHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: Icons.arrowLeft
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: backHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                }

                HoverHandler { id: backHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestBack()
                }
            }

            Text {
                text: "Menu"
                font.family: Styling.defaultFont
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: "#ffffff"
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }
        }

        // app items grid
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 10

            // hydration app tile
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: hydCardHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: hydCardHover.hovered ? Qt.rgba(56, 189, 248, 0.35) : Qt.rgba(1, 1, 1, 0.08)

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        radius: 12
                        color: Qt.rgba(0, 122, 255, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(56, 189, 248, 0.3)

                        Canvas {
                            anchors.centerIn: parent
                            width: 14
                            height: 18
                            antialiasing: true
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                ctx.fillStyle = "#38bdf8";
                                ctx.beginPath();
                                ctx.moveTo(width / 2, 0);
                                ctx.bezierCurveTo(width * 0.75, height * 0.32, width, height * 0.58, width, height * 0.74);
                                ctx.bezierCurveTo(width, height * 0.95, width * 0.78, height, width / 2, height);
                                ctx.bezierCurveTo(width * 0.22, height, 0, height * 0.95, 0, height * 0.74);
                                ctx.bezierCurveTo(0, height * 0.58, width * 0.25, height * 0.32, width / 2, 0);
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: "Hydration"
                            font.family: Styling.defaultFont
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }

                        Text {
                            text: HydrationService.enabled ? ("Every " + HydrationService.intervalMinutes + "m • " + HydrationService.todayCount + " drinks today") : "Tap to configure reminder"
                            font.family: Styling.defaultFont
                            font.pixelSize: 12
                            color: Qt.rgba(1, 1, 1, 0.5)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: Icons.caretRight
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }
                }

                HoverHandler { id: hydCardHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openHydration()
                }
            }

            // quick controls tile
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: controlsCardHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: controlsCardHover.hovered ? Qt.rgba(255, 255, 255, 0.2) : Qt.rgba(1, 1, 1, 0.08)

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: Icons.faders
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: "#ffffff"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: "Controls"
                            font.family: Styling.defaultFont
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }

                        Text {
                            text: "Volume, brightness & system"
                            font.family: Styling.defaultFont
                            font.pixelSize: 12
                            color: Qt.rgba(1, 1, 1, 0.5)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: Icons.caretRight
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }
                }

                HoverHandler { id: controlsCardHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Visibilities.setActiveModule("controls");
                    }
                }
            }
        }
    }
}
