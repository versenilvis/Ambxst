import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root
    implicitWidth: 570
    implicitHeight: 190

    readonly property var currentMonitor: Brightness.monitors.length > 0 ? Brightness.monitors[0] : null
    property real brightnessVal: currentMonitor?.brightness ?? 0.8
    property real volumeVal: Audio.volume

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // left 2x2 toggle grid (Control Center style)
        GridLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 260
            columns: 2
            rowSpacing: 10
            columnSpacing: 10

            // wifi toggle
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: NetworkService.activeConnection ? Qt.rgba(0.04, 0.52, 1.0, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: NetworkService.activeConnection ? Qt.rgba(0.04, 0.52, 1.0, 0.5) : Qt.rgba(1, 1, 1, 0.06)

                Behavior on color { ColorAnimation { duration: 180 } }

                MouseArea {
                    id: wifiArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NetworkService.toggleWifi()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: NetworkService.activeConnection ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: NetworkService.activeConnection ? Icons.wifiHigh : Icons.wifiOff
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: "#ffffff"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Wi-Fi"
                            font.family: Styling.defaultFont
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }

                        Text {
                            Layout.fillWidth: true
                            text: NetworkService.activeConnection ? (NetworkService.ssid || "Connected") : "Off"
                            font.family: Styling.defaultFont
                            font.pixelSize: 11
                            color: Qt.rgba(1, 1, 1, 0.5)
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // bluetooth toggle
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                readonly property bool btActive: BluetoothService.adapter?.powered ?? false
                color: btActive ? Qt.rgba(0.04, 0.52, 1.0, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: btActive ? Qt.rgba(0.04, 0.52, 1.0, 0.5) : Qt.rgba(1, 1, 1, 0.06)

                Behavior on color { ColorAnimation { duration: 180 } }

                MouseArea {
                    id: btArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (BluetoothService.adapter) {
                            BluetoothService.adapter.powered = !BluetoothService.adapter.powered;
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: parent.parent.btActive ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.btActive ? Icons.bluetooth : Icons.bluetoothOff
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: "#ffffff"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Bluetooth"
                            font.family: Styling.defaultFont
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }

                        Text {
                            Layout.fillWidth: true
                            text: parent.parent.btActive ? (BluetoothService.connectedDevices.length > 0 ? BluetoothService.connectedDevices[0].name : "On") : "Off"
                            font.family: Styling.defaultFont
                            font.pixelSize: 11
                            color: Qt.rgba(1, 1, 1, 0.5)
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // night light toggle
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                readonly property bool nlActive: NightLightService.active
                color: nlActive ? Qt.rgba(1.0, 0.6, 0.0, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: nlActive ? Qt.rgba(1.0, 0.6, 0.0, 0.5) : Qt.rgba(1, 1, 1, 0.06)

                Behavior on color { ColorAnimation { duration: 180 } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NightLightService.toggle()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: parent.parent.nlActive ? "#ff9500" : Qt.rgba(1, 1, 1, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: Icons.moon
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: "#ffffff"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Night Light"
                            font.family: Styling.defaultFont
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }

                        Text {
                            text: parent.parent.nlActive ? "On" : "Off"
                            font.family: Styling.defaultFont
                            font.pixelSize: 11
                            color: Qt.rgba(1, 1, 1, 0.5)
                        }
                    }
                }
            }

            // caffeine toggle
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                readonly property bool cafActive: CaffeineService.inhibit
                color: cafActive ? Qt.rgba(0.68, 0.35, 0.95, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: cafActive ? Qt.rgba(0.68, 0.35, 0.95, 0.5) : Qt.rgba(1, 1, 1, 0.06)

                Behavior on color { ColorAnimation { duration: 180 } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: CaffeineService.toggleInhibit()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: parent.parent.cafActive ? "#af52de" : Qt.rgba(1, 1, 1, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: Icons.caffeine
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: "#ffffff"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Caffeine"
                            font.family: Styling.defaultFont
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }

                        Text {
                            text: parent.parent.cafActive ? "Active" : "Off"
                            font.family: Styling.defaultFont
                            font.pixelSize: 11
                            color: Qt.rgba(1, 1, 1, 0.5)
                        }
                    }
                }
            }
        }

        // right column: thick apple capsule sliders
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // display brightness capsule
            Rectangle {
                id: displaySliderCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 18
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)
                clip: true

                // filled progress
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, root.brightnessVal))
                    radius: parent.radius
                    color: Qt.rgba(1, 1, 1, 0.22)
                }

                MouseArea {
                    id: brightDrag
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        let pct = Math.max(0.05, Math.min(1.0, mouseX / width));
                        root.brightnessVal = pct;
                        if (root.currentMonitor) {
                            root.currentMonitor.setBrightness(pct);
                        }
                    }

                    onPressed: mouse => updateValue(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed) updateValue(mouse.x);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16

                    Text {
                        text: Icons.sun
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: "#ffffff"
                    }

                    Text {
                        text: "Display"
                        font.family: Styling.defaultFont
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: Math.round(root.brightnessVal * 100) + "%"
                        font.family: Styling.defaultFont
                        font.pixelSize: 13
                        font.bold: true
                        color: Qt.rgba(1, 1, 1, 0.7)
                    }
                }
            }

            // sound volume capsule
            Rectangle {
                id: soundSliderCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 18
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)
                clip: true

                // filled progress
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, Audio.muted ? 0 : root.volumeVal))
                    radius: parent.radius
                    color: Audio.muted ? Qt.rgba(1, 0.2, 0.2, 0.25) : Qt.rgba(0.04, 0.52, 1.0, 0.35)
                }

                MouseArea {
                    id: soundDrag
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        let pct = Math.max(0.0, Math.min(1.0, mouseX / width));
                        root.volumeVal = pct;
                        if (Audio.sink && Audio.sink.audio) {
                            Audio.sink.audio.volume = pct;
                            if (Audio.muted && pct > 0) Audio.sink.audio.muted = false;
                        }
                    }

                    onPressed: mouse => updateValue(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed) updateValue(mouse.x);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16

                    Item {
                        width: 20
                        height: 20

                        Text {
                            anchors.centerIn: parent
                            text: Audio.muted ? Icons.speakerSlash : (root.volumeVal > 0.5 ? Icons.speakerHigh : Icons.speakerLow)
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: Audio.muted ? "#ef4444" : "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Audio.sink && Audio.sink.audio) {
                                    Audio.sink.audio.muted = !Audio.sink.audio.muted;
                                }
                            }
                        }
                    }

                    Text {
                        text: "Sound"
                        font.family: Styling.defaultFont
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: Audio.muted ? "Muted" : (Math.round(root.volumeVal * 100) + "%")
                        font.family: Styling.defaultFont
                        font.pixelSize: 13
                        font.bold: true
                        color: Qt.rgba(1, 1, 1, 0.7)
                    }
                }
            }
        }
    }
}
