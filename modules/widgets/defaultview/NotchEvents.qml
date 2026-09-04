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

    // Dynamic-Island arrival: the puck lands first, the detail unfurls after it.
    // Driven by expandTimer so an event always plays the same beat.
    property bool expanded: false

    // Services fire their change handlers once during startup as they populate.
    // Nothing may be shown until this settles, or the notch announces the battery
    // level every login.
    property bool ready: false

    // Previous values, so a handler can tell which DIRECTION a value moved.
    property int lastBluetoothCount: -1
    property string lastSsid: ""

    implicitWidth: current ? eventRow.implicitWidth + (expanded ? 40 : 22) : 0
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

    Timer {
        id: expandTimer
        interval: 260
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
            root.current = null;
        }
    }

    // meter is 0..1 for events that have a level to show, or -1 for none.
    function show(icon, accent, title, value, meter) {
        if (!root.ready)
            return;
        root.expanded = false;
        root.current = {
            icon: icon,
            accent: accent,
            title: title,
            value: value,
            meter: meter === undefined ? -1 : meter
        };
        expandTimer.restart();
        dismissTimer.restart();
    }

    readonly property real batteryLevel: Battery.available ? Battery.percentage / 100 : -1
    readonly property string batteryPct: Battery.available ? Math.round(Battery.percentage) + "%" : ""

    Connections {
        target: Battery
        enabled: Battery.available

        function onIsChargingChanged() {
            if (Battery.isCharging) {
                root.show(Icons.batteryCharging, Colors.green, Battery.timeToFull ? Battery.timeToFull + " to full" : "Charging", root.batteryPct, root.batteryLevel);
            } else {
                root.show(Icons.batteryMedium, Colors.overBackground, Battery.timeToEmpty ? Battery.timeToEmpty + " left" : "On battery", root.batteryPct, root.batteryLevel);
            }
        }

        // Battery.qml owns the threshold logic and used to shell out to notify-send;
        // it now hands the alert here so it renders in the notch instead. Its body is
        // a full sentence, too long for a glance surface - the level says it better.
        function onBatteryAlert(title, body, urgency) {
            root.show(Icons.batteryLow, urgency === "critical" ? Colors.red : Colors.yellow, title, root.batteryPct, root.batteryLevel);
        }

        function onChargeStateChanged() {
            if (Battery.percentage >= 99 && Battery.isPluggedIn) {
                root.show(Icons.batteryFull, Colors.green, "Fully charged", "100%", 1);
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
                root.show(Icons.bluetoothConnected, Colors.cyan, "Bluetooth", now === 1 ? "Connected" : now + " devices");
            } else {
                root.show(Icons.bluetooth, Colors.outline, "Bluetooth", now === 0 ? "Disconnected" : now + " left");
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
                root.show(Icons.wifiHigh, Colors.cyan, ssid, "Connected");
            } else if (prev) {
                root.show(Icons.wifiOff, Colors.outline, "Wi-Fi", "Disconnected");
            }
        }
    }

    readonly property color accent: current ? current.accent : Colors.outline

    Row {
        id: eventRow
        anchors.centerIn: parent
        spacing: root.expanded ? 11 : 0
        visible: root.current !== null

        Behavior on spacing {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        // The puck: a lit disc in the event's colour, so the notch reads at a
        // glance before any text has unfurled.
        Rectangle {
            width: 28
            height: 28
            radius: 999
            anchors.verticalCenter: parent.verticalCenter
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)

            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30) }
                GradientStop { position: 1.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10) }
            }

            Text {
                anchors.centerIn: parent
                text: root.current ? root.current.icon : ""
                font.family: Icons.font
                font.pixelSize: 15
                color: root.accent
            }
        }

        // Everything after the puck unfurls sideways. Width is animated to zero
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
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current ? root.current.title : ""
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Medium
                    color: Colors.overBackground
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    // A long SSID must not stretch the notch across the screen.
                    width: Math.min(implicitWidth, 230)
                }

                // The value carries the colour, the way the reference designs put
                // the loud number on the trailing edge.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
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
                    width: visible ? 30 : 0
                    height: 13
                    radius: 999
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(4, parent.width * (root.current ? Math.min(1, Math.max(0, root.current.meter)) : 0))
                        height: parent.height
                        radius: 999
                        color: root.accent
                    }
                }
            }
        }
    }
}
