import QtQuick
import QtQuick.Effects
import Quickshell.Io
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

    // Glyph events need the extra room so their ping ring is not clipped
    // by the notch edge.
    implicitWidth: current ? eventRow.implicitWidth + (expanded ? (isBattery ? 38 : 48) : 28) : 0
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
    function show(icon, accent, label, value, meter, pulse, trail) {
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
            pulse: pulse === true,
            trail: trail === undefined ? "" : trail
        };
        arriveTimer.restart();
        expandTimer.restart();
        dismissTimer.restart();
    }

    readonly property real batteryLevel: Battery.available ? Battery.percentage / 100 : -1
    readonly property string batteryPct: Battery.available ? String(Math.round(Battery.percentage)) : ""

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

        // Every charge transition comes through here. Watching isCharging alone
        // missed the states that are plugged in but not charging - full, or held
        // at a charge threshold - so plugging in could produce nothing at all.
        function onChargeStateChanged() {
            if (Battery.isCharging) {
                root.show(Icons.batteryCharging, Colors.green, "", root.batteryPct, root.batteryLevel, true, Battery.timeToFull);
            } else if (Battery.isPluggedIn) {
                root.show(Icons.batteryFull, Colors.green, "", root.batteryPct, root.batteryLevel, false, "");
            } else {
                root.show(Icons.batteryMedium, Colors.overBackground, "", root.batteryPct, root.batteryLevel, false, Battery.timeToEmpty);
            }
        }

        // Battery.qml owns the threshold logic and used to shell out to notify-send;
        // it now hands the alert here so it renders in the notch instead. Its title
        // and body are both prose - the glyph, the colour and the level say it.
        function onBatteryAlert(title, body, urgency) {
            root.show(Icons.batteryLow, urgency === "critical" ? Colors.red : Colors.yellow, "", root.batteryPct, root.batteryLevel, urgency === "critical", Battery.timeToEmpty);
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
                root.show(Icons.wifiHigh, Colors.primary, ssid, "");
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

    // Fire an event by hand instead of waiting for the hardware to produce one:
    //   qs ipc call notchEvents preview charging
    IpcHandler {
        target: "notchEvents"

        function preview(kind: string): string {
            root.ready = true;
            const pct = root.batteryPct !== "" ? root.batteryPct : "76";
            const lvl = root.batteryLevel >= 0 ? root.batteryLevel : 0.76;
            switch (kind) {
            case "charging":
                root.show(Icons.batteryCharging, Colors.green, "", pct, lvl, true, Battery.timeToFull);
                break;
            case "full":
                root.show(Icons.batteryFull, Colors.green, "", pct, lvl, false, "");
                break;
            case "unplug":
                root.show(Icons.batteryMedium, Colors.overBackground, "", pct, lvl, false, Battery.timeToEmpty);
                break;
            case "low":
                root.show(Icons.batteryLow, Colors.yellow, "", pct, lvl, false, Battery.timeToEmpty);
                break;
            case "critical":
                root.show(Icons.batteryLow, Colors.red, "", pct, lvl, true, Battery.timeToEmpty);
                break;
            case "wifi":
                root.show(Icons.wifiHigh, Colors.primary, NetworkService.active ? NetworkService.active.ssid : "Wi-Fi", "");
                break;
            case "wifioff":
                root.show(Icons.wifiOff, Colors.outline, "", "");
                break;
            case "bt":
                root.show(Icons.bluetoothConnected, Colors.primary, root.connectedBluetoothName(), "");
                break;
            case "btoff":
                root.show(Icons.bluetooth, Colors.outline, "", "");
                break;
            default:
                return "unknown kind: " + kind + " (charging full unplug low critical wifi wifioff bt btoff)";
            }
            return "shown: " + kind;
        }
    }

    readonly property bool isBattery: current !== null && current.meter >= 0
    readonly property real meterValue: current ? Math.min(1, Math.max(0, current.meter)) : 0

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

        // A level event arrives as a lit pill and grows a track under itself, the
        // pill riding out to where the charge actually sits.
        Item {
            id: batteryBlock
            visible: root.isBattery
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? Math.max(trackLength, knob.x + knob.width) : 0
            height: 20

            property real trackLength: root.expanded ? 158 : 0

            Behavior on trackLength {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration * 1.4
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: batteryBlock.trackLength
                height: 6
                radius: 999
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, knob.x + knob.width / 2)
                height: 6
                radius: 999
                color: root.accent

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.accent
                    shadowBlur: 1.0
                    shadowOpacity: 0.7
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 24
                }
            }

            Rectangle {
                id: knob
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, batteryBlock.trackLength * root.meterValue - width / 2)
                width: knobRow.implicitWidth + 16
                height: 22
                radius: 999
                color: root.accent
                opacity: root.arrived ? 1 : 0
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

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.accent
                    shadowBlur: 1.0
                    shadowOpacity: root.pulseOpacity
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 32
                }

                Row {
                    id: knobRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.current ? root.current.icon : ""
                        font.family: Icons.font
                        font.pixelSize: 13
                        color: Colors.background
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.current ? root.current.value : ""
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.ExtraBold
                        color: Colors.background
                    }
                }
            }
        }

        // Everything else is just its glyph, lit in its own colour, pinging out
        // a ring the way a radio event should.
        Item {
            visible: !root.isBattery
            anchors.verticalCenter: parent.verticalCenter
            width: glyph.implicitWidth
            height: glyph.implicitHeight

            Rectangle {
                id: ping
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: 999
                color: "transparent"
                border.width: 2
                border.color: root.accent
                opacity: 0
                scale: 0.6
            }

            SequentialAnimation {
                id: pingAnim
                loops: 2

                ParallelAnimation {
                    NumberAnimation { target: ping; property: "scale"; from: 0.6; to: 1.9; duration: 950; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        NumberAnimation { target: ping; property: "opacity"; from: 0; to: 0.6; duration: 140 }
                        NumberAnimation { target: ping; property: "opacity"; to: 0; duration: 810; easing.type: Easing.OutCubic }
                    }
                }
            }

            Connections {
                target: root
                function onArrivedChanged() {
                    if (root.arrived && !root.isBattery)
                        pingAnim.restart();
                }
            }

            Text {
                id: glyph
                anchors.centerIn: parent
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

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.accent
                    shadowBlur: 1.0
                    shadowOpacity: 0.9
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 24
                }
            }
        }

        // The trailing word - an SSID, a device name, a time estimate - unfurls
        // last. Width animates to zero so the notch grows with it.
        Item {
            id: detail
            anchors.verticalCenter: parent.verticalCenter
            width: root.expanded ? trailText.implicitWidth : 0
            height: trailText.implicitHeight
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

            Text {
                id: trailText
                anchors.verticalCenter: parent.verticalCenter
                // Slides out from under whatever precedes it.
                x: root.expanded ? 0 : -14
                text: root.current ? (root.isBattery ? root.current.trail : root.current.label) : ""
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(0)
                // A name is the headline; a time estimate is a footnote.
                font.weight: root.isBattery ? Font.DemiBold : Font.ExtraBold
                color: root.isBattery ? root.accent : Colors.overBackground
                elide: Text.ElideRight
                maximumLineCount: 1
                // A long SSID must not stretch the notch across the screen.
                width: Math.min(implicitWidth, 230)

                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }
    }
}
