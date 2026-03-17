pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    required property WifiAccessPoint network

    property bool expanded: false

    property bool showProperties: false
    property string savedPassword: ""
    property bool revealPassword: false

    implicitHeight: contentColumn.implicitHeight + 16

    onShowPropertiesChanged: {
        if (showProperties && savedPassword === "") {
            NetworkService.getWifiPassword(root.network.ssid, (pwd) => {
                root.savedPassword = pwd;
            });
        }
    }

    Behavior on implicitHeight {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    StyledRect {
        anchors.fill: parent
        variant: mouseArea.containsMouse ? "focus" : "common"
        radius: Styling.radius(4)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 8
        spacing: 8

        // Main row with network info
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 12

            // Wi-Fi signal icon with security indicator
            Item {
                width: 24
                height: 24

                Text {
                    anchors.centerIn: parent
                    text: {
                        const strength = root.network?.strength ?? 0;
                        if (strength > 80)
                            return Icons.wifiHigh;
                        if (strength > 55)
                            return Icons.wifiMedium;
                        if (strength > 30)
                            return Icons.wifiLow;
                        return Icons.wifiNone;
                    }
                    font.family: Icons.font
                    font.pixelSize: 20
                    color: root.network?.active ? Styling.srItem("overprimary") : Colors.overBackground
                }

                // Lock icon for secure networks
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -2
                    visible: root.network?.isSecure ?? false
                    text: Icons.lock
                    font.family: Icons.font
                    font.pixelSize: 10
                    color: Colors.overSurfaceVariant
                }
            }

            // Network name and status
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: root.network?.ssid ?? "Unknown"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    font.weight: Font.Medium
                    color: Colors.overBackground
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.network?.active || root.expanded
                    text: {
                        if (root.network?.active)
                            return "Connected";
                        if (root.network?.isSecure)
                            return "Secured";
                        return "Open";
                    }
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                    elide: Text.ElideRight

                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration / 2
                        }
                    }
                }
            }

            // Frequency badge (5GHz indicator)
            StyledRect {
                visible: root.network?.is5GHz ?? false
                variant: "common"
                implicitWidth: 32
                implicitHeight: 18
                radius: Styling.radius(-4)

                Text {
                    anchors.centerIn: parent
                    text: "5G"
                    font.family: Config.theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Colors.overSurfaceVariant
                }
            }
        }

        // Expanded content with connect/disconnect button and password input
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 8
            opacity: root.expanded ? 1 : 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }

            // Password input (shown when required)
            SearchInput {
                id: passwordInput
                Layout.fillWidth: true
                visible: root.network?.askingPassword ?? false
                placeholderText: "Enter password..."
                passwordMode: true
                implicitHeight: 40
                variant: "internalbg"

                onAccepted: {
                    if (text.length > 0) {
                        NetworkService.changePassword(root.network, text);
                        text = "";
                    }
                }
            }

            // Properties details (visible when showProperties is true)
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.showProperties
                spacing: 4
                
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Colors.overSurfaceVariant
                    opacity: 0.2
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Text {
                        text: "BSSID:"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        Layout.preferredWidth: 60
                    }
                    Text {
                        text: root.network?.bssid ?? "Unknown"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Text {
                        text: "Frequency:"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        Layout.preferredWidth: 60
                    }
                    Text {
                        text: root.network?.frequency + " MHz"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.savedPassword !== ""
                    
                    Text {
                        text: "Password:"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        Layout.preferredWidth: 60
                    }
                    
                    Text {
                        text: root.revealPassword ? root.savedPassword : "••••••••"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }

                    Button {
                        flat: true
                        implicitWidth: 24
                        implicitHeight: 24
                        background: null
                        contentItem: Text {
                            text: Icons.xeyes
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: root.revealPassword ? Colors.primary : Colors.overSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: root.revealPassword = !root.revealPassword
                    }
                }
            }

            // Action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    id: propsButton
                    flat: true
                    implicitWidth: 32
                    implicitHeight: 32
                    
                    background: StyledRect {
                        variant: propsButton.hovered ? "focus" : "internalbg"
                        radius: Styling.radius(4)
                    }

                    contentItem: Text {
                        text: Icons.info
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: root.showProperties ? Colors.primary : Colors.overSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: root.showProperties = !root.showProperties

                    StyledToolTip {
                        visible: propsButton.hovered
                        tooltipText: "Network details"
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    id: forgetButton
                    flat: true
                    implicitWidth: 32
                    implicitHeight: 32
                    visible: !root.network?.active

                    background: StyledRect {
                        variant: forgetButton.hovered ? "focus" : "internalbg"
                        radius: Styling.radius(4)
                    }

                    contentItem: Text {
                        text: Icons.trash
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.error
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        NetworkService.deleteWifiNetwork(root.network.ssid);
                    }

                    StyledToolTip {
                        visible: forgetButton.hovered
                        tooltipText: "Forget network"
                    }
                }

                Button {
                    id: actionButton
                    flat: true
                    implicitWidth: 100
                    implicitHeight: 32

                    background: StyledRect {
                        variant: root.network?.active ? "internalbg" : "primary"
                        radius: Styling.radius(4)
                    }

                    contentItem: Text {
                        text: root.network?.active ? "Disconnect" : "Connect"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: root.network?.active ? Colors.overSurfaceVariant : Styling.srItem("primary")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (root.network?.active) {
                            NetworkService.disconnectWifiNetwork();
                        } else {
                            NetworkService.connectToWifiNetwork(root.network);
                        }
                    }
                }
            }
        }
    }
}
