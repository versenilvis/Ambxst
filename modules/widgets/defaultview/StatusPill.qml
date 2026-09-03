import QtQuick
import qs.modules.theme
import qs.config

Item {
    id: root

    property color accentColor: Colors.primary
    property string icon: ""
    property string iconFont: Icons.font
    property string artworkUrl: ""
    property string valueText: ""
    property string contextText: ""
    property bool compact: false
    property bool chipFilled: false
    property real progress: -1
    property bool iconAboveLabel: false
    property bool clickable: false

    signal clicked()

    readonly property real chipSize: 32
    readonly property real maxTextWidth: 140

    implicitHeight: iconAboveLabel ? 44 : 38
    implicitWidth: {
        if (compact) {
            return chipSize + 8
        }
        if (iconAboveLabel) {
            return Math.max(chipSize, labelText.implicitWidth) + 12
        }
        return chipSize + 8 + textCol.implicitWidth + 12
    }

    Rectangle {
        id: hoverBg
        anchors.fill: parent
        radius: Styling.radius(-4)
        color: Colors.surfaceContainer
        opacity: (root.clickable && pillHover.hovered) ? 0.35 : 0
        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: 150 }
        }
    }

    HoverHandler {
        id: pillHover
        enabled: root.clickable
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.clickable
        onClicked: root.clicked()
    }

    // standard horizontal mode
    Row {
        id: standardRow
        visible: !root.iconAboveLabel && !root.compact
        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            id: standardChip
            width: root.chipSize
            height: root.chipSize
            radius: root.chipSize / 2
            color: root.chipFilled ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
            clip: true
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: standardArt
                anchors.fill: parent
                source: root.artworkUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready && source !== ""
            }

            Text {
                anchors.centerIn: parent
                visible: !standardArt.visible
                text: root.icon
                font.family: root.iconFont
                font.pixelSize: 16
                color: root.chipFilled ? Colors.surfaceContainerLowest : root.accentColor
            }
        }

        Column {
            id: textCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                id: valText
                text: root.valueText
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(3)
                font.weight: Font.Bold
                color: root.accentColor
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.maxTextWidth)
                visible: text !== ""
            }

            Text {
                id: ctxText
                text: root.contextText
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.outline
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.maxTextWidth)
                visible: text !== ""
            }

            Rectangle {
                id: progBar
                visible: root.progress >= 0
                width: Math.min(Math.max(valText.implicitWidth, ctxText.implicitWidth, 48), root.maxTextWidth)
                height: 2
                radius: 1
                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.progress))
                    height: parent.height
                    radius: 1
                    color: root.accentColor
                }
            }
        }
    }

    // compact icon-only mode
    Rectangle {
        id: compactChip
        visible: root.compact && !root.iconAboveLabel
        anchors.centerIn: parent
        width: root.chipSize
        height: root.chipSize
        radius: root.chipSize / 2
        color: root.chipFilled ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
        clip: true

        Image {
            id: compactArt
            anchors.fill: parent
            source: root.artworkUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready && source !== ""
        }

        Text {
            anchors.centerIn: parent
            visible: !compactArt.visible
            text: root.icon
            font.family: root.iconFont
            font.pixelSize: 16
            color: root.chipFilled ? Colors.surfaceContainerLowest : root.accentColor
        }
    }

    // vertical icon-above-label mode
    Column {
        id: verticalCol
        visible: root.iconAboveLabel
        anchors.centerIn: parent
        spacing: 2

        Rectangle {
            id: verticalChip
            width: root.chipSize
            height: root.chipSize
            radius: root.chipSize / 2
            color: root.chipFilled ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
            clip: true
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                anchors.centerIn: parent
                text: root.icon
                font.family: root.iconFont
                font.pixelSize: 16
                color: root.chipFilled ? Colors.surfaceContainerLowest : root.accentColor
            }
        }

        Text {
            id: labelText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.contextText !== "" ? root.contextText : root.valueText
            font.family: Styling.defaultFont
            font.pixelSize: Styling.fontSize(-3)
            color: Colors.outline
        }
    }
}
