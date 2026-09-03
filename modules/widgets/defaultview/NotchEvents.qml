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

    // Services fire their change handlers once during startup as they populate.
    // Nothing may be shown until this settles, or the notch announces the battery
    // level every login.
    property bool ready: false

    // Previous values, so a handler can tell which DIRECTION a value moved.
    property int lastBluetoothCount: -1
    property string lastSsid: ""

    implicitWidth: current ? eventRow.implicitWidth + 32 : 0
    implicitHeight: current ? 44 : 0

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

    // Only runs while something is on screen; idle costs nothing.
    Timer {
        id: dismissTimer
        interval: 3200
        running: root.current !== null
        repeat: false
        onTriggered: root.current = null
    }

    function show(icon, accent, title, subtitle) {
        if (!root.ready)
            return;
        root.current = {
            icon: icon,
            accent: accent,
            title: title,
            subtitle: subtitle
        };
        dismissTimer.restart();
    }

    Connections {
        target: Battery
        enabled: Battery.available

        function onIsChargingChanged() {
            if (Battery.isCharging) {
                root.show(Icons.batteryCharging, Colors.green, "Charging", Battery.timeToFull ? Battery.timeToFull + " to full" : Math.round(Battery.percentage) + "%");
            } else {
                root.show(Icons.batteryMedium, Colors.outline, "On battery", Battery.timeToEmpty ? Battery.timeToEmpty + " left" : Math.round(Battery.percentage) + "%");
            }
        }

        // Battery.qml owns the threshold logic and used to shell out to notify-send;
        // it now hands the alert here so it renders in the notch instead.
        function onBatteryAlert(title, body, urgency) {
            root.show(Icons.batteryLow, urgency === "critical" ? Colors.red : Colors.yellow, title, body);
        }

        function onChargeStateChanged() {
            if (Battery.percentage >= 99 && Battery.isPluggedIn) {
                root.show(Icons.batteryFull, Colors.green, "Fully charged", "100%");
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
                root.show(Icons.bluetoothConnected, Colors.cyan, "Connected", now === 1 ? "Bluetooth device" : now + " devices");
            } else {
                root.show(Icons.bluetooth, Colors.outline, "Disconnected", now === 0 ? "No devices" : now + " left");
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
                root.show(Icons.wifiHigh, Colors.cyan, ssid, "Wi-Fi connected");
            } else if (prev) {
                root.show(Icons.wifiOff, Colors.outline, "Wi-Fi", "Disconnected");
            }
        }
    }

    Row {
        id: eventRow
        anchors.centerIn: parent
        spacing: 11
        visible: root.current !== null

        Rectangle {
            width: 30
            height: 30
            radius: 999
            anchors.verticalCenter: parent.verticalCenter
            color: root.current ? Qt.rgba(root.current.accent.r, root.current.accent.g, root.current.accent.b, 0.16) : "transparent"

            Text {
                anchors.centerIn: parent
                text: root.current ? root.current.icon : ""
                font.family: Icons.font
                font.pixelSize: 16
                color: root.current ? root.current.accent : Colors.outline
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: root.current ? root.current.title : ""
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(1)
                font.weight: Font.Bold
                color: root.current ? root.current.accent : Colors.overBackground
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                text: root.current ? root.current.subtitle : ""
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.outline
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
}
