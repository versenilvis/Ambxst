import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
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
    implicitWidth: current ? (isBattery ? (root.expanded ? 216 : 60) : (eventRow.implicitWidth + (expanded ? 48 : 28))) : 0
    implicitHeight: current ? 36 : 0

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
        GlobalStates.notchBounce();
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
                root.show(Icons.batteryFull, Colors.green, "", root.batteryPct, root.batteryLevel, false, "Full");
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

    readonly property color chargingGreen: "#22c55e"
    readonly property color accent: current ? (current.accent === Colors.green ? chargingGreen : current.accent) : Colors.outline

    // Slow breath on the glyph while charging or critical, so those two keep
    // moving for as long as they are on screen.
    property real pulseOpacity: 1.0
    SequentialAnimation {
        running: root.arrived && root.current !== null && root.current.pulse
        loops: Animation.Infinite
        onStopped: root.pulseOpacity = 1.0
        NumberAnimation { target: root; property: "pulseOpacity"; to: 0.80; duration: 850; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "pulseOpacity"; to: 1.0; duration: 850; easing.type: Easing.InOutQuad }
    }

    // Fire an event by hand instead of waiting for the hardware to produce one:
    //   qs ipc call notchEvents preview charging
    IpcHandler {
        target: "notchEvents"

        function preview(kind: string): string {
            root.ready = true;
            const pct = root.batteryPct !== "" ? root.batteryPct : "82";
            const lvl = root.batteryLevel >= 0 ? root.batteryLevel : 0.82;
            switch (kind) {
            case "charging":
                root.show(Icons.batteryCharging, Colors.green, "", pct, lvl, true, Battery.timeToFull ? Battery.timeToFull : "45m");
                break;
            case "full":
                root.show(Icons.batteryFull, Colors.green, "", "100", 1.0, false, "Full");
                break;
            case "unplug":
                root.show(Icons.batteryMedium, Colors.overBackground, "", pct, lvl, false, Battery.timeToEmpty ? Battery.timeToEmpty : "3h 40m");
                break;
            case "low":
                root.show(Icons.batteryLow, Colors.yellow, "", "18", 0.18, false, Battery.timeToEmpty ? Battery.timeToEmpty : "25m");
                break;
            case "critical":
                root.show(Icons.batteryLow, Colors.red, "", "6", 0.06, true, Battery.timeToEmpty ? Battery.timeToEmpty : "8m");
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

    function formatRemainingTime() {
        if (!root.current)
            return "";
        const trail = root.current.trail ? String(root.current.trail).trim() : "";
        if (root.current.icon === Icons.batteryFull || root.current.value === "100")
            return "Fully Charged";
        if (trail !== "") {
            if (trail.startsWith("in ") || trail.endsWith("left") || trail.endsWith("remaining"))
                return trail;
            if (root.current.pulse)
                return "in " + trail;
            return trail + " left";
        }
        return root.current.pulse ? "Charging" : "";
    }

    // Minimalist 3-part layout for battery / charging events
    Item {
        id: batteryEventLayout
        anchors.fill: parent
        visible: root.current !== null && root.isBattery

        // Left: Battery icon (green, pulsing when charging/critical)
        Item {
            id: batteryIconItem
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24

            opacity: root.arrived ? root.pulseOpacity : 0
            scale: root.arrived ? 1 : 0.5

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
                    easing.overshoot: 1.6
                }
            }

            Text {
                anchors.centerIn: parent
                text: root.current ? (root.current.icon || Icons.batteryCharging) : Icons.batteryCharging
                font.family: Icons.font
                font.pixelSize: 20
                color: root.accent
            }
        }

        // Center: Remaining time only
        Item {
            id: remainingTimeItem
            anchors.centerIn: parent
            width: remainingTimeText.implicitWidth
            height: remainingTimeText.implicitHeight
            opacity: root.expanded ? 1 : 0
            scale: root.expanded ? 1 : 0.8

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration * 0.7
                    easing.type: Easing.OutQuart
                }
            }

            Behavior on scale {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration * 0.7
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }

            Text {
                id: remainingTimeText
                anchors.centerIn: parent
                text: root.formatRemainingTime()
                font.family: Styling.defaultFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: Qt.rgba(255, 255, 255, 0.9)
                font.letterSpacing: 0.3
            }
        }

        // Right: Circular progress ring with battery number inside (Image 2 style)
        Item {
            id: batteryRingItem
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28

            opacity: root.arrived ? 1 : 0
            scale: root.arrived ? 1 : 0.5

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
                    easing.overshoot: 1.4
                }
            }

            property real animatedLevel: 0
            Behavior on animatedLevel {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration * 1.5
                    easing.type: Easing.OutCubic
                }
            }

            onAnimatedLevelChanged: ringCanvas.requestPaint()

            Connections {
                target: root
                function onArrivedChanged() {
                    if (root.arrived) {
                        batteryRingItem.animatedLevel = root.meterValue;
                    } else {
                        batteryRingItem.animatedLevel = 0;
                    }
                }
            }

            Canvas {
                id: ringCanvas
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var centerX = width / 2;
                    var centerY = height / 2;
                    var radius = 10.5;
                    var startAngle = -Math.PI / 2;

                    // Background track ring
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
                    ctx.lineWidth = 2.4;
                    ctx.strokeStyle = Qt.rgba(255, 255, 255, 0.14);
                    ctx.stroke();

                    // Progress arc
                    if (batteryRingItem.animatedLevel > 0) {
                        var sweep = Math.min(1.0, Math.max(0.01, batteryRingItem.animatedLevel)) * 2 * Math.PI;
                        ctx.beginPath();
                        ctx.arc(centerX, centerY, radius, startAngle, startAngle + sweep);
                        ctx.lineWidth = 2.4;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = root.accent;
                        ctx.stroke();
                    }
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.accent
                    shadowBlur: 0.6
                    shadowOpacity: 0.65
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 16
                }
            }

            // Battery percentage number inside ring (Image 2)
            Text {
                anchors.centerIn: parent
                text: root.current ? root.current.value : ""
                font.family: Styling.defaultFont
                font.pixelSize: 10
                font.weight: Font.Black
                color: "#ffffff"
            }
        }
    }

    // Non-battery events: glyph ping + label/detail
    Row {
        id: eventRow
        anchors.centerIn: parent
        spacing: root.expanded ? 10 : 0
        visible: root.current !== null && !root.isBattery

        Behavior on spacing {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Item {
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
                x: root.expanded ? 0 : -14
                text: root.current ? root.current.label : ""
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.ExtraBold
                color: Colors.overBackground
                elide: Text.ElideRight
                maximumLineCount: 1
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

