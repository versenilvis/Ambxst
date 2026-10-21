pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.config

Item {
    id: root

    implicitWidth: 36
    implicitHeight: 36

    property bool isHovered: false

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    scale: hydMouseArea.pressed ? 0.90 : (root.isHovered ? 1.05 : 1.0)
    Behavior on scale {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuart
        }
    }

    StyledRect {
        id: buttonBg
        variant: "bg"
        anchors.fill: parent
        radius: 18

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            radius: 18
            z: -1
        }

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: hydMouseArea.pressed ? 0.35 : (root.isHovered ? 0.18 : 0)
            radius: 18

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        Canvas {
            id: dropCanvas
            anchors.centerIn: parent
            width: 13
            height: 17
            antialiasing: true

            readonly property bool isAlert: HydrationService.alertActive
            onIsAlertChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = isAlert ? "#ef4444" : "#38bdf8";
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

        MouseArea {
            id: hydMouseArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                GlobalStates.dashboardCurrentTab = 2;
                Visibilities.setActiveModule("dashboard");
            }
        }
    }
}
