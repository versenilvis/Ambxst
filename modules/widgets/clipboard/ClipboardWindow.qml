pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.config
import qs.modules.widgets.dashboard.clipboard

FloatingWindow {
    id: root

    visible: GlobalStates.clipboardVisible
    title: "Clipboard"
    color: "transparent"

    minimumSize: Qt.size(900, 650)
    maximumSize: Qt.size(900, 650)

    Shortcut {
        sequence: "Escape"
        onActivated: GlobalStates.clipboardVisible = false
    }

    onVisibleChanged: {
        if (visible) {
            clipboardTab.focusSearchInput();
        }
    }

    Process {
        id: openProcess
        running: false
    }

    function openItem(itemId, items, currentContent, getFilePathFromUri, isUrl) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === itemId) {
                var item = items[i];
                var content = currentContent || item.preview;

                if (item.isFile) {
                    var filePath = getFilePathFromUri(content);
                    if (filePath) {
                        openProcess.command = ["xdg-open", filePath];
                        openProcess.running = true;
                    }
                } else if (item.isImage && item.binaryPath) {
                    openProcess.command = ["xdg-open", item.binaryPath];
                    openProcess.running = true;
                } else if (isUrl(content)) {
                    openProcess.command = ["xdg-open", content.trim()];
                    openProcess.running = true;
                }
                break;
            }
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
                        text: "Clipboard"
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
                            GlobalStates.clipboardVisible = false;
                        }
                    }
                }
            }

            ClipboardTab {
                id: clipboardTab
                Layout.fillWidth: true
                Layout.fillHeight: true
                leftPanelWidth: 270  // matches DashboardView.qml's original notch-popup value

                onRequestOpenItem: (itemId, items, currentContent, filePathGetter, urlChecker) => {
                    root.openItem(itemId, items, currentContent, filePathGetter, urlChecker);
                }
            }
        }
    }
}
