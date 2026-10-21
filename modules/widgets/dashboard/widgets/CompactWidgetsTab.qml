import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root
    implicitWidth: 520
    implicitHeight: 220

    FullPlayer {
        id: fullPlayer
        anchors.fill: parent
    }
}
