import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config

Rectangle {
    id: root
    color: "transparent"

    property bool showSearch: true
    property string searchText: ""

    function focusSearchInput() {
        if (root.showSearch) {
            searchInput.focusInput();
        } else {
            resultsList.forceActiveFocus();
        }
    }

    function selectNext() {
        if (resultsList.count > 0) {
            resultsList.currentIndex = Math.min(resultsList.currentIndex + 1, resultsList.count - 1);
        }
    }

    function selectPrevious() {
        if (resultsList.count > 0) {
            resultsList.currentIndex = Math.max(resultsList.currentIndex - 1, 0);
        }
    }

    function activateCurrent() {
        if (resultsList.currentIndex >= 0 && resultsList.currentIndex < resultsList.count) {
            const item = FileSearch.searchResults[resultsList.currentIndex];
            if (item && item.path) {
                root.openFile(item.path);
            }
        }
    }

    Process {
        id: openProcess
        running: false
    }

    function openFile(path) {
        if (!path || path.length === 0)
            return;
        openProcess.command = ["xdg-open", path];
        openProcess.running = true;
        GlobalStates.commandPaletteVisible = false;
    }

    onSearchTextChanged: {
        resultsList.currentIndex = 0;
        FileSearch.searchFiles(root.searchText);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        SearchInput {
            id: searchInput
            Layout.fillWidth: true
            height: root.showSearch ? implicitHeight : 0
            visible: root.showSearch
            text: root.searchText
            placeholderText: "Search files…"

            onSearchTextChanged: text => {
                root.searchText = text;
            }
            onAccepted: root.activateCurrent()
            onDownPressed: root.selectNext()
            onUpPressed: root.selectPrevious()
            onEscapePressed: GlobalStates.commandPaletteVisible = false
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: resultsList
                anchors.fill: parent
                clip: true
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                model: FileSearch.searchResults

                currentIndex: FileSearch.searchResults.length > 0 ? 0 : -1

                onCurrentIndexChanged: {
                    if (currentIndex >= 0) {
                        resultsList.positionViewAtIndex(currentIndex, ListView.Contain);
                    }
                }

                Keys.onReturnPressed: root.activateCurrent()
                Keys.onEnterPressed: root.activateCurrent()
                Keys.onDownPressed: root.selectNext()
                Keys.onUpPressed: root.selectPrevious()

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property bool isCurrent: resultsList.currentIndex === row.index

                    width: resultsList.width
                    height: 48
                    color: row.isCurrent ? Colors.surfaceContainer : "transparent"
                    radius: Styling.radius(-4)

                    Behavior on color {
                        enabled: Config.animDuration > 0
                        ColorAnimation {
                            duration: Config.animDuration / 3
                            easing.type: Easing.OutQuart
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: resultsList.currentIndex = row.index
                        onClicked: root.openFile(row.modelData.path)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Text {
                            text: Icons.file
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: row.isCurrent ? Colors.primary : Colors.outline
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                color: Colors.overBackground
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(0)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.dir
                                color: Colors.outline
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-2)
                                elide: Text.ElideLeft
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: resultsList.count === 0 && root.searchText.length > 0
                text: "No files found"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(0)
                color: Colors.outline
            }

            Text {
                anchors.centerIn: parent
                visible: resultsList.count === 0 && root.searchText.length === 0
                text: "Type to search files…"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(0)
                color: Colors.outline
            }
        }
    }
}
