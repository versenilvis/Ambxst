pragma Singleton

import QtQuick
import Quickshell
import qs.modules.theme
import qs.modules.services

Singleton {
    id: root

    property var availableProfiles: []
    property string currentProfile: ""
    property bool isAvailable: false

    signal profileChanged(string profile)

    Connections {
        target: DaemonClient
        function onPowerProfileReceived(data) {
            if (!data) return;
            root.isAvailable = data.is_available ?? false;
            root.currentProfile = data.current ?? "";
            root.availableProfiles = data.profiles ?? [];
            root.profileChanged(root.currentProfile);
        }
    }

    Component.onCompleted: {
        updateCurrentProfile();
    }

    function updateCurrentProfile() {
        DaemonClient.sendCommand({ type: "get_power_profile" });
    }

    function updateAvailableProfiles() {
        DaemonClient.sendCommand({ type: "get_power_profile" });
    }

    function setProfile(profileName) {
        if (!isAvailable) {
            console.warn("PowerProfile: cannot set profile - service not available");
            return;
        }

        if (availableProfiles.indexOf(profileName) === -1) {
            console.warn("PowerProfile: profile not available:", profileName);
            return;
        }

        DaemonClient.sendCommand({ type: "set_power_profile", profile: profileName });
    }

    // map profile names to icons
    function getProfileIcon(profileName) {
        if (profileName === "power-saver") return Icons.powerSave;
        if (profileName === "balanced") return Icons.balanced;
        if (profileName === "performance") return Icons.performance;
        return Icons.balanced;
    }

    // map profile names to display names
    function getProfileDisplayName(profileName) {
        if (profileName === "power-saver") return "Power Save";
        if (profileName === "balanced") return "Balanced";
        if (profileName === "performance") return "Performance";
        return profileName;
    }
}
