import QtQuick
import qs.modules.globals
import qs.modules.services
import qs.config
import qs.modules.components

ToggleButton {
    buttonIcon: {
        let icon = Config.bar.launcherIcon || Qt.resolvedUrl("../../../assets/ambxst/ambxst-icon.svg").toString().replace("file://", "");
        if (icon === "helium" || icon === "helium-os") {
            return Qt.resolvedUrl("../../../assets/ambxst/ambxst-icon.svg").toString().replace("file://", "");
        }
        return icon;
    }
    iconTint: Config.bar.launcherIconTint
    iconFullTint: Config.bar.launcherIconFullTint
    iconSize: Config.bar.launcherIconSize
    tooltipText: "Open Dashboard"

    onToggle: function () {
        if (GlobalStates.dashboardOpen) {
            GlobalStates.clearLauncherState();
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.dashboardCurrentTab = 0;
            Visibilities.setActiveModule("dashboard");
        }
    }
}
