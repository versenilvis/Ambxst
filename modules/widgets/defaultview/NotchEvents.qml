import QtQuick
import qs.modules.theme
import qs.modules.services
import qs.config

// Event-driven notch content: the notch morphs briefly when something actually
// happens (charger plugged in, battery low, a device connects, wifi joins a
// network) and collapses again on its own. This is deliberately NOT the
// notification system - nothing is queued for later or kept in history.
Item {
    id: root

    // The event currently on screen, or null. DefaultView expands the notch while
    // this is set, so it is the single source of truth for "the notch has something
    // to say right now".
    property var current: null
    readonly property bool active: current !== null

    // Two beats in, two beats out: the glyph lands (arrived), then the detail
    // unfurls beside it (expanded). Leaving plays the same beats in reverse.
    property bool arrived: false
    property bool expanded: false

    // Services fire their change handlers once during startup as they populate.
    // Nothing may be shown until this settles, or the notch announces the battery
    // level every login.
    property bool ready: false

    // Previous values, so a handler can tell which DIRECTION a value moved.
    property int lastBluetoothCount: -1
    property string lastSsid: ""

    implicitWidth: current ? eventRow.implicitWidth + (expanded ? 38 : 20) : 0
    implicitHeight: current ? 44 : 0

    Behavior on implicitWidth {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.15
        }
    }

    Timer {
        id: readyTimer
        interval: 2500
        running: true
        repeat: false
        onTriggered: {
            root.lastBluetoothCount = BluetoothService.connectedDevices;
            root.lastSsid = NetworkService.active ? NetworkService.active.ssid : "";
            root.ready = true;
        }
    }

    // Beat 1 in: a frame after current is set, so the glyph animates from its
    // collapsed state instead of being born at full size.
    Timer {
        id: arriveTimer
        interval: 20
        repeat: false
        onTriggered: root.arrived = true
    }

    // Beat 2 in.
    Timer {
        id: expandTimer
        interval: 240
        repeat: false
        onTriggered: root.expanded = true
    }

    // Only runs while something is on screen; idle costs nothing.
    Timer {
        id: dismissTimer
        interval: 3600
        running: root.current !== null
        repeat: false
        onTriggered: {
            root.expanded = false;
            root.arrived = false;
            collapseTimer.restart();
        }
    }

    // Beat 2 out: hold the event until the collapse has actually played, or the
    // whole row would vanish mid-animation.
    Timer {
        id: collapseTimer
        interval: Math.max(Config.animDuration, 1)
        repeat: false
        onTriggered: root.current = null
    }

    // label is only for things that need naming (an SSID, a device); everything
    // else is its glyph plus its value. meter is 0..1, or -1 for no level.
    function show(icon, accent, label, value, meter, pulse) {
        if (!root.ready)
            return;
        root.arrived = false;
        root.expanded = false;
        collapseTimer.stop();
        root.current = {
            icon: icon,
            accent: accent,
            label: label,
            value: value,
            meter: meter === undefined ? -1 : meter,
            pulse: pulse === true
        };
        arriveTimer.restart();
        expandTimer.restart();
        dismissTimer.restart();
    }

    readonly property real batteryLevel: Battery.available ? Battery.percentage / 100 : -1
    readonly property string batteryPct: Battery.available ? Math.round(Battery.percentage) + "%" : ""

    function connectedBluetoothName() {
        const list = BluetoothService.devices;
        for (let i = 0; i < list.length; i++) {
            if (list[i].connected)
                return list[i].name || "";
        }
        return "";
    }

    Connections {
        target: Battery
        enabled: Battery.available

        function onIsChargingChanged() {
            if (Battery.isCharging) {
                root.show(Icons.batteryCharging, Colors.green, "", root.batteryPct, root.batteryLevel, true);
            } else {
                root.show(Icons.batteryMedium, Colors.overBackground, "", root.batteryPct, root.batteryLevel);
            }
        }

        // Battery.qml owns the threshold logic and used to shell out to notify-send;
        // it now hands the alert here so it renders in the notch instead. Its title
        // and body are both prose - the glyph, the colour and the level say it.
        function onBatteryAlert(title, body, urgency) {
            root.show(Icons.batteryLow, urgency === "critical" ? Colors.red : Colors.yellow, "", root.batteryPct, root.batteryLevel, urgency === "critical");
        }

        function onChargeStateChanged() {
            if (Battery.percentage >= 99 && Battery.isPluggedIn) {
                root.show(Icons.batteryFull, Colors.green, "", "100%", 1);
            }
        }
    }

    Connections {
        target: BluetoothService

        function onConnectedDevicesChanged() {
            const now = BluetoothService.connectedDevices;
            const prev = root.lastBluetoothCount;
            root.lastBluetoothCount = now;
            if (prev < 0 || now === prev)
                return;
            if (now > prev) {
                root.show(Icons.bluetoothConnected, Colors.cyan, root.connectedBluetoothName(), "");
            } else {
                root.show(Icons.bluetooth, Colors.outline, "", "");
            }
        }
    }

    Connections {
        target: NetworkService

        function onActiveChanged() {
            const ssid = NetworkService.active ? NetworkService.active.ssid : "";
            const prev = root.lastSsid;
            root.lastSsid = ssid;
            if (ssid === prev)
                return;
            if (ssid) {
                root.show(Icons.wifiHigh, Colors.cyan, ssid, "");
            } else if (prev) {
                root.show(Icons.wifiOff, Colors.outline, "", "");
            }
        }
    }

    readonly property color accent: current ? current.accent : Colors.outline

    // Slow breath on the glyph while charging or critical, so those two keep
    // moving for as long as they are on screen.
    property real pulseOpacity: 1.0
    SequentialAnimation {
        running: root.arrived && root.current !== null && root.current.pulse
        loops: Animation.Infinite
        onStopped: root.pulseOpacity = 1.0
        NumberAnimation { target: root; property: "pulseOpacity"; to: 0.45; duration: 850; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "pulseOpacity"; to: 1.0; duration: 850; easing.type: Easing.InOutQuad }
    }

    Row {
        id: eventRow
        anchors.centerIn: parent
        spacing: root.expanded ? 10 : 0
        visible: root.current !== null

        Behavior on spacing {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        // Bare glyph, no puck behind it. It pops in on its own beat.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.current ? root.current.icon : ""
            font.family: Icons.font
            font.pixelSize: 19
            color: root.accent
            opacity: root.arrived ? root.pulseOpacity : 0
            scale: root.arrived ? 1 : 0.4

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration * 0.6
                    easing.type: Easing.OutQuart
                }
            }

            Behavior on scale {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutBack
                    easing.overshoot: 2.6
                }
            }
        }

        // Everything after the glyph unfurls sideways. Width animates to zero
        // rather than the item being hidden, so the notch itself grows with it.
        Item {
            id: detail
            anchors.verticalCenter: parent.verticalCenter
            width: root.expanded ? detailRow.implicitWidth : 0
            height: detailRow.implicitHeight
            clip: true
            opacity: root.expanded ? 1 : 0

            Behavior on width {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            Row {
                id: detailRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                // Slides out from under the glyph instead of just appearing.
                x: root.expanded ? 0 : -14

                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }

                // Only for events that carry a name - an SSID, a paired device.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: root.current ? root.current.label : ""
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Medium
                    color: Colors.overBackground
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    // A long SSID must not stretch the notch across the screen.
                    width: Math.min(implicitWidth, 230)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: root.current ? root.current.value : ""
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Bold
                    color: root.accent
                }

                // Only battery events carry a level, and only they get the bar.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.current && root.current.meter >= 0
                    width: visible ? 32 : 0
                    height: 13
                    radius: 999
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // Fills from empty once the row is open.
                        width: root.expanded ? Math.max(4, parent.width * (root.current ? Math.min(1, Math.max(0, root.current.meter)) : 0)) : 0
                        height: parent.height
                        radius: 999
                        color: root.accent

                        Behavior on width {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration * 1.4
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }
}
