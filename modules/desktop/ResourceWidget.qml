pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.bar.workspaces
import qs.modules.components
import qs.modules.corners
import qs.modules.services
import qs.modules.theme
import qs.config

PanelWindow {
    id: root

    required property ShellScreen modelData
    screen: modelData

    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(root.screen)
    readonly property int activeWorkspaceId: hyprlandMonitor?.activeWorkspace?.id ?? 1

    readonly property bool activeWindowFullscreen: {
        const toplevel = ToplevelManager.activeToplevel;
        if (!toplevel)
            return false;
        if (toplevel.screen !== root.screen)
            return false;
        return toplevel.fullscreen === true;
    }

    property bool reveal: false
    readonly property bool isMouseOver: hitArea.containsMouse || (root.hoveredItem !== null)

    onIsMouseOverChanged: {
        if (isMouseOver) {
            hideTimer.stop();
            root.reveal = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (!root.isMouseOver) {
                root.reveal = false;
                root.hoveredItem = null;
            }
        }
    }

    // Green while there is headroom, yellow once it matters, red when it hurts.
    // Same palette BatteryIndicator interpolates over.
    function usageColor(percent) {
        if (percent >= 80)
            return "#f64108";
        if (percent >= 50)
            return "#effd14";
        return Colors.green;
    }

    function gib(bytes) {
        return (bytes / 1024 / 1024 / 1024).toFixed(1);
    }

    readonly property var metrics: {
        const m = [
            {
                icon: Icons.cpu,
                value: SystemResources.cpuUsage,
                title: "CPU",
                detail: (SystemResources.cpuModel || "Processor") + (SystemResources.cpuTemp >= 0 ? `  ·  ${SystemResources.cpuTemp}°C` : "")
            },
            {
                icon: Icons.ram,
                value: SystemResources.ramUsage,
                title: "RAM",
                detail: `${root.gib(SystemResources.ramUsed)} / ${root.gib(SystemResources.ramTotal)} GiB`
            }
        ];
        if (SystemResources.gpuDetected)
            m.push({
                icon: Icons.gpu,
                value: SystemResources.gpuUsage,
                title: "GPU",
                detail: (SystemResources.gpuNames[0] || "Graphics") + (SystemResources.gpuTemp >= 0 ? `  ·  ${SystemResources.gpuTemp}°C` : "")
            });
        return m;
    }

    property Item hoveredItem: null
    readonly property var hoveredMetric: hoveredItem ? hoveredItem.modelData : null

    visible: (Config.desktop?.resourceWidget ?? true) && !root.activeWindowFullscreen

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell:resourceWidget"

    // Only the pill takes pointer input; the detail card is read-only decoration
    mask: Region {
        item: hitArea
    }

    anchors {
        top: true
        bottom: true
        right: true
    }

    // Wide enough to hold the detail card to the left of the pill
    implicitWidth: pillContainer.visibleWidth + 300

    MouseArea {
        id: hitArea
        hoverEnabled: true

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.reveal
            ? (root.hoveredItem ? pillContainer.visibleWidth + card.width + 20 : pillContainer.visibleWidth)
            : pillContainer.peekWidth + 6
        height: pillContainer.height + 40
    }

    Item {
        id: pillContainer

        readonly property int cornerSize: Config.roundness > 0 ? Config.roundness + 4 : 20
        readonly property int visibleWidth: 72
        readonly property int peekWidth: 8

        width: visibleWidth
        height: panel.height + cornerSize * 2
        anchors.right: parent.right
        anchors.rightMargin: root.reveal ? 0 : -(visibleWidth - peekWidth)
        anchors.verticalCenter: parent.verticalCenter

        Behavior on anchors.rightMargin {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: root.reveal ? 240 : 160
                easing.type: Easing.OutCubic
            }
        }

        RoundCorner {
            id: topCorner
            size: pillContainer.cornerSize
            anchors.top: parent.top
            anchors.right: parent.right
            corner: RoundCorner.CornerEnum.BottomRight
            color: "#000000"
        }

        Rectangle {
            id: panel

            readonly property int visibleWidth: pillContainer.visibleWidth
            readonly property int cornerSize: pillContainer.cornerSize

            color: "#000000"
            topLeftRadius: cornerSize
            bottomLeftRadius: cornerSize
            topRightRadius: 0
            bottomRightRadius: 0

            width: visibleWidth
            height: column.height + 32
            anchors.top: topCorner.bottom
            anchors.right: parent.right

            Column {
                id: column
                spacing: 16
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: (panel.visibleWidth - width) / 2

            Repeater {
                model: root.metrics

                Column {
                    id: metric

                    required property var modelData
                    spacing: 2

                    CircularControl {
                        id: ring
                        anchors.horizontalCenter: parent.horizontalCenter
                        icon: metric.modelData.icon
                        value: metric.modelData.value / 100
                        accentColor: root.usageColor(metric.modelData.value)
                        isToggleable: false
                        isToggled: false
                        showBackground: false
                        showHandle: false
                        gapAngle: 0
                        lineWidth: 3

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.hoveredItem = metric
                            onExited: {
                                if (root.hoveredItem === metric)
                                    root.hoveredItem = null;
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: `${Math.round(metric.modelData.value)}%`
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        font.weight: Font.Bold
                        color: Colors.overBackground
                    }
                }
            }
        }
    }

    RoundCorner {
            id: bottomCorner
            size: pillContainer.cornerSize
            anchors.top: panel.bottom
            anchors.right: parent.right
            corner: RoundCorner.CornerEnum.TopRight
            color: "#000000"
        }
    }

    Rectangle {
        id: card

        readonly property var metric: root.hoveredMetric

        visible: root.reveal && root.hoveredItem !== null && opacity > 0
        opacity: (root.reveal && root.hoveredItem !== null) ? 1 : 0
        color: "#000000"
        radius: Styling.radius(4)

        width: cardColumn.width + 28
        height: cardColumn.height + 20
        anchors.right: pillContainer.left
        anchors.rightMargin: 10

        property real targetY: (root.height - height) / 2
        Binding on targetY {
            when: root.hoveredItem !== null
            value: root.hoveredItem ? root.hoveredItem.mapToItem(root, 0, root.hoveredItem.height / 2).y - card.height / 2 : (root.height - card.height) / 2
        }
        y: targetY

        Behavior on y {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Column {
            id: cardColumn
            anchors.centerIn: parent
            spacing: 3

            Text {
                text: card.metric ? `${card.metric.title}   ${Math.round(card.metric.value)}%` : ""
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.Bold
                color: card.metric ? root.usageColor(card.metric.value) : Colors.overBackground
            }

            Text {
                text: card.metric ? card.metric.detail : ""
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
            }
        }
    }
}
