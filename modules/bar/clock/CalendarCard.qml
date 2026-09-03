pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

Item {
    id: root

    readonly property color accentRed: Colors.red
    readonly property color cardBg: "#0c0c11"
    readonly property color cardBorder: Qt.rgba(1, 1, 1, 0.08)

    property date now: new Date()
    property int monthShift: 0

    // Refresh every minute
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    readonly property date viewingDate: new Date(now.getFullYear(), now.getMonth() + monthShift, 1)
    readonly property int viewingYear: viewingDate.getFullYear()
    readonly property int viewingMonth: viewingDate.getMonth()

    readonly property int firstWeekday: new Date(viewingYear, viewingMonth, 1).getDay()
    readonly property int daysInMonth: new Date(viewingYear, viewingMonth + 1, 0).getDate()

    readonly property int todayDate: now.getDate()
    readonly property int todayMonth: now.getMonth()
    readonly property int todayYear: now.getFullYear()
    readonly property bool isCurrentMonth: (viewingYear === todayYear && viewingMonth === todayMonth)

    readonly property int weekNumber: {
        let d = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
        let dayNum = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - dayNum);
        let yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    }

    readonly property int dayOfYear: {
        let start = new Date(now.getFullYear(), 0, 0);
        let diff = now - start;
        return Math.floor(diff / (1000 * 60 * 60 * 24));
    }

    function getDayNumber(index) {
        let dayNum = index - firstWeekday + 1;
        if (dayNum >= 1 && dayNum <= daysInMonth)
            return dayNum;
        return 0;
    }

    width: 440
    height: 248

    // Single unified dark card container
    Rectangle {
        id: mainCard
        anchors.fill: parent
        radius: 20
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            // Left Section: Day & Agenda Summary
            Item {
                id: leftSection
                width: 164
                height: parent.height

                Column {
                    anchors.fill: parent
                    spacing: 2

                    // Day name in uppercase soft red
                    Text {
                        text: root.now.toLocaleDateString(Qt.locale(), "dddd").toUpperCase()
                        color: root.accentRed
                        font.family: Config.theme.font
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 1.0
                    }

                    // Large clean date number
                    Text {
                        text: root.now.getDate()
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 52
                        font.weight: Font.Normal
                    }

                    Item {
                        width: parent.width
                        height: 12
                    }

                    // Agenda item 1: Date & month full detail
                    Row {
                        spacing: 8
                        width: parent.width

                        Rectangle {
                            width: 3.5
                            height: 32
                            radius: 1.75
                            color: root.accentRed
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: parent.width - 12

                            Text {
                                text: root.now.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: Qt.formatDateTime(root.now, "hh:mm") + " · All Day"
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 10
                    }

                    // Agenda item 2: Week & Day counter
                    Row {
                        spacing: 8
                        width: parent.width

                        Rectangle {
                            width: 3.5
                            height: 20
                            radius: 1.75
                            color: Colors.yellow
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: `Week ${root.weekNumber} · Day ${root.dayOfYear}`
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                width: 1
                height: parent.height - 12
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.07)
            }

            // Right Section: Full Month Calendar Grid
            Item {
                id: rightSection
                width: parent.width - leftSection.width - 1 - 28
                height: parent.height

                Column {
                    anchors.fill: parent
                    spacing: 8

                    // Header: Month in uppercase soft red with navigation
                    RowLayout {
                        width: parent.width

                        Text {
                            Layout.fillWidth: true
                            text: (root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM") + (root.monthShift !== 0 ? ` ${root.viewingYear}` : "")).toUpperCase()
                            color: root.accentRed
                            font.family: Config.theme.font
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            font.letterSpacing: 1.0

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.monthShift = 0
                            }
                        }

                        // Prev month button
                        Text {
                            text: "‹"
                            color: Colors.outline
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            padding: 4

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.monthShift--
                            }
                        }

                        // Next month button
                        Text {
                            text: "›"
                            color: Colors.outline
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            padding: 4

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.monthShift++
                            }
                        }
                    }

                    // Weekday headers: S M T W T F S
                    Row {
                        width: parent.width

                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]

                            Item {
                                required property string modelData
                                width: rightSection.width / 7
                                height: 18

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    color: Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }

                    // Days Grid (6 rows of 7 = 42 cells)
                    Grid {
                        id: daysGrid
                        columns: 7
                        columnSpacing: 0
                        rowSpacing: 3
                        width: parent.width

                        Repeater {
                            model: 42

                            Item {
                                id: dayCell
                                required property int index

                                readonly property int dayNum: root.getDayNumber(index)
                                readonly property bool isToday: root.isCurrentMonth && dayCell.dayNum === root.todayDate

                                width: rightSection.width / 7
                                height: 24

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: root.accentRed
                                    visible: dayCell.isToday
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: dayCell.dayNum > 0 ? `${dayCell.dayNum}` : ""
                                    color: dayCell.isToday ? Colors.surfaceContainerLowest : Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: 13
                                    font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
