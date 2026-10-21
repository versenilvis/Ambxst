pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.modules.bar.clock
import qs.config

BaseWidget {
    id: root

    widgetId: "calendar"
    title: "Calendar"
    icon: Icons.calendar

    width: calendarCard.implicitWidth > 0 ? calendarCard.implicitWidth : 440
    height: calendarCard.implicitHeight > 0 ? calendarCard.implicitHeight : 248
    implicitWidth: width
    implicitHeight: height

    defaultX: 32
    defaultY: 32

    hasCardBackground: false

    CalendarCard {
        id: calendarCard
        anchors.fill: parent
    }
}
