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

    property string photoWidgetsFile: Quickshell.dataPath("photo-widgets.json")
    property var photoWidgets: []
    property bool photoWidgetsLoaded: false
    property string _pendingPhotoAction: ""
    property string _pendingPhotoId: ""
    property int _pendingPhotoX: 32
    property int _pendingPhotoY: 300

    property var registeredWidgets: ({})
    property var _undoStack: []
    property var _redoStack: []

    signal positionsReady()
    signal photoWidgetsReady()
    signal photoWidgetUpdated(string widgetId)
    signal photoWidgetsRestored()

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

    function _cloneState() {
        return JSON.parse(JSON.stringify({
            photoWidgets: photoWidgets || [],
            widgetPositions: widgetPositions || {}
        }));
    }

    function _pushUndoSnapshot() {
        _undoStack.push(_cloneState());
        if (_undoStack.length > 50) {
            _undoStack.shift();
        }
        _redoStack = [];
    }

    function undo() {
        if (_undoStack.length === 0) return false;
        _redoStack.push(_cloneState());
        const prev = _undoStack.pop();
        widgetPositions = prev.widgetPositions || {};
        photoWidgets = prev.photoWidgets || [];
        savePositions();
        savePhotoWidgets();
        positionsReady();
        photoWidgetsRestored();
        return true;
    }

    function redo() {
        if (_redoStack.length === 0) return false;
        _undoStack.push(_cloneState());
        const next = _redoStack.pop();
        widgetPositions = next.widgetPositions || {};
        photoWidgets = next.photoWidgets || [];
        savePositions();
        savePhotoWidgets();
        positionsReady();
        photoWidgetsRestored();
        return true;
    }

    function setPosition(widgetId, newX, newY, isLocked) {
        if (!widgetId) return;
        _pushUndoSnapshot();
        widgetPositions[widgetId] = {
            x: Math.round(newX),
            y: Math.round(newY),
            locked: isLocked === true
        };
        savePositions();
    }

    function toggleLocked(widgetId) {
        if (!widgetId) return;
        _pushUndoSnapshot();
        if (!widgetPositions[widgetId]) {
            widgetPositions[widgetId] = { x: 32, y: 32, locked: true };
        } else {
            widgetPositions[widgetId].locked = !widgetPositions[widgetId].locked;
        }
        savePositions();
    }

    function resetPosition(widgetId) {
        if (!widgetId) return;
        _pushUndoSnapshot();
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

    function registerWidget(widgetId, item) {
        if (!widgetId || !item) return;
        registeredWidgets[widgetId] = item;
    }

    function unregisterWidget(widgetId) {
        if (!widgetId) return;
        delete registeredWidgets[widgetId];
    }

    function _getOtherBounds(excludeId) {
        let list = [];
        for (let id in registeredWidgets) {
            if (id === excludeId) continue;
            let item = registeredWidgets[id];
            if (!item || !item.visible) continue;
            list.push({
                x: item.x,
                y: item.y,
                w: item.width,
                h: item.height
            });
        }
        return list;
    }

    function computeSnapForMove(widgetId, rawX, rawY, w, h, threshold) {
        const thresh = threshold !== undefined ? threshold : 6;
        const others = _getOtherBounds(widgetId);
        let bestDx = null;
        let bestDy = null;
        let guideX = null;
        let guideY = null;

        const xEdges = [0, w / 2, w];
        const yEdges = [0, h / 2, h];

        for (let i = 0; i < others.length; i++) {
            const o = others[i];
            const oxEdges = [o.x, o.x + o.w / 2, o.x + o.w];
            const oyEdges = [o.y, o.y + o.h / 2, o.y + o.h];

            for (let a = 0; a < xEdges.length; a++) {
                const myVal = rawX + xEdges[a];
                for (let b = 0; b < oxEdges.length; b++) {
                    const diff = oxEdges[b] - myVal;
                    if (Math.abs(diff) <= thresh && (bestDx === null || Math.abs(diff) < Math.abs(bestDx))) {
                        bestDx = diff;
                        guideX = {
                            orientation: "v",
                            pos: oxEdges[b],
                            start: Math.min(rawY, o.y),
                            end: Math.max(rawY + h, o.y + o.h)
                        };
                    }
                }
            }

            for (let a = 0; a < yEdges.length; a++) {
                const myVal = rawY + yEdges[a];
                for (let b = 0; b < oyEdges.length; b++) {
                    const diff = oyEdges[b] - myVal;
                    if (Math.abs(diff) <= thresh && (bestDy === null || Math.abs(diff) < Math.abs(bestDy))) {
                        bestDy = diff;
                        guideY = {
                            orientation: "h",
                            pos: oyEdges[b],
                            start: Math.min(rawX, o.x),
                            end: Math.max(rawX + w, o.x + o.w)
                        };
                    }
                }
            }
        }

        const snappedX = bestDx !== null ? (rawX + bestDx) : rawX;
        const snappedY = bestDy !== null ? (rawY + bestDy) : rawY;
        return { x: snappedX, y: snappedY };
    }

    function computeSnapForResize(widgetId, x, y, w, h, resizeLeft, resizeRight, resizeTop, resizeBottom, threshold) {
        const thresh = threshold !== undefined ? threshold : 6;
        const others = _getOtherBounds(widgetId);
        let bestDx = null;
        let bestDy = null;
        let guideX = null;
        let guideY = null;

        const targetX = resizeRight ? (x + w) : (resizeLeft ? x : null);
        const targetY = resizeBottom ? (y + h) : (resizeTop ? y : null);

        for (let i = 0; i < others.length; i++) {
            const o = others[i];
            if (targetX !== null) {
                const oxEdges = [o.x, o.x + o.w / 2, o.x + o.w];
                for (let b = 0; b < oxEdges.length; b++) {
                    const diff = oxEdges[b] - targetX;
                    if (Math.abs(diff) <= thresh && (bestDx === null || Math.abs(diff) < Math.abs(bestDx))) {
                        bestDx = diff;
                        guideX = {
                            orientation: "v",
                            pos: oxEdges[b],
                            start: Math.min(y, o.y),
                            end: Math.max(y + h, o.y + o.h)
                        };
                    }
                }
            }
            if (targetY !== null) {
                const oyEdges = [o.y, o.y + o.h / 2, o.y + o.h];
                for (let b = 0; b < oyEdges.length; b++) {
                    const diff = oyEdges[b] - targetY;
                    if (Math.abs(diff) <= thresh && (bestDy === null || Math.abs(diff) < Math.abs(bestDy))) {
                        bestDy = diff;
                        guideY = {
                            orientation: "h",
                            pos: oyEdges[b],
                            start: Math.min(x, o.x),
                            end: Math.max(x + w, o.x + o.w)
                        };
                    }
                }
            }
        }

        let nextX = x;
        let nextY = y;
        let nextW = w;
        let nextH = h;

        if (bestDx !== null) {
            if (resizeRight) {
                nextW = w + bestDx;
            } else if (resizeLeft) {
                nextX = x + bestDx;
                nextW = w - bestDx;
            }
        }
        if (bestDy !== null) {
            if (resizeBottom) {
                nextH = h + bestDy;
            } else if (resizeTop) {
                nextY = y + bestDy;
                nextH = h - bestDy;
            }
        }

        return { x: nextX, y: nextY, width: nextW, height: nextH };
    }

    function addPhotoWidget(imagePath, x, y, width, height) {
        if (!imagePath) return null;
        _pushUndoSnapshot();
        let entry = {
            id: "photo_" + Date.now() + "_" + Math.floor(Math.random() * 1000),
            imagePath: imagePath,
            x: Math.round(x !== undefined ? x : 32),
            y: Math.round(y !== undefined ? y : 300),
            width: Math.round(width !== undefined ? width : 240),
            height: Math.round(height !== undefined ? height : 240),
            locked: false,
            cornerRadius: 20
        };
        let next = (photoWidgets || []).slice();
        next.push(entry);
        photoWidgets = next;
        savePhotoWidgets();
        return entry;
    }

    function updatePhotoWidget(widgetId, props) {
        if (!widgetId || !photoWidgets) return;
        for (let i = 0; i < photoWidgets.length; i++) {
            if (photoWidgets[i].id === widgetId) {
                _pushUndoSnapshot();
                if (props.x !== undefined) photoWidgets[i].x = Math.round(props.x);
                if (props.y !== undefined) photoWidgets[i].y = Math.round(props.y);
                if (props.width !== undefined) photoWidgets[i].width = Math.round(props.width);
                if (props.height !== undefined) photoWidgets[i].height = Math.round(props.height);
                if (props.locked !== undefined) photoWidgets[i].locked = props.locked === true;
                if (props.lockAspectRatio !== undefined) photoWidgets[i].lockAspectRatio = props.lockAspectRatio === true;
                if (props.imagePath !== undefined) photoWidgets[i].imagePath = props.imagePath;
                if (props.cornerRadius !== undefined) photoWidgets[i].cornerRadius = props.cornerRadius;
                savePhotoWidgets();
                photoWidgetUpdated(widgetId);
                return;
            }
        }
    }

    function removePhotoWidget(widgetId) {
        if (!widgetId || !photoWidgets) return;
        _pushUndoSnapshot();
        photoWidgets = photoWidgets.filter(w => w.id !== widgetId);
        savePhotoWidgets();
    }

    function browseAndAddPhotoWidget(x, y) {
        _pendingPhotoAction = "add";
        _pendingPhotoId = "";
        _pendingPhotoX = x !== undefined ? Math.round(x) : 32;
        _pendingPhotoY = y !== undefined ? Math.round(y) : 300;
        photoPickerProcess.running = true;
    }

    function browseAndChangePhotoImage(widgetId) {
        if (!widgetId) return;
        _pendingPhotoAction = "change";
        _pendingPhotoId = widgetId;
        photoPickerProcess.running = true;
    }

    function savePhotoWidgets() {
        let json = JSON.stringify(photoWidgets || [], null, 2);
        savePhotoProcess.command = [
            "sh",
            "-c",
            "mkdir -p \"$(dirname '" + photoWidgetsFile + "')\" && echo '" + json.replace(/'/g, "'\\''") + "' > '" + photoWidgetsFile + "'"
        ];
        savePhotoProcess.running = true;
    }

    function loadPhotoWidgets() {
        loadPhotoProcess.running = true;
    }

    Process {
        id: savePhotoProcess
        running: false
        command: []
    }

    Process {
        id: loadPhotoProcess
        running: false
        command: ["cat", photoWidgetsFile]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    try {
                        let parsed = JSON.parse(text);
                        root.photoWidgets = Array.isArray(parsed) ? parsed : [];
                    } catch (e) {
                        console.warn("error parsing photo widgets:", e);
                    }
                }
                root.photoWidgetsLoaded = true;
                root.photoWidgetsReady();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                root.photoWidgetsLoaded = true;
                root.photoWidgetsReady();
            }
        }
    }

    Process {
        id: photoPickerProcess
        running: false
        command: [
            "zenity",
            "--file-selection",
            "--filename=" + (Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")) + "/",
            "--title=Select Photo for Widget",
            "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.svg"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                let selectedPath = text.trim();
                if (selectedPath.length > 0) {
                    if (root._pendingPhotoAction === "add") {
                        root.addPhotoWidget(selectedPath, root._pendingPhotoX, root._pendingPhotoY, 240, 240);
                    } else if (root._pendingPhotoAction === "change" && root._pendingPhotoId) {
                        root.updatePhotoWidget(root._pendingPhotoId, { imagePath: selectedPath });
                    }
                }
                root._pendingPhotoAction = "";
                root._pendingPhotoId = "";
            }
        }
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
        Qt.callLater(loadPhotoWidgets);
    }
}
