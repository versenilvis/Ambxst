pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.modules.widgets.dashboard.controls
import qs.config

Item {
    id: root

    required property var bar
    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false

    // Popup visibility state
    property bool popupOpen: wifiPopup.isOpen

    Layout.preferredWidth: vertical ? 36 : buttonBg.implicitWidth
    Layout.preferredHeight: vertical ? buttonBg.implicitHeight : 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: Config.showBackground

        implicitWidth: vertical ? 36 : rowLayout.implicitWidth + 24
        implicitHeight: vertical ? 36 : 36

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        RowLayout {
            id: rowLayout
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            Text {
                text: NetworkService.wifiIconForStrength(NetworkService.networkStrength)
                font.family: Icons.font
                font.pixelSize: 16
                color: root.popupOpen ? buttonBg.item : Colors.overBackground
            }


            Text {
                visible: NetworkService.wifi && NetworkService.networkName !== ""
                text: NetworkService.networkName
                font.family: Styling.defaultFont
                font.pixelSize: Config.theme.fontSize
                font.bold: true
                color: root.popupOpen ? buttonBg.item : Colors.overBackground
            }
        }

        Text {
            visible: root.vertical
            anchors.centerIn: parent
            text: NetworkService.wifiIconForStrength(NetworkService.networkStrength)
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Colors.overBackground
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: wifiPopup.toggle()
        }

        StyledToolTip {
            show: root.isHovered && !root.popupOpen
            tooltipText: {
                if (!NetworkService.wifiEnabled) return "Wifi Disabled";
                if (!NetworkService.wifi && !NetworkService.ethernet) return "Disconnected";
                if (NetworkService.ethernet) return "Ethernet Connected";
                return NetworkService.networkName || "Connected";
            }
        }
    }

    BarPopup {
        id: wifiPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 12

        // Shift ONLY the dropdown menu 20px to the right
        anchor.rect.x: root.vertical ? (barAtLeft ? anchorItem.width + visualMargin - shadowMargin : -totalWidth + shadowMargin - visualMargin) : ((anchorItem.width - totalWidth) / 2) + 20

        contentWidth: 320
        contentHeight: Math.max(100, Math.min(400, (networkList.count * 52) + 64))

        // Rescan when opening
        onIsOpenChanged: {
            if (isOpen) {
                NetworkService.rescanWifi();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            PanelTitlebar {
                title: "Wi-Fi"
                statusText: NetworkService.wifiConnecting ? "Connecting..." : (NetworkService.wifiStatus === "limited" ? "Limited" : "")
                statusColor: NetworkService.wifiStatus === "limited" ? Colors.warning : Styling.srItem("overprimary")
                showToggle: true
                toggleChecked: NetworkService.wifiStatus !== "disabled"

                actions: [
                    {
                        icon: Icons.globe,
                        tooltip: "Open captive portal",
                        enabled: NetworkService.wifiStatus === "limited",
                        onClicked: function () {
                            NetworkService.openPublicWifiPortal();
                        }
                    },
                    {
                        icon: Icons.popOpen,
                        tooltip: "Network settings",
                        onClicked: function () {
                            Quickshell.execDetached(["nm-connection-editor"]);
                        }
                    },
                    {
                        icon: Icons.sync,
                        tooltip: "Rescan networks",
                        enabled: NetworkService.wifiEnabled,
                        loading: NetworkService.wifiScanning,
                        onClicked: function () {
                            NetworkService.rescanWifi();
                        }
                    }
                ]

                onToggleChanged: checked => {
                    NetworkService.enableWifi(checked);
                    if (checked) {
                        NetworkService.rescanWifi();
                    }
                }
            }

            ListView {
                id: networkList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: NetworkService.friendlyWifiNetworks

                delegate: WifiNetworkItem {
                    required property var modelData
                    id: networkItem
                    width: networkList.width
                    network: modelData
                }

                ScrollBar.vertical: ScrollBar {
                    active: networkList.moving || networkList.flicking
                }
            }

            // Empty state
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                visible: networkList.count === 0 && !NetworkService.wifiScanning
                text: NetworkService.wifiEnabled ? "No networks found" : "Wi-Fi is disabled"
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color: Colors.overSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
