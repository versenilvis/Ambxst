pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.bar.workspaces
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import qs.config

PanelWindow {
    id: root

    required property ShellScreen modelData
    screen: modelData

    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(root.screen)
    readonly property int activeWorkspaceId: hyprlandMonitor?.activeWorkspace?.id ?? 1

    // Only shown while the active workspace holds no windows at all
    readonly property bool workspaceEmpty: HyprlandData.windowList.filter(w => w.workspace?.id === root.activeWorkspaceId).length === 0

    readonly property var metrics: {
        const m = [
            { icon: Icons.cpu, value: SystemResources.cpuUsage, accent: Colors.red },
            { icon: Icons.ram, value: SystemResources.ramUsage, accent: Colors.cyan }
        ];
        if (SystemResources.gpuDetected)
            m.push({ icon: Icons.gpu, value: SystemResources.gpuUsage, accent: Colors.yellow });
        return m;
    }

    visible: (Config.desktop?.resourceWidget ?? true) && root.workspaceEmpty

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell:resourceWidget"
    mask: Region {
        item: null
    }

    anchors {
        top: true
        bottom: true
        right: true
    }

    implicitWidth: panel.visibleWidth

    StyledRect {
        id: panel
        variant: "pane"

        readonly property int visibleWidth: 72

        radius: Styling.radius(8)
        // Right corners are pushed past the screen edge so the pill sits flush against it
        width: panel.visibleWidth + panel.radius
        height: column.height + 32
        anchors.right: parent.right
        anchors.rightMargin: -panel.radius
        anchors.verticalCenter: parent.verticalCenter

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
                        anchors.horizontalCenter: parent.horizontalCenter
                        icon: metric.modelData.icon
                        value: metric.modelData.value / 100
                        accentColor: metric.modelData.accent
                        isToggleable: false
                        isToggled: false
                        showBackground: false
                        showHandle: false
                        gapAngle: 0
                        lineWidth: 3
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
}
