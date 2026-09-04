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
    readonly property bool isPluggedIn: available && !UPower.onBattery
    readonly property bool isCharging: isPluggedIn && primaryDevice.state === UPowerDevice.Charging
    readonly property int chargeState: available ? primaryDevice.state : UPowerDevice.Unknown

    signal powerTransition()

    Timer {
        id: powerDebounceTimer
        interval: 150
        repeat: false
        onTriggered: root.powerTransition()
    }

    onIsPluggedInChanged: powerDebounceTimer.restart()
    onIsChargingChanged: powerDebounceTimer.restart()
    onChargeStateChanged: powerDebounceTimer.restart()

    // Add some helpful descriptive properties if needed
    readonly property string timeToEmpty: available && primaryDevice.timeToEmpty > 0 ? formatTime(primaryDevice.timeToEmpty) : ""
    readonly property string timeToFull: available && primaryDevice.timeToFull > 0 ? formatTime(primaryDevice.timeToFull) : ""

    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    function getBatteryLevelIcon(pct) {
        if (!available && pct === undefined) return Icons.batteryEmpty;
        const val = pct !== undefined ? pct : percentage;
        if (val > 75) return Icons.batteryFull;
        if (val > 50) return Icons.batteryHigh;
        if (val > 25) return Icons.batteryMedium;
        if (val > 5) return Icons.batteryLow;
        return Icons.batteryEmpty;
    }

    function getBatteryIcon() {
        if (!available) return Icons.batteryEmpty;
        if (isPluggedIn) return Icons.batteryCharging;
        return getBatteryLevelIcon(percentage);
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

    // Battery alerts surface in the notch (see NotchEvents) rather than as desktop
    // notifications. The threshold bookkeeping above stays here because it already
    // handles de-duplication and resetting when the battery climbs again.
    signal batteryAlert(string title, string body, string urgency)

    function _sendBatteryNotification(title, body, urgency) {
        root.batteryAlert(title, body, urgency);
    }
}
