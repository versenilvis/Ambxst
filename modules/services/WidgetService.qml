pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string positionsFile: Quickshell.dataPath("widget-positions.json")
    property var widgetPositions: ({})
    property bool positionsLoaded: false

    signal positionsReady()

    function getPosition(widgetId, defaultX, defaultY) {
        let entry = widgetPositions[widgetId];
        if (entry && typeof entry.x === "number" && typeof entry.y === "number") {
            return {
                x: entry.x,
                y: entry.y,
                locked: entry.locked === true
            };
        }
        return {
            x: defaultX !== undefined ? defaultX : 32,
            y: defaultY !== undefined ? defaultY : 32,
            locked: false
        };
    }

    function setPosition(widgetId, newX, newY, isLocked) {
        if (!widgetId) return;
        widgetPositions[widgetId] = {
            x: Math.round(newX),
            y: Math.round(newY),
            locked: isLocked === true
        };
        savePositions();
    }

    function toggleLocked(widgetId) {
        if (!widgetId) return;
        if (!widgetPositions[widgetId]) {
            widgetPositions[widgetId] = { x: 32, y: 32, locked: true };
        } else {
            widgetPositions[widgetId].locked = !widgetPositions[widgetId].locked;
        }
        savePositions();
    }

    function resetPosition(widgetId) {
        if (!widgetId) return;
        delete widgetPositions[widgetId];
        savePositions();
    }

    function savePositions() {
        let json = JSON.stringify(widgetPositions, null, 2);
        saveProcess.command = [
            "sh",
            "-c",
            "mkdir -p \"$(dirname '" + positionsFile + "')\" && echo '" + json.replace(/'/g, "'\\''") + "' > '" + positionsFile + "'"
        ];
        saveProcess.running = true;
    }

    function loadPositions() {
        loadProcess.running = true;
    }

    Process {
        id: saveProcess
        running: false
        command: []
    }

    Process {
        id: loadProcess
        running: false
        command: ["cat", positionsFile]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    try {
                        let parsed = JSON.parse(text);
                        root.widgetPositions = parsed || {};
                    } catch (e) {
                        console.warn("error parsing widget positions:", e);
                    }
                }
                root.positionsLoaded = true;
                root.positionsReady();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                root.positionsLoaded = true;
                root.positionsReady();
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(loadPositions);
    }
}
