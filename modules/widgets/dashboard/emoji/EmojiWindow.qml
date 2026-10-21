pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.widgets.dashboard.emoji
import qs.config

PanelWindow {
    id: root

    screen: {
        const focused = Hyprland.focusedMonitor;
        if (focused && Quickshell.screens) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === focused.name)
                    return Quickshell.screens[i];
            }
        }
        return Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: GlobalStates.emojiVisible

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    mask: Region {
        item: GlobalStates.emojiVisible ? fullMask : emptyMask
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        active: root.visible

        onCleared: {
            Qt.callLater(() => {
                if (root.visible) {
                    GlobalStates.emojiVisible = false;
                }
            });
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: GlobalStates.emojiVisible = false
    }

    Component.onCompleted: {
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(() => searchField.forceActiveFocus());
        } else {
            searchField.text = "";
        }
    }

    // Dismiss when clicking outside modal
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: GlobalStates.emojiVisible = false
        }
    }

    // Centered modal card with clean rounded corners
    ClippingRectangle {
        id: container
        anchors.centerIn: parent
        width: 680
        height: 560
        color: Colors.background
        radius: Styling.radius(0)
        border.width: 1
        border.color: Colors.surfaceContainer

        // Prevent click in modal from propagating to backdrop
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Search bar in exact CommandPalette style
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 16
                Layout.bottomMargin: 8
                spacing: 12

                Text {
                    text: Icons.emoji
                    font.family: Icons.font
                    font.pixelSize: 21
                    color: Colors.outline
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Colors.overBackground
                    placeholderTextColor: Colors.outline
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(8)
                    placeholderText: "Search emoji…"
                    text: ""

                    onTextChanged: emojiTab.searchText = text

                    Keys.onEscapePressed: {
                        if (text.length > 0) {
                            text = "";
                        } else {
                            GlobalStates.emojiVisible = false;
                        }
                    }

                    Keys.onUpPressed: event => {
                        emojiTab.navUp();
                        event.accepted = true;
                    }

                    Keys.onDownPressed: event => {
                        emojiTab.navDown();
                        event.accepted = true;
                    }

                    Keys.onLeftPressed: event => {
                        emojiTab.navLeft();
                        event.accepted = true;
                    }

                    Keys.onRightPressed: event => {
                        emojiTab.navRight();
                        event.accepted = true;
                    }

                    onAccepted: {
                        emojiTab.navAccept();
                    }
                }

                // Esc badge in exact CommandPalette style
                Rectangle {
                    implicitWidth: escLabel.implicitWidth + 14
                    implicitHeight: 22
                    radius: Styling.radius(-10)
                    color: "transparent"
                    border.width: 1
                    border.color: Colors.surfaceContainer

                    Text {
                        id: escLabel
                        anchors.centerIn: parent
                        text: "esc"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outlineVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.emojiVisible = false
                    }
                }
            }

            // Divider line
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Colors.surfaceContainer
            }

            // Central content: EmojiTab
            EmojiTab {
                id: emojiTab
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                showSearch: false
            }

            // Footer bar in exact CommandPalette style
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                color: Colors.surfaceContainerLowest

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Colors.surfaceContainer
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Currently active emoji preview + name + shortcode
                    Row {
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter
                        visible: emojiTab.currentSelectedEmoji != null

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: emojiTab.currentSelectedEmoji ? emojiTab.currentSelectedEmoji.emoji : ""
                            font.pixelSize: 18
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: emojiTab.currentSelectedEmoji ? emojiTab.currentSelectedEmoji.name : ""
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.DemiBold
                            color: Colors.overBackground
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: emojiTab.currentSelectedEmoji ? `(:${emojiTab.currentSelectedEmoji.slug}:)` : ""
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.outline
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Keyboard hints
                    Row {
                        spacing: 12
                        Layout.alignment: Qt.AlignVCenter

                        Row {
                            spacing: 4
                            Rectangle {
                                width: key1.implicitWidth + 8
                                height: 18
                                radius: Styling.radius(-12)
                                color: Colors.surfaceContainer
                                Text {
                                    id: key1
                                    anchors.centerIn: parent
                                    text: "↵"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: Colors.outline
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "copy & type"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outlineVariant
                            }
                        }

                        Row {
                            spacing: 4
                            Rectangle {
                                width: key2.implicitWidth + 8
                                height: 18
                                radius: Styling.radius(-12)
                                color: Colors.surfaceContainer
                                Text {
                                    id: key2
                                    anchors.centerIn: parent
                                    text: "↑↓←→"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: Colors.outline
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "navigate"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outlineVariant
                            }
                        }

                        Row {
                            spacing: 4
                            Rectangle {
                                width: key3.implicitWidth + 8
                                height: 18
                                radius: Styling.radius(-12)
                                color: Colors.surfaceContainer
                                Text {
                                    id: key3
                                    anchors.centerIn: parent
                                    text: "esc"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: Colors.outline
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "close"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outlineVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
