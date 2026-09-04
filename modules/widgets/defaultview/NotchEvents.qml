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
    property bool closing: false

    // Services fire their change handlers once during startup as they populate.
    // Nothing may be shown until this settles, or the notch announces the battery
    // level every login.
    property bool ready: false

    // Previous values, so a handler can tell which DIRECTION a value moved.
    property int lastBluetoothCount: -1
    property string lastSsid: ""
    property int lastPluggedIn: -1
    property int lastCharging: -1

    // compact dynamic island pill width tailored to content
    readonly property real batteryContentWidth: Math.max(160, remainingTimeText.implicitWidth + 88)
    implicitWidth: current ? (isBattery ? batteryContentWidth : (eventRow.implicitWidth + (expanded ? 48 : 28))) : 0
    implicitHeight: current ? 36 : 0

    property var eventQueue: []

    Timer {
        id: readyTimer
        interval: 2500
        running: true
        repeat: false
        onTriggered: {
            root.lastBluetoothCount = BluetoothService.connectedDevices;
            root.lastSsid = NetworkService.active ? NetworkService.active.ssid : "";
            root.lastPluggedIn = Battery.isPluggedIn ? 1 : 0;
            root.lastCharging = Battery.isCharging ? 1 : 0;
            root.ready = true;

            // show boot bluetooth connections
            const bootDevices = BluetoothService.connectedDeviceList || [];
            for (let i = 0; i < bootDevices.length; i++) {
                const dev = bootDevices[i];
                if (dev && dev.name) {
                    root.show(Icons.bluetoothConnected, Colors.cyan, dev.name, "");
                }
            }
        }
    }

    // morph starts on next frame for smooth entrance
    Timer {
        id: arriveTimer
        interval: 16
        repeat: false
        onTriggered: {
            root.arrived = true;
            root.expanded = true;
        }
    }

    // Only runs while something is on screen; idle costs nothing.
    Timer {
        id: dismissTimer
        interval: 3600
        running: root.current !== null
        repeat: false
        onTriggered: {
            root.closing = true;
            collapseTimer.restart();
        }
    }

    // hold the event until the collapse animation finishes
    Timer {
        id: collapseTimer
        interval: 150
        repeat: false
        onTriggered: {
            root.current = null;
            root.arrived = false;
            root.expanded = false;
            root.closing = false;
            if (root.eventQueue.length > 0) {
                const nextEvt = root.eventQueue.shift();
                nextEventTimer.nextEvt = nextEvt;
                nextEventTimer.restart();
            }
        }
    }

    Timer {
        id: nextEventTimer
        interval: 200
        repeat: false
        property var nextEvt: null
        onTriggered: {
            if (nextEvt) {
                root.displayEvent(nextEvt);
                nextEvt = null;
            }
        }
    }

    // label is only for things that need naming (an SSID, a device); everything
    // else is its glyph plus its value. meter is 0..1, or -1 for no level.
    function show(icon, accent, label, value, meter, pulse, trail, mode) {
        if (!root.ready)
            return;

        const evt = {
            icon: icon,
            accent: accent,
            label: label,
            value: value,
            meter: meter === undefined ? -1 : meter,
            pulse: pulse === true,
            trail: trail === undefined ? "" : trail,
            mode: mode || ""
        };

        const isUrgent = mode === "charging" || mode === "unplug" || mode === "alert" || mode === "full";
        if (!isUrgent && root.current !== null && !root.closing) {
            root.eventQueue.push(evt);
            return;
        }

        displayEvent(evt);
    }

    function displayEvent(evt) {
        GlobalStates.notchBounce();
        root.closing = false;
        root.arrived = false;
        root.expanded = false;
        collapseTimer.stop();
        root.current = evt;
        arriveTimer.restart();
        dismissTimer.restart();
    }

    readonly property real batteryLevel: Battery.available ? Battery.percentage / 100 : -1
    readonly property string batteryPct: Battery.available ? String(Math.round(Battery.percentage)) : ""

    function connectedBluetoothName() {
        if (BluetoothService.connectedDeviceList && BluetoothService.connectedDeviceList.length > 0) {
            return BluetoothService.connectedDeviceList[0].name || "";
        }
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
        function onPowerTransition() {
            const plugged = Battery.isPluggedIn ? 1 : 0;
            const charging = Battery.isCharging ? 1 : 0;
            const prevPlugged = root.lastPluggedIn;
            const prevCharging = root.lastCharging;
            root.lastPluggedIn = plugged;
            root.lastCharging = charging;

            if (!root.ready || prevPlugged < 0)
                return;

            if (plugged === 0) {
                if (prevPlugged === 1) {
                    root.show(Battery.getBatteryLevelIcon(), root.getBatteryColor(Battery.percentage), "", root.batteryPct, root.batteryLevel, false, Battery.timeToEmpty, "unplug");
                }
            } else {
                if (prevPlugged === 0) {
                    root.show(Icons.lightning, Colors.green, "", root.batteryPct, root.batteryLevel, true, Battery.timeToFull, "charging");
                } else if (prevCharging === 1 && charging === 0) {
                    root.show(Icons.batteryFull, Colors.green, "", root.batteryPct, root.batteryLevel, false, "Full", "full");
                }
            }
        }

        // Battery.qml owns the threshold logic and used to shell out to notify-send;
        // it now hands the alert here so it renders in the notch instead. Its title
        // and body are both prose - the glyph, the colour and the level say it.
        function onBatteryAlert(title, body, urgency) {
            root.show(Icons.batteryLow, urgency === "critical" ? Colors.red : Colors.yellow, "", root.batteryPct, root.batteryLevel, urgency === "critical", Battery.timeToEmpty, "alert");
        }
    }

    Connections {
        target: BluetoothService

        function onDeviceConnected(address, name) {
            if (!root.ready)
                return;
            root.show(Icons.bluetoothConnected, Colors.cyan, name, "");
        }

        function onDeviceDisconnected(address, name) {
            if (!root.ready)
                return;
            root.show(Icons.bluetooth, Colors.outline, name, "");
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

    function getBatteryColor(pct) {
        if (pct <= 20) return Colors.red;
        if (pct >= 80) return Colors.green;
        if (pct < 50) {
            const ratio = (pct - 20) / 30;
            return Qt.rgba(
                Colors.red.r + (Colors.yellow.r - Colors.red.r) * ratio,
                Colors.red.g + (Colors.yellow.g - Colors.red.g) * ratio,
                Colors.red.b + (Colors.yellow.b - Colors.red.b) * ratio,
                1
            );
        } else {
            const ratio = (pct - 50) / 30;
            return Qt.rgba(
                Colors.yellow.r + (Colors.green.r - Colors.yellow.r) * ratio,
                Colors.yellow.g + (Colors.green.g - Colors.yellow.g) * ratio,
                Colors.yellow.b + (Colors.green.b - Colors.yellow.b) * ratio,
                1
            );
        }
    }

    readonly property color accent: current ? (current.accent || Colors.green) : Colors.outline

    // Slow breath on the glyph while charging or critical
    property real pulseOpacity: 1.0
    SequentialAnimation {
        running: root.arrived && root.current !== null && root.current.pulse && !root.closing
        loops: Animation.Infinite
        onStopped: root.pulseOpacity = 1.0
        NumberAnimation { target: root; property: "pulseOpacity"; to: 0.65; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "pulseOpacity"; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
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
                root.show(Icons.lightning, Colors.green, "", pct, lvl, true, Battery.timeToFull ? Battery.timeToFull : "45m", "charging");
                break;
            case "full":
                root.show(Icons.batteryFull, Colors.green, "", "100", 1.0, false, "Full", "full");
                break;
            case "unplug":
                root.show(Battery.getBatteryLevelIcon(Number(pct)), root.getBatteryColor(Number(pct)), "", pct, lvl, false, Battery.timeToEmpty ? Battery.timeToEmpty : "3h 40m", "unplug");
                break;
            case "low":
                root.show(Icons.batteryLow, Colors.yellow, "", "18", 0.18, false, Battery.timeToEmpty ? Battery.timeToEmpty : "25m", "alert");
                break;
            case "critical":
                root.show(Icons.batteryLow, Colors.red, "", "6", 0.06, true, Battery.timeToEmpty ? Battery.timeToEmpty : "8m", "alert");
                break;
            case "wifi":
                root.show(Icons.wifiHigh, Colors.primary, NetworkService.active ? NetworkService.active.ssid : "Wi-Fi", "");
                break;
            case "wifioff":
                root.show(Icons.wifiOff, Colors.outline, "", "");
                break;
            case "bt":
                root.show(Icons.bluetoothConnected, Colors.cyan, root.connectedBluetoothName(), "");
                break;
            case "btoff":
                root.show(Icons.bluetooth, Colors.outline, root.connectedBluetoothName(), "");
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
        const mode = root.current.mode || "";
        const rawTrail = root.current.trail ? String(root.current.trail).trim() : (mode === "charging" ? Battery.timeToFull : Battery.timeToEmpty);
        const trail = rawTrail ? String(rawTrail).trim() : "";
        const cleaned = trail.replace(/^in\s+/i, "").replace(/\s+(left|remaining)$/i, "").trim();

        if (mode === "full")
            return "Fully Charged";

        if (mode === "charging") {
            if (cleaned !== "" && cleaned.toLowerCase() !== "full")
                return cleaned;
            return "Charging";
        }

        if (mode === "unplug" || mode === "alert") {
            if (cleaned !== "" && cleaned.toLowerCase() !== "full")
                return cleaned;
            return "Discharging";
        }

        // fallback if mode wasn't explicitly passed
        if (root.current.pulse && root.current.icon === Icons.lightning) {
            if (cleaned !== "" && cleaned.toLowerCase() !== "full")
                return cleaned;
            return "Charging";
        }

        if (cleaned !== "" && cleaned.toLowerCase() !== "full")
            return cleaned;

        return "Discharging";
    }

    // minimalist 3-part layout for battery and charging events
    Item {
        id: batteryEventLayout
        anchors.fill: parent
        visible: root.current !== null && root.isBattery

        // The pill takes animDuration * 1.3 to grow. Revealing the content before
        // it settles made the icon and the ring visibly slide apart, because their
        // anchors are the pill's own edges.
        readonly property bool shown: root.arrived && !root.closing
        readonly property int revealDelay: shown ? Math.round(Config.animDuration * 0.75) : 0

        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.9

        Behavior on opacity {
            enabled: Config.animDuration > 0
            SequentialAnimation {
                PauseAnimation { duration: batteryEventLayout.revealDelay }
                NumberAnimation {
                    duration: root.closing ? 120 : 200
                    easing.type: root.closing ? Easing.InQuad : Easing.OutCubic
                }
            }
        }

        Behavior on scale {
            enabled: Config.animDuration > 0
            SequentialAnimation {
                PauseAnimation { duration: batteryEventLayout.revealDelay }
                NumberAnimation {
                    duration: root.closing ? 120 : 340
                    easing.type: root.closing ? Easing.InQuad : Easing.OutBack
                    easing.overshoot: 1.5
                }
            }
        }

        // left: battery or lightning icon with glowing accent color
        Item {
            id: batteryIconItem
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22

            Text {
                anchors.centerIn: parent
                text: root.current ? (root.current.icon || Icons.lightning) : Icons.lightning
                font.family: Icons.font
                font.pixelSize: 20
                color: root.accent
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.accent
                shadowBlur: 0.35
                shadowOpacity: 0.55
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 8
            }
        }

        // center: bold remaining time
        Item {
            id: remainingTimeItem
            anchors.centerIn: parent
            width: remainingTimeText.implicitWidth
            height: remainingTimeText.implicitHeight

            Text {
                id: remainingTimeText
                anchors.centerIn: parent
                text: root.formatRemainingTime()
                font.family: Styling.defaultFont
                font.pixelSize: Config.theme.fontSize
                font.bold: true
                color: Colors.overBackground
            }
        }

        // right: circular progress ring with battery number inside
        Item {
            id: batteryRingItem
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24

            property real animatedLevel: 0
            Behavior on animatedLevel {
                enabled: Config.animDuration > 0
                SequentialAnimation {
                    PauseAnimation { duration: batteryEventLayout.revealDelay }
                    NumberAnimation {
                        duration: 520
                        easing.type: Easing.OutCubic
                    }
                }
            }

            onAnimatedLevelChanged: ringCanvas.requestPaint()

            Connections {
                target: root
                function onArrivedChanged() {
                    if (root.arrived) {
                        batteryRingItem.animatedLevel = root.meterValue;
                    } else if (!root.closing) {
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
                    var radius = 9.5;
                    var startAngle = -Math.PI / 2;

                    // background track ring
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
                    ctx.lineWidth = 2.4;
                    ctx.strokeStyle = Qt.rgba(Colors.outlineVariant.r, Colors.outlineVariant.g, Colors.outlineVariant.b, 0.45);
                    ctx.stroke();

                    // progress arc
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
                    shadowBlur: 0.35
                    shadowOpacity: 0.45
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 8
                }
            }

            // battery percentage number inside ring
            Text {
                anchors.centerIn: parent
                text: root.current ? root.current.value : ""
                font.family: Styling.defaultFont
                font.pixelSize: (root.current && root.current.value === "100") ? 8 : 10
                font.bold: true
                color: Colors.overBackground
            }
        }
    }

    // Non-battery events: glyph ping + label/detail
    Row {
        id: eventRow
        anchors.centerIn: parent
        spacing: root.expanded ? 10 : 0
        visible: root.current !== null && !root.isBattery
        opacity: root.closing ? 0 : 1

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: 160
                easing.type: Easing.InQuad
            }
        }

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

