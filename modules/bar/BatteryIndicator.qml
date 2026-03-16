pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    // Popup visibility state
    property bool popupOpen: batteryPopup.isOpen

    // Function to interpolate color between green and red based on battery percentage
    function getBatteryColor() {
        if (!Battery.available)
            return Colors.overBackground;

        const pct = Battery.percentage;
        if (pct <= 15)
            return Colors.red;
        if (pct >= 85)
            return Colors.green;

        // Linear interpolation between red (15%) and green (85%)
        const ratio = (pct - 15) / (85 - 15);
        return Qt.rgba(Colors.red.r + (Colors.green.r - Colors.red.r) * ratio, Colors.red.g + (Colors.green.g - Colors.red.g) * ratio, Colors.red.b + (Colors.green.b - Colors.red.b) * ratio, 1);
    }

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    // Main button with circular progress
    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        // Background highlight on hover
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

        // Circular progress indicator (only if battery available)
        Item {
            id: progressCanvas
            anchors.centerIn: parent
            width: 32
            height: 32
            visible: Battery.available

            property real angle: (Battery.percentage / 100) * (360 - 2 * gapAngle)
            property real radius: 12
            property real lineWidth: 3
            property real gapAngle: 45

            Canvas {
                id: canvas
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    let ctx = getContext("2d");
                    ctx.reset();

                    let centerX = width / 2;
                    let centerY = height / 2;
                    let radius = progressCanvas.radius;
                    let lineWidth = progressCanvas.lineWidth;

                    ctx.lineCap = "round";

                    // Base start angle (matching CircularControl: bottom + gap)
                    let baseStartAngle = (Math.PI / 2) + (progressCanvas.gapAngle * Math.PI / 180);
                    let progressAngleRad = progressCanvas.angle * Math.PI / 180;

                    // Draw background track (remaining part)
                    let totalAngleRad = (360 - 2 * progressCanvas.gapAngle) * Math.PI / 180;

                    ctx.strokeStyle = Colors.outlineVariant;
                    ctx.lineWidth = lineWidth;
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius, baseStartAngle + progressAngleRad, baseStartAngle + totalAngleRad, false);
                    ctx.stroke();

                    // Draw progress
                    if (progressCanvas.angle > 0) {
                        ctx.strokeStyle = root.getBatteryColor();
                        ctx.lineWidth = lineWidth;
                        ctx.beginPath();
                        ctx.arc(centerX, centerY, radius, baseStartAngle, baseStartAngle + progressAngleRad, false);
                        ctx.stroke();
                    }
                }

                Connections {
                    target: progressCanvas
                    function onAngleChanged() {
                        canvas.requestPaint();
                    }
                }

                Connections {
                    target: Battery
                    function onPercentageChanged() {
                        canvas.requestPaint();
                    }
                }
            }

            Behavior on angle {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Central icon (Lightning for charging, tiered Battery icons for unplugged)
        Text {
            id: batteryIcon
            anchors.centerIn: parent
            text: Battery.available ? (Battery.isPluggedIn ? Icons.lightning : Battery.getBatteryIcon()) : PowerProfile.getProfileIcon(PowerProfile.currentProfile)
            font.family: Icons.font
            font.pixelSize: Battery.available ? 14 : 18
            color: root.popupOpen ? buttonBg.item : Colors.overBackground

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration / 2
                }
            }

            Connections {
                target: Battery
                function onIsPluggedInChanged() {
                    batteryIcon.text = Battery.available ? (Battery.isPluggedIn ? Icons.lightning : Battery.getBatteryIcon()) : PowerProfile.getProfileIcon(PowerProfile.currentProfile);
                }
                function onPercentageChanged() {
                    if (!Battery.isPluggedIn) {
                        batteryIcon.text = Battery.available ? Battery.getBatteryIcon() : PowerProfile.getProfileIcon(PowerProfile.currentProfile);
                    }
                }
                function onAvailableChanged() {
                    batteryIcon.text = Battery.available ? (Battery.isPluggedIn ? Icons.lightning : Battery.getBatteryIcon()) : PowerProfile.getProfileIcon(PowerProfile.currentProfile);
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: batteryPopup.toggle()
        }

        StyledToolTip {
            visible: root.isHovered && !root.popupOpen
            tooltipText: Battery.available ? ("Battery: " + Math.round(Battery.percentage) + "%" + (Battery.isCharging ? " (Charging)" : "")) : ("Power Profile: " + PowerProfile.getProfileDisplayName(PowerProfile.currentProfile))
        }
    }

    // Battery popup with Power Profiles
    BarPopup {
        id: batteryPopup
        anchorItem: buttonBg
        bar: root.bar

        contentWidth: 220
        contentHeight: 80 + batteryPopup.popupPadding * 2

        RowLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 6

            // LEFT SIDE: Main Battery Display (Ultra Compact)
            StyledRect {
                id: batteryMainCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 160
                variant: "common"
                enableShadow: false
                radius: Styling.radius(0)

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    // Tiny circular progress
                    Item {
                        width: 40
                        height: 40
                        Layout.alignment: Qt.AlignVCenter

                        Canvas {
                            id: batteryPopupCanvas
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var centerX = width/2; var centerY = height/2;
                                ctx.lineCap = "round";
                                
                                // Background
                                ctx.strokeStyle = Colors.outlineVariant;
                                ctx.lineWidth = 4;
                                ctx.beginPath(); ctx.arc(centerX, centerY, 16, 0, 2*Math.PI); ctx.stroke();

                                // Fill
                                ctx.strokeStyle = root.getBatteryColor();
                                ctx.lineWidth = 4;
                                ctx.beginPath(); 
                                ctx.arc(centerX, centerY, 16, -Math.PI/2, (-Math.PI/2) + (Battery.percentage/100 * 2*Math.PI)); 
                                ctx.stroke();
                            }
                            Connections { 
                                target: Battery
                                function onPercentageChanged() { batteryPopupCanvas.requestPaint(); } 
                            }
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: Battery.available ? (Battery.isPluggedIn ? Icons.lightning : Battery.getBatteryIcon()) : ""
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: Colors.overBackground
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2

                        Text {
                            text: Math.round(Battery.percentage) + "%"
                            font.family: Styling.defaultFont
                            font.pixelSize: 18
                            font.bold: true
                            color: Colors.overBackground
                        }

                        Text {
                            visible: Battery.timeToEmpty !== "" || Battery.timeToFull !== ""
                            text: Battery.isPluggedIn ? Battery.timeToFull : Battery.timeToEmpty
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overBackground
                            opacity: 0.6
                        }
                    }
                }
            }

            // RIGHT SIDE: Mini Power Profiles
            Item {
                Layout.preferredWidth: 36
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                        model: PowerProfile.availableProfiles

                        delegate: StyledRect {
                            id: profileButton
                            required property string modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            readonly property bool isSelected: PowerProfile.currentProfile === modelData
                            property bool buttonHovered: false

                            variant: isSelected ? "primary" : (buttonHovered ? "focus" : "common")
                            enableShadow: false
                            radius: Styling.radius(0)

                            Text {
                                anchors.centerIn: parent
                                text: PowerProfile.getProfileIcon(profileButton.modelData)
                                font.family: Icons.font
                                font.pixelSize: 12
                                color: profileButton.item
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: profileButton.buttonHovered = true
                                onExited: profileButton.buttonHovered = false
                                onClicked: PowerProfile.setProfile(profileButton.modelData)
                            }

                            StyledToolTip {
                                visible: profileButton.buttonHovered
                                tooltipText: PowerProfile.getProfileDisplayName(profileButton.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
