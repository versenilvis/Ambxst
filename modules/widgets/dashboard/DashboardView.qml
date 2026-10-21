import QtQuick
import qs.modules.widgets.dashboard
import qs.modules.services

Item {
    implicitWidth: dashboardItem.implicitWidth
    implicitHeight: dashboardItem.implicitHeight

    readonly property int leftPanelWidth: 44

    Dashboard {
        id: dashboardItem
        anchors.fill: parent
        leftPanelWidth: parent.leftPanelWidth

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Visibilities.setActiveModule("");
                event.accepted = true;
            }
        }

        Component.onCompleted: {
            Qt.callLater(() => {
                forceActiveFocus();
            });
        }
    }
}
