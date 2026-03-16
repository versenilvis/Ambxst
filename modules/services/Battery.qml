pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.modules.theme

Singleton {
    id: root

    readonly property UPowerDevice primaryDevice: UPower.displayDevice

    readonly property bool available: primaryDevice !== null && primaryDevice.type === UPowerDevice.Battery
    readonly property real percentage: available ? (primaryDevice.percentage * 100) : 0
    readonly property bool isCharging: available && primaryDevice.state === UPowerDevice.Charging
    readonly property bool isPluggedIn: available && (primaryDevice.state === UPowerDevice.Charging || primaryDevice.state === UPowerDevice.FullyCharged)
    readonly property int chargeState: available ? primaryDevice.state : UPowerDevice.Unknown

    // Add some helpful descriptive properties if needed
    readonly property string timeToEmpty: available && primaryDevice.timeToEmpty > 0 ? formatTime(primaryDevice.timeToEmpty) : ""
    readonly property string timeToFull: available && primaryDevice.timeToFull > 0 ? formatTime(primaryDevice.timeToFull) : ""

    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    function getBatteryIcon() {
        if (!available) return Icons.batteryEmpty;
        if (isPluggedIn) return Icons.batteryCharging;
        
        const pct = percentage;
        if (pct > 75) return Icons.batteryFull;
        if (pct > 50) return Icons.batteryHigh;
        if (pct > 25) return Icons.batteryMedium;
        if (pct > 5) return Icons.batteryLow;
        return Icons.batteryEmpty;
    }

    // Low Battery Notifications
    property int _lastNotifiedThreshold: 100

    onPercentageChanged: {
        if (!available || isPluggedIn) {
            _lastNotifiedThreshold = 100;
            return;
        }

        const pct = Math.round(percentage);
        
        // Critical: 2%
        if (pct <= 2 && _lastNotifiedThreshold > 2) {
            _sendBatteryNotification("Critical Battery", `Battery is critically low at ${pct}%. Please plug in now!`, "critical");
            _lastNotifiedThreshold = 2;
        } 
        // Warning: 10%
        else if (pct <= 10 && _lastNotifiedThreshold > 10) {
            _sendBatteryNotification("Low Battery", `Battery is at ${pct}%.`, "critical");
            _lastNotifiedThreshold = 10;
        } 
        // Notice: 20%
        else if (pct <= 20 && _lastNotifiedThreshold > 20) {
            _sendBatteryNotification("Battery Low", `Battery is at ${pct}%.`, "normal");
            _lastNotifiedThreshold = 20;
        } 
        // Reset threshold if battery level increases significantly
        else if (pct > _lastNotifiedThreshold + 5) {
            _lastNotifiedThreshold = 100;
        }
    }

    function _sendBatteryNotification(title, body, urgency) {
        Quickshell.execDetached([
            "notify-send",
            "-a", "System",
            "-u", urgency,
            "-i", "battery-low",
            title,
            body
        ]);
    }
}
