pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.config
import qs.modules.widgets.dashboard.emoji

FloatingWindow {
    id: root

    visible: GlobalStates.emojiVisible
    title: "Emoji"
    color: "transparent"

    minimumSize: Qt.size(900, 650)
    maximumSize: Qt.size(900, 650)

    Shortcut {
        sequence: "Escape"
        onActivated: GlobalStates.emojiVisible = false
    }

    onVisibleChanged: {
        if (visible) {
            emojiTab.focusSearchInput();
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: Colors.surfaceContainerLowest
        radius: Styling.radius(0)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            // title bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                color: Colors.surfaceContainer
                radius: Styling.radius(-1)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: "Emoji"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0) + 2
                        font.bold: true
                        color: Styling.srItem("overprimary")
                        Layout.fillWidth: true
                    }

                    Button {
                        id: titleCloseButton
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32

                        background: Rectangle {
                            color: titleCloseButton.hovered ? Colors.overErrorContainer : Colors.error
                            radius: Styling.radius(-4)
                        }

                        contentItem: Text {
                            text: Icons.cancel
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: titleCloseButton.hovered ? Colors.error : Colors.overError
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            GlobalStates.emojiVisible = false;
                        }
                    }
                }
            }

            EmojiTab {
                id: emojiTab
                Layout.fillWidth: true
                Layout.fillHeight: true
                leftPanelWidth: 270  // matches DashboardView.qml's original notch-popup value
            }
        }
    }
}
