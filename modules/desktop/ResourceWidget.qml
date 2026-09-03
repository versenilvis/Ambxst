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

    // Hide only when a window actually overlaps the pill - a window sitting
    // elsewhere on the workspace is no reason to disappear. Hyprland reports
    // window geometry in logical coordinates, same space as ShellScreen.
    readonly property bool covered: {
        if (!root.screen)
            return false;

        const count = root.metrics ? root.metrics.length : 3;
        const h = count * 66 + (count - 1) * 16 + 32 + 40;
        const left = root.screen.x + root.screen.width - 72;
        const right = root.screen.x + root.screen.width;
        const top = root.screen.y + (root.screen.height - h) / 2;
        const bottom = top + h;

        return HyprlandData.windowList.some(w => {
            if (w.workspace?.id !== root.activeWorkspaceId || w.hidden || !w.at || !w.size)
                return false;
            const x1 = w.at[0], y1 = w.at[1];
            return x1 < right && x1 + w.size[0] > left && y1 < bottom && y1 + w.size[1] > top;
        });
    }

    // Green while there is headroom, yellow once it matters, red when it hurts.
    // Same palette BatteryIndicator interpolates over.
    function usageColor(percent) {
        if (percent >= 80)
            return "#f64108";
        if (percent >= 50)
            return "#effd14";
        return "#04FE88";
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

    visible: (Config.desktop?.resourceWidget ?? true) && !root.covered

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell:resourceWidget"

    // Only the pill takes pointer input; the detail card is read-only decoration
    mask: Region {
        item: pillContainer
    }

    anchors {
        top: true
        bottom: true
        right: true
    }

    // Wide enough to hold the detail card to the left of the pill
    implicitWidth: pillContainer.visibleWidth + 300

    Item {
        id: pillContainer

        readonly property int cornerSize: Config.roundness > 0 ? Config.roundness + 4 : 20
        readonly property int visibleWidth: 72

        width: visibleWidth
        height: panel.height + cornerSize * 2
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

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

        visible: opacity > 0
        opacity: root.hoveredItem ? 1 : 0
        color: "#000000"
        radius: Styling.radius(4)

        width: cardColumn.width + 28
        height: cardColumn.height + 20
        anchors.right: pillContainer.left
        anchors.rightMargin: 10
        y: root.hoveredItem ? root.hoveredItem.mapToItem(null, 0, root.hoveredItem.height / 2).y - height / 2 : 0

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
