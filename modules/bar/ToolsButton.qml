import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.modules.services

ToggleButton {
    id: toolsButton
    buttonIcon: Icons.camera
    tooltipText: "Screenshot"
    onToggle: function () {
        GlobalStates.screenshotToolVisible = !GlobalStates.screenshotToolVisible;
    }
}
