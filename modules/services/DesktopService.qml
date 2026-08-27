pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string desktopDir: Quickshell.env("XDG_DESKTOP_DIR") || (Quickshell.env("HOME") + "/Desktop")
    property bool initialLoadComplete: false
    property string positionsFile: Quickshell.dataPath("desktop-positions.json")
    property int maxRowsHint: 15
    property int maxColumnsHint: 10
    property bool gridReady: false
    property bool positionsLoaded: false

    onMaxRowsHintChanged: checkGridReady()
    onMaxColumnsHintChanged: checkGridReady()
    onPositionsLoadedChanged: checkGridReady()

    function checkGridReady() {
        if (maxRowsHint > 0 && maxColumnsHint > 0 && positionsLoaded && !gridReady) {
            gridReady = true;
            console.log("Grid ready - rows:", maxRowsHint, "cols:", maxColumnsHint);
            if (tempItems.length > 0 || tempDesktopFiles.length > 0) {
                console.log("Finalizing items with", tempItems.length + tempDesktopFiles.length, "items");
                finalizeItems();
            }
        }
    }

    property ListModel items: ListModel {
        id: itemsModel
    }

    property var iconPositions: ({})

    function savePositions() {
        var json = JSON.stringify(iconPositions, null, 2);
        savePositionsProcess.command = ["sh", "-c", "echo '" + json.replace(/'/g, "'\\''") + "' > " + positionsFile];
        savePositionsProcess.running = true;
    }

    function loadPositions() {
        loadPositionsProcess.running = true;
    }

    function updateIconPosition(path, gridX, gridY) {
        iconPositions[path] = {
            x: gridX,
            y: gridY
        };
        savePositions();
    }

    function getIconPosition(path) {
        return iconPositions[path] || null;
    }

    function calculateAutoPosition(index) {
        var usedPositions = {};

        for (var key in iconPositions) {
            var pos = iconPositions[key];
            usedPositions[pos.x + "," + pos.y] = true;
        }

        var gridX = 0;
        var gridY = 0;
        var checked = 0;

        while (checked <= index) {
            var posKey = gridX + "," + gridY;
            if (!usedPositions[posKey]) {
                if (checked === index) {
                    return {
                        x: gridX,
                        y: gridY
                    };
                }
                checked++;
            }
            gridY++;
            if (gridY >= maxRowsHint) {
                gridY = 0;
                gridX++;
            }
        }

        return {
            x: gridX,
            y: gridY
        };
    }


    Connections {
        ignoreUnknownSignals: true
        enabled: DaemonClient != null
        target: DaemonClient
        function onDesktopReceived(itemsList) {
            tempItems = [];
            tempDesktopFiles = [];

            for (var i = 0; i < itemsList.length; i++) {
                var item = itemsList[i];
                if (item.is_desktop_file) {
                    tempDesktopFiles.push({
                        name: item.name,
                        path: item.path,
                        type: item.type,
                        icon: item.icon,
                        isDesktopFile: true,
                        sortOrder: 1
                    });
                } else {
                    tempDesktopFiles.push({
                        name: item.name,
                        path: item.path,
                        type: item.type,
                        icon: item.icon,
                        isDesktopFile: false,
                        sortOrder: item.sort_order
                    });
                }
            }

            if (gridReady && positionsLoaded) {
                finalizeItems();
            }
        }
    }

    function scanDesktop() {
        DaemonClient.sendCommand({ type: "get_desktop" });
    }

    function executeDesktopFile(filePath) {
        DaemonClient.sendCommand({
            type: "execute_desktop",
            path: filePath
        });
    }

    function openFile(filePath) {
        DaemonClient.sendCommand({
            type: "execute_desktop",
            path: filePath
        });
    }

    function trashFile(filePath) {
        DaemonClient.sendCommand({
            type: "trash_file",
            path: filePath
        });
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            loadPositions();
            scanDesktop();
        });
    }

    Process {
        id: savePositionsProcess
        running: false
        command: []

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error saving positions:", text);
                }
            }
        }
    }

    Process {
        id: loadPositionsProcess
        running: false
        command: ["cat", positionsFile]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(text);

                        for (var key in root.iconPositions) {
                            delete root.iconPositions[key];
                        }

                        for (var k in parsed) {
                            root.iconPositions[k] = {
                                x: parsed[k].x,
                                y: parsed[k].y
                            };
                        }

                        console.log("Loaded", Object.keys(root.iconPositions).length, "icon positions");
                    } catch (e) {
                        console.warn("Error parsing positions file:", e);
                    }
                }
                root.positionsLoaded = true;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                root.positionsLoaded = true;
            }
        }
    }
}
