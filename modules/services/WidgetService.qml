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
    property var selectedWidgetIds: []
    property var _groupMoveStart: ({})
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
            widgetPositions: widgetPositions || {},
            iconPositions: DesktopService.getPositionsSnapshot()
        }));
    }

    function pushGlobalUndoSnapshot() {
        _pushUndoSnapshot();
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
        if (prev.iconPositions) {
            DesktopService.restorePositionsSnapshot(prev.iconPositions);
        }
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
        if (next.iconPositions) {
            DesktopService.restorePositionsSnapshot(next.iconPositions);
        }
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

    function isWidgetSelected(widgetId) {
        return selectedWidgetIds.indexOf(widgetId) !== -1;
    }

    function clearSelection() {
        if (selectedWidgetIds.length > 0) {
            selectedWidgetIds = [];
        }
    }

    function selectWidgetsInRect(rx, ry, rw, rh, additive, baseSelection) {
        let next = additive && baseSelection ? baseSelection.slice() : [];
        for (let id in registeredWidgets) {
            const item = registeredWidgets[id];
            if (!item || !item.visible) continue;
            const intersects = item.x < (rx + rw) && (item.x + item.width) > rx &&
                               item.y < (ry + rh) && (item.y + item.height) > ry;
            if (intersects && next.indexOf(id) === -1) {
                next.push(id);
            }
        }
        selectedWidgetIds = next;
    }

    function beginGroupMove() {
        let starts = {};
        for (let i = 0; i < selectedWidgetIds.length; i++) {
            const id = selectedWidgetIds[i];
            const item = registeredWidgets[id];
            if (!item || item.locked) continue;
            starts[id] = {
                x: item.x,
                y: item.y,
                w: item.width,
                h: item.height,
                parentW: item.parent ? item.parent.width : 1920,
                parentH: item.parent ? item.parent.height : 1080
            };
        }
        _groupMoveStart = starts;
    }

    function moveGroupBy(dx, dy) {
        let minDx = -1e9;
        let maxDx = 1e9;
        let minDy = -1e9;
        let maxDy = 1e9;

        for (let id in _groupMoveStart) {
            const s = _groupMoveStart[id];
            minDx = Math.max(minDx, -s.x);
            maxDx = Math.min(maxDx, Math.max(0, s.parentW - s.w) - s.x);
            minDy = Math.max(minDy, -s.y);
            maxDy = Math.min(maxDy, Math.max(0, s.parentH - s.h) - s.y);
        }

        const clampedDx = Math.max(minDx, Math.min(maxDx, dx));
        const clampedDy = Math.max(minDy, Math.min(maxDy, dy));

        for (let id in _groupMoveStart) {
            const s = _groupMoveStart[id];
            const item = registeredWidgets[id];
            if (!item) continue;
            item._groupMoving = true;
            item.x = Math.round(s.x + clampedDx);
            item.y = Math.round(s.y + clampedDy);
            item.savedX = item.x;
            item.savedY = item.y;
            item._groupMoving = false;
        }
    }

    function commitGroupMove() {
        let hasChanges = false;
        for (let id in _groupMoveStart) {
            const s = _groupMoveStart[id];
            const item = registeredWidgets[id];
            if (item && (item.x !== s.x || item.y !== s.y)) {
                hasChanges = true;
                break;
            }
        }
        if (!hasChanges) {
            _groupMoveStart = {};
            return;
        }

        _pushUndoSnapshot();
        let photoChanged = false;
        let posChanged = false;

        for (let id in _groupMoveStart) {
            const item = registeredWidgets[id];
            if (!item) continue;
            item.savedX = item.x;
            item.savedY = item.y;

            let isPhoto = false;
            for (let i = 0; i < (photoWidgets || []).length; i++) {
                if (photoWidgets[i].id === id) {
                    photoWidgets[i].x = Math.round(item.x);
                    photoWidgets[i].y = Math.round(item.y);
                    isPhoto = true;
                    photoChanged = true;
                    break;
                }
            }
            if (!isPhoto) {
                widgetPositions[id] = {
                    x: Math.round(item.x),
                    y: Math.round(item.y),
                    locked: item.locked === true
                };
                posChanged = true;
            }
        }

        if (photoChanged) savePhotoWidgets();
        if (posChanged) savePositions();
        _groupMoveStart = {};
    }

    function _getOtherBounds(excludeId, includeIcons, cellWidth, cellHeight) {
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
        if (includeIcons && DesktopService && DesktopService.items) {
            const cw = cellWidth || 96;
            const ch = cellHeight || 120;
            for (let i = 0; i < DesktopService.items.count; i++) {
                const entry = DesktopService.items.get(i);
                if (!entry || entry.path === excludeId) continue;
                const ix = entry.posX >= 0 ? entry.posX : (entry.col * cw);
                const iy = entry.posY >= 0 ? entry.posY : (entry.row * ch);
                list.push({
                    x: ix,
                    y: iy,
                    w: cw,
                    h: ch
                });
            }
        }
        return list;
    }

    // snap one axis against edge/center alignment and equal-spacing gaps
    function _snapAxis(rawStart, mySize, myPerpStart, myPerpSize, boxes, threshold) {
        let bestDiff = null;
        const myEdges = [0, mySize / 2, mySize];
        const myPerpEnd = myPerpStart + myPerpSize;

        // 1. edge and center alignment
        for (let i = 0; i < boxes.length; i++) {
            const b = boxes[i];
            const bEdges = [b.start, b.start + b.size / 2, b.start + b.size];
            for (let a = 0; a < myEdges.length; a++) {
                const myVal = rawStart + myEdges[a];
                for (let k = 0; k < bEdges.length; k++) {
                    const diff = bEdges[k] - myVal;
                    if (Math.abs(diff) <= threshold && (bestDiff === null || Math.abs(diff) < Math.abs(bestDiff))) {
                        bestDiff = diff;
                    }
                }
            }
        }

        // 2. collect existing gaps between nearby items in the same band, fallback to 16px
        let gaps = [];
        let seenGap = {};
        for (let i = 0; i < boxes.length; i++) {
            const a = boxes[i];
            const aPerpEnd = a.perpStart + a.perpSize;
            for (let j = i + 1; j < boxes.length; j++) {
                const b = boxes[j];
                const bPerpEnd = b.perpStart + b.perpSize;
                if (Math.min(aPerpEnd, bPerpEnd) <= Math.max(a.perpStart, b.perpStart)) continue;
                const g1 = b.start - (a.start + a.size);
                const g2 = a.start - (b.start + b.size);
                const g = g1 > 0 ? g1 : (g2 > 0 ? g2 : -1);
                if (g > 2 && g <= 120) {
                    const rg = Math.round(g);
                    if (!seenGap[rg]) {
                        seenGap[rg] = true;
                        gaps.push(rg);
                    }
                }
            }
        }
        if (!seenGap[16]) gaps.push(16);

        // 3. snap to equal gap with overlapping-band neighbors
        for (let i = 0; i < boxes.length; i++) {
            const b = boxes[i];
            const bPerpEnd = b.perpStart + b.perpSize;
            if (Math.min(myPerpEnd, bPerpEnd) <= Math.max(myPerpStart, b.perpStart)) continue;
            for (let g = 0; g < gaps.length; g++) {
                const gap = gaps[g];
                const afterDiff = (b.start + b.size + gap) - rawStart;
                if (Math.abs(afterDiff) <= threshold && (bestDiff === null || Math.abs(afterDiff) < Math.abs(bestDiff))) {
                    bestDiff = afterDiff;
                }
                const beforeDiff = (b.start - mySize - gap) - rawStart;
                if (Math.abs(beforeDiff) <= threshold && (bestDiff === null || Math.abs(beforeDiff) < Math.abs(bestDiff))) {
                    bestDiff = beforeDiff;
                }
            }
        }

        return bestDiff !== null ? (rawStart + bestDiff) : rawStart;
    }

    function computeSnapForMove(widgetId, rawX, rawY, w, h, threshold, includeIcons, cellWidth, cellHeight, excludeIds) {
        const thresh = threshold !== undefined ? threshold : 10;
        let others = _getOtherBounds(widgetId, includeIcons === true, cellWidth, cellHeight);
        if (excludeIds && excludeIds.length > 0) {
            let exSet = {};
            for (let i = 0; i < excludeIds.length; i++) exSet[excludeIds[i]] = true;
            others = _getOtherBoundsFiltered(exSet, includeIcons === true, cellWidth, cellHeight);
        }
        const xBoxes = others.map(o => ({ start: o.x, size: o.w, perpStart: o.y, perpSize: o.h }));
        const yBoxes = others.map(o => ({ start: o.y, size: o.h, perpStart: o.x, perpSize: o.w }));
        return {
            x: _snapAxis(rawX, w, rawY, h, xBoxes, thresh),
            y: _snapAxis(rawY, h, rawX, w, yBoxes, thresh)
        };
    }

    function _getOtherBoundsFiltered(excludeSet, includeIcons, cellWidth, cellHeight) {
        let list = [];
        for (let id in registeredWidgets) {
            if (excludeSet[id]) continue;
            let item = registeredWidgets[id];
            if (!item || !item.visible) continue;
            list.push({ x: item.x, y: item.y, w: item.width, h: item.height });
        }
        if (includeIcons && DesktopService && DesktopService.items) {
            const cw = cellWidth || 96;
            const ch = cellHeight || 120;
            for (let i = 0; i < DesktopService.items.count; i++) {
                const entry = DesktopService.items.get(i);
                if (!entry || excludeSet[entry.path]) continue;
                const ix = entry.posX >= 0 ? entry.posX : (entry.col * cw);
                const iy = entry.posY >= 0 ? entry.posY : (entry.row * ch);
                list.push({ x: ix, y: iy, w: cw, h: ch });
            }
        }
        return list;
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
