import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

Item {
    id: root

    implicitWidth: 570
    implicitHeight: 236

    property string arrowPosition: "top" // "top", "left", "none"
    readonly property color cardBgColor: "#11141c"

    signal requestBack()
    property bool showBackButton: true

    // background panel card
    Rectangle {
        id: panelCard
        anchors.fill: parent
        anchors.topMargin: root.arrowPosition === "top" ? 9 : 0
        anchors.leftMargin: root.arrowPosition === "left" ? 9 : 0
        radius: Styling.radius(22)
        color: root.arrowPosition === "none" ? "transparent" : root.cardBgColor
        border.width: root.arrowPosition === "none" ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        layer.enabled: root.arrowPosition !== "none"
        layer.effect: Shadow {}

        // main content layout with two optically balanced columns
        RowLayout {
            anchors.fill: parent
            anchors.margins: root.arrowPosition === "none" ? 6 : 18
            spacing: 16

            // LEFT COLUMN: today intake focus & controls
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 255
                Layout.fillHeight: true
                spacing: 8

                // header row: back button + icon + title + goal tag + apple switch
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 8

                    // back button
                    Rectangle {
                        visible: root.showBackButton
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: 13
                        color: backBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Icons.arrowLeft
                            font.family: Icons.font
                            font.pixelSize: 13
                            color: backBtnHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                        }

                        HoverHandler { id: backBtnHover }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestBack()
                        }
                    }

                    Row {
                        spacing: 6
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "<font face='Symbols Nerd Font'>\uf043</font>"
                            font.pixelSize: 14
                            textFormat: Text.RichText
                            color: "#007AFF"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Hydration"
                            font.family: Styling.defaultFont
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.3
                            color: "#ffffff"
                        }
                    }

                    // goal badge tag
                    Rectangle {
                        height: 20
                        radius: 10
                        width: goalBadgeLabel.implicitWidth + 14
                        color: Qt.rgba(0, 122, 255, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(0, 122, 255, 0.24)

                        Text {
                            id: goalBadgeLabel
                            anchors.centerIn: parent
                            text: "Goal: " + HydrationService.dailyGoal + "/d"
                            font.family: Styling.defaultFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: "#38bdf8"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // apple toggle switch
                    Rectangle {
                        id: featureSwitch
                        width: 36
                        height: 20
                        radius: 10
                        color: HydrationService.enabled ? "#007AFF" : Qt.rgba(1, 1, 1, 0.14)
                        border.width: 1
                        border.color: HydrationService.enabled ? Qt.rgba(56, 189, 248, 0.4) : Qt.rgba(1, 1, 1, 0.08)

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation { duration: 160 }
                        }

                        // knob
                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            x: HydrationService.enabled ? parent.width - width - 2 : 2
                            color: "#ffffff"

                            Behavior on x {
                                enabled: Config.animDuration > 0
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: HydrationService.toggleEnabled()
                        }
                    }
                }

                // hero intake & action card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 82
                    radius: 16
                    color: !HydrationService.enabled ? Qt.rgba(1, 1, 1, 0.03) : (HydrationService.alertActive ? Qt.rgba(255, 69, 58, 0.12) : Qt.rgba(0, 122, 255, 0.09))
                    border.width: 1
                    border.color: !HydrationService.enabled ? Qt.rgba(1, 1, 1, 0.05) : (HydrationService.alertActive ? Qt.rgba(255, 69, 58, 0.38) : Qt.rgba(0, 122, 255, 0.25))

                    Behavior on color {
                        enabled: Config.animDuration > 0
                        ColorAnimation { duration: 180 }
                    }
                    Behavior on border.color {
                        enabled: Config.animDuration > 0
                        ColorAnimation { duration: 180 }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // left: intake metrics & progress bar
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Row {
                                spacing: 6
                                Text {
                                    text: "TODAY'S INTAKE"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.6
                                    color: HydrationService.enabled ? (HydrationService.alertActive ? "#ff6961" : "#70b5ff") : Qt.rgba(1, 1, 1, 0.4)
                                }

                                Text {
                                    visible: HydrationService.goalReached
                                    text: "REACHED ✨"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#38bdf8"
                                }
                            }

                            Row {
                                spacing: 4
                                Layout.alignment: Qt.AlignLeft

                                Text {
                                    text: String(HydrationService.todayCount)
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 28
                                    font.weight: Font.Bold
                                    font.letterSpacing: -0.8
                                    color: "#ffffff"
                                }

                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: " / " + HydrationService.dailyGoal + " drinks"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                }
                            }

                            // goal progress bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 2.5
                                color: Qt.rgba(1, 1, 1, 0.08)

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(parent.radius * 2, parent.width * HydrationService.goalProgress)
                                    radius: parent.radius
                                    color: HydrationService.goalReached ? "#38bdf8" : "#007AFF"

                                    Behavior on width {
                                        enabled: Config.animDuration > 0
                                        NumberAnimation { duration: 250; easing.type: Easing.OutQuart }
                                    }
                                }
                            }
                        }

                        // right: primary drink action + subtle undo
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            // drink button
                            Rectangle {
                                id: drinkNowBtn
                                Layout.alignment: Qt.AlignHCenter
                                width: 88
                                height: 34
                                radius: 17
                                color: drinkNowHover.hovered ? "#0064d2" : "#007AFF"
                                scale: drinkNowMouse.pressed ? 0.94 : 1.0

                                Behavior on scale {
                                    enabled: Config.animDuration > 0
                                    NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                                }

                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation { duration: 150 }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Canvas {
                                        width: 8
                                        height: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        antialiasing: true
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.clearRect(0, 0, width, height);
                                            ctx.fillStyle = "#ffffff";
                                            ctx.beginPath();
                                            ctx.moveTo(4, 0);
                                            ctx.bezierCurveTo(6, 3, 8, 5.5, 8, 7);
                                            ctx.bezierCurveTo(8, 9, 6.2, 10, 4, 10);
                                            ctx.bezierCurveTo(1.8, 10, 0, 9, 0, 7);
                                            ctx.bezierCurveTo(0, 5.5, 2, 3, 4, 0);
                                            ctx.closePath();
                                            ctx.fill();
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Drink"
                                        font.family: Styling.defaultFont
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: "#ffffff"
                                    }
                                }

                                HoverHandler { id: drinkNowHover }
                                MouseArea {
                                    id: drinkNowMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: HydrationService.drink()
                                }
                            }

                            // subtle undo button
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Undo (-1)"
                                visible: HydrationService.todayCount > 0
                                font.family: Styling.defaultFont
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: undoHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)

                                HoverHandler { id: undoHover }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: HydrationService.undoDrink()
                                }
                            }
                        }
                    }
                }

                // reminder countdown & interval stepper card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.05)
                    opacity: HydrationService.enabled ? 1.0 : 0.4
                    enabled: HydrationService.enabled

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8

                        // next reminder countdown
                        Row {
                            spacing: 6
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "NEXT IN"
                                font.family: Styling.defaultFont
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                                color: Qt.rgba(1, 1, 1, 0.45)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: HydrationService.formattedTime
                                font.family: Styling.defaultFont
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: HydrationService.alertActive ? "#ff453a" : "#ffffff"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // stepper capsule
                        Rectangle {
                            height: 26
                            width: stepperRow.implicitWidth + 8
                            radius: 13
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.08)

                            Row {
                                id: stepperRow
                                anchors.centerIn: parent
                                spacing: 4

                                // minus button
                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: minusHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                                    scale: minusMouse.pressed ? 0.88 : 1.0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "−"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: minusHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                                    }

                                    HoverHandler { id: minusHover }
                                    MouseArea {
                                        id: minusMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: HydrationService.stepInterval(-5)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: HydrationService.intervalMinutes + "m"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#ffffff"
                                }

                                // plus button
                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: plusHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                                    scale: plusMouse.pressed ? 0.88 : 1.0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: plusHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                                    }

                                    HoverHandler { id: plusHover }
                                    MouseArea {
                                        id: plusMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: HydrationService.stepInterval(5)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // RIGHT COLUMN: 14-day activity & insights
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 275
                Layout.fillHeight: true
                spacing: 8

                // header row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    spacing: 8

                    Text {
                        text: "14-Day Activity"
                        font.family: Styling.defaultFont
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.2
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "Today: " + HydrationService.todayCount + " drinks"
                        font.family: Styling.defaultFont
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }
                }

                // activity bar chart card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 82
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.03)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.05)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 8
                        anchors.bottomMargin: 6
                        spacing: 0

                        Repeater {
                            model: HydrationService.history

                            Item {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                readonly property bool isToday: index === (HydrationService.history.length - 1)
                                readonly property int countVal: modelData.count || 0
                                readonly property real barFrac: Math.min(1.0, countVal / Math.max(1, HydrationService.dailyGoal))

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 3

                                    // bar track capsule
                                    Rectangle {
                                        id: barTrack
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.fillHeight: true
                                        Layout.preferredWidth: 7
                                        radius: 3.5
                                        color: Qt.rgba(1, 1, 1, 0.08)

                                        // filled water bar
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 7
                                            height: countVal > 0 ? Math.max(5, barTrack.height * parent.parent.barFrac) : 3
                                            radius: 3.5
                                            color: parent.parent.isToday ? "#38bdf8" : "#007AFF"
                                            opacity: parent.parent.isToday ? 1.0 : (countVal > 0 ? (0.45 + 0.55 * parent.parent.barFrac) : 0.25)

                                            Behavior on height {
                                                enabled: Config.animDuration > 0
                                                NumberAnimation { duration: 250; easing.type: Easing.OutQuart }
                                            }
                                        }
                                    }

                                    // weekday initial
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.day || ""
                                        font.family: Styling.defaultFont
                                        font.pixelSize: 9
                                        font.weight: parent.parent.isToday ? Font.Bold : Font.Medium
                                        color: parent.parent.isToday ? "#38bdf8" : Qt.rgba(1, 1, 1, 0.35)
                                    }

                                    // today indicator dot
                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 3
                                        height: 3
                                        radius: 1.5
                                        color: "#38bdf8"
                                        visible: parent.parent.isToday
                                    }
                                }
                            }
                        }
                    }
                }

                // insights metrics bento bar: streak | daily avg | record
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.06)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 0

                        // streak cell
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "STREAK"
                                font.family: Styling.defaultFont
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                                color: Qt.rgba(1, 1, 1, 0.45)
                            }

                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Text {
                                    text: String(HydrationService.streak)
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: "#38bdf8"
                                }

                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: "d"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: "#38bdf8"
                                }
                            }
                        }

                        // divider
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 24
                            color: Qt.rgba(1, 1, 1, 0.07)
                        }

                        // average cell
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "DAILY AVG"
                                font.family: Styling.defaultFont
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                                color: Qt.rgba(1, 1, 1, 0.45)
                            }

                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Text {
                                    text: HydrationService.average.toFixed(1)
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }

                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: "/d"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                }
                            }
                        }

                        // divider
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 24
                            color: Qt.rgba(1, 1, 1, 0.07)
                        }

                        // best record cell
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "RECORD"
                                font.family: Styling.defaultFont
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                                color: Qt.rgba(1, 1, 1, 0.45)
                            }

                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Text {
                                    text: String(HydrationService.bestCount)
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }

                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: "max"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // seamless pointer arrow with soft rounded apex fused into panel card
    Canvas {
        id: arrowCanvas
        visible: root.arrowPosition !== "none"
        z: 10
        antialiasing: true
        width: root.arrowPosition === "top" ? 28 : 12
        height: root.arrowPosition === "top" ? 12 : 28
        anchors.bottom: root.arrowPosition === "top" ? panelCard.top : undefined
        anchors.bottomMargin: root.arrowPosition === "top" ? -3 : 0
        anchors.horizontalCenter: root.arrowPosition === "top" ? panelCard.horizontalCenter : undefined
        anchors.right: root.arrowPosition === "left" ? panelCard.left : undefined
        anchors.rightMargin: root.arrowPosition === "left" ? -3 : 0
        anchors.verticalCenter: root.arrowPosition === "left" ? panelCard.verticalCenter : undefined

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            if (root.arrowPosition === "top") {
                // fill path seamlessly overlaps into card to cover top border
                ctx.beginPath();
                ctx.moveTo(0, height);
                ctx.lineTo(0, 9);
                ctx.quadraticCurveTo(2.5, 9, 4, 8);
                ctx.lineTo(11, 3);
                ctx.quadraticCurveTo(14, 0.5, 17, 3);
                ctx.lineTo(24, 8);
                ctx.quadraticCurveTo(25.5, 9, 28, 9);
                ctx.lineTo(28, height);
                ctx.closePath();
                ctx.fillStyle = root.cardBgColor;
                ctx.fill();

                // stroke path across outer edges and rounded apex
                ctx.beginPath();
                ctx.moveTo(0, 9);
                ctx.quadraticCurveTo(2.5, 9, 4, 8);
                ctx.lineTo(11, 3);
                ctx.quadraticCurveTo(14, 0.5, 17, 3);
                ctx.lineTo(24, 8);
                ctx.quadraticCurveTo(25.5, 9, 28, 9);
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08);
                ctx.lineWidth = 1;
                ctx.stroke();
            } else if (root.arrowPosition === "left") {
                // fill path overlaps into card
                ctx.beginPath();
                ctx.moveTo(width, 0);
                ctx.lineTo(9, 0);
                ctx.quadraticCurveTo(9, 2.5, 8, 4);
                ctx.lineTo(3, 11);
                ctx.quadraticCurveTo(0.5, 14, 3, 17);
                ctx.lineTo(8, 24);
                ctx.quadraticCurveTo(9, 25.5, 9, 28);
                ctx.lineTo(width, 28);
                ctx.closePath();
                ctx.fillStyle = root.cardBgColor;
                ctx.fill();

                // stroke path across outer edges and rounded apex
                ctx.beginPath();
                ctx.moveTo(9, 0);
                ctx.quadraticCurveTo(9, 2.5, 8, 4);
                ctx.lineTo(3, 11);
                ctx.quadraticCurveTo(0.5, 14, 3, 17);
                ctx.lineTo(8, 24);
                ctx.quadraticCurveTo(9, 25.5, 9, 28);
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08);
                ctx.lineWidth = 1;
                ctx.stroke();
            }
        }

        Component.onCompleted: requestPaint()
    }
}
