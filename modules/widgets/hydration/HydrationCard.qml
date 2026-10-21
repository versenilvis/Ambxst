import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

Item {
    id: root

    implicitWidth: 110
    implicitHeight: 110

    readonly property bool isAlert: HydrationService.alertActive

    ClippingRectangle {
        id: cardBg
        anchors.fill: parent
        radius: Styling.radius(20)
        color: "#0f1217"
        border.width: root.isAlert ? 2 : 1
        border.color: root.isAlert ? "#ef4444" : Qt.rgba(1, 1, 1, 0.1)

        Behavior on border.color {
            ColorAnimation { duration: 250 }
        }

        // top digital countdown
        Text {
            id: countdownText
            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            text: HydrationService.formattedTime
            font.family: Styling.defaultFont
            font.pixelSize: 16
            font.bold: true
            color: root.isAlert ? "#ef4444" : "#e2e8f0"

            Behavior on color {
                ColorAnimation { duration: 200 }
            }
        }

        // animated liquid wave
        WaveEffect {
            id: wave
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.52
            waterLevel: 0.55
            colorTop: root.isAlert ? "#f87171" : "#00C6FF"
            colorBottom: root.isAlert ? "#dc2626" : "#0072FF"
        }

        // pill drink button centered over wave
        Rectangle {
            id: drinkBtn
            width: 76
            height: 26
            radius: 13
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            color: btnHover.hovered ? Qt.rgba(0.18, 0.22, 0.3, 0.95) : Qt.rgba(0.12, 0.15, 0.22, 0.85)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.25)
            scale: btnMouse.pressed ? 0.93 : (btnHover.hovered ? 1.05 : 1.0)

            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
            }

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            Row {
                anchors.centerIn: parent
                spacing: 5

                Canvas {
                    id: dropIcon
                    width: 10
                    height: 12
                    anchors.verticalCenter: parent.verticalCenter
                    antialiasing: true

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.fillStyle = "#ffffff";
                        ctx.beginPath();
                        ctx.moveTo(5, 0);
                        ctx.bezierCurveTo(7.5, 3.5, 10, 6.5, 10, 8.5);
                        ctx.bezierCurveTo(10, 10.8, 7.8, 12, 5, 12);
                        ctx.bezierCurveTo(2.2, 12, 0, 10.8, 0, 8.5);
                        ctx.bezierCurveTo(0, 6.5, 2.5, 3.5, 5, 0);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Drink"
                    font.family: Styling.defaultFont
                    font.pixelSize: 11
                    font.bold: true
                    color: "#ffffff"
                }
            }

            HoverHandler {
                id: btnHover
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    HydrationService.drink();
                    wave.splash();
                }
            }
        }

        // click card background to toggle full panel
        MouseArea {
            anchors.fill: parent
            z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                HydrationService.togglePopup();
            }
        }
    }

    Connections {
        target: HydrationService
        function onDrank() {
            wave.splash();
        }
    }
}
