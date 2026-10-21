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
    property int maxRows: 12
    property int maxColumns: 16
    property bool gridReady: false
    property bool positionsLoaded: false

    property var iconPositions: ({})
    property var rawItems: []

    property ListModel items: ListModel {
        id: itemsModel
    }

    onMaxRowsChanged: checkGridReady()
    onMaxColumnsChanged: checkGridReady()
    onPositionsLoadedChanged: checkGridReady()

    function checkGridReady() {
        if (maxRows > 0 && maxColumns > 0 && positionsLoaded && !gridReady) {
            gridReady = true;
            if (rawItems.length > 0) {
                finalizeItems();
            }
        }
    }

    Connections {
        ignoreUnknownSignals: true
        enabled: DaemonClient != null
        target: DaemonClient
        function onDesktopReceived(itemsList) {
            root.rawItems = itemsList || [];
            if (root.gridReady && root.positionsLoaded) {
                root.finalizeItems();
            }
        }
    }

    function finalizeItems() {
        if (!rawItems || rawItems.length === 0) {
            items.clear();
            initialLoadComplete = true;
            return;
        }

        let occupied = {};
        let processed = [];
        let validPaths = {};

        for (let i = 0; i < rawItems.length; i++) {
            validPaths[rawItems[i].path] = true;
        }

        // clean up stale entries from deleted files
        for (let p in iconPositions) {
            if (!validPaths[p]) {
                delete iconPositions[p];
            }
        }

        // first pass: place items that already have valid saved positions
        for (let i = 0; i < rawItems.length; i++) {
            let item = rawItems[i];
            let saved = iconPositions[item.path];
            let col = -1;
            let row = -1;

            if (saved && typeof saved.col === "number" && typeof saved.row === "number") {
                if (saved.col >= 0 && saved.col < maxColumns && saved.row >= 0 && saved.row < maxRows) {
                    let key = saved.col + "," + saved.row;
                    if (!occupied[key]) {
                        col = saved.col;
                        row = saved.row;
                        occupied[key] = true;
                    }
                }
            }

            processed.push({
                name: item.name || "",
                path: item.path || "",
                type: item.type || "file",
                icon: item.icon || "file",
                isDesktopFile: item.is_desktop_file === true,
                sortOrder: typeof item.sort_order === "number" ? item.sort_order : 2,
                col: col,
                row: row
            });
        }

        // second pass: place remaining items into first vacant slot from right to left
        let hasNewPositions = false;
        for (let i = 0; i < processed.length; i++) {
            if (processed[i].col === -1) {
                let slot = findNextVacantSlot(occupied);
                processed[i].col = slot.col;
                processed[i].row = slot.row;
                occupied[slot.col + "," + slot.row] = true;
                iconPositions[processed[i].path] = { col: slot.col, row: slot.row };
                hasNewPositions = true;
            }
        }

        items.clear();
        for (let i = 0; i < processed.length; i++) {
            items.append(processed[i]);
        }

        initialLoadComplete = true;
        if (hasNewPositions) {
            savePositions();
        }
    }

    function findNextVacantSlot(occupied) {
        // macOS default fills from top-right downwards
        for (let c = maxColumns - 1; c >= 0; c--) {
            for (let r = 0; r < maxRows; r++) {
                let key = c + "," + r;
                if (!occupied[key]) {
                    return { col: c, row: r };
                }
            }
        }
        return { col: 0, row: 0 };
    }

    function updatePosition(path, targetCol, targetRow) {
        targetCol = Math.max(0, Math.min(targetCol, maxColumns - 1));
        targetRow = Math.max(0, Math.min(targetRow, maxRows - 1));

        let sourceIndex = -1;
        let swapIndex = -1;

        for (let i = 0; i < items.count; i++) {
            let entry = items.get(i);
            if (entry.path === path) {
                sourceIndex = i;
            } else if (entry.col === targetCol && entry.row === targetRow) {
                swapIndex = i;
            }
        }

        if (sourceIndex === -1) return;

        let sourceItem = items.get(sourceIndex);
        let oldCol = sourceItem.col;
        let oldRow = sourceItem.row;

        if (swapIndex !== -1) {
            let swapItem = items.get(swapIndex);
            items.setProperty(swapIndex, "col", oldCol);
            items.setProperty(swapIndex, "row", oldRow);
            iconPositions[swapItem.path] = { col: oldCol, row: oldRow };
        }

        items.setProperty(sourceIndex, "col", targetCol);
        items.setProperty(sourceIndex, "row", targetRow);
        iconPositions[path] = { col: targetCol, row: targetRow };

        savePositions();
    }

    function sortItems(byKind) {
        let list = [];
        for (let i = 0; i < items.count; i++) {
            list.push(items.get(i));
        }

        list.sort((a, b) => {
            if (byKind && a.sortOrder !== b.sortOrder) {
                return a.sortOrder - b.sortOrder;
            }
            return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
        });

        for (let i = 0; i < list.length; i++) {
            let col = Math.max(0, maxColumns - 1 - Math.floor(i / maxRows));
            let row = i % maxRows;
            for (let j = 0; j < items.count; j++) {
                if (items.get(j).path === list[i].path) {
                    items.setProperty(j, "col", col);
                    items.setProperty(j, "row", row);
                    iconPositions[list[i].path] = { col: col, row: row };
                    break;
                }
            }
        }

        savePositions();
    }

    function savePositions() {
        let json = JSON.stringify(iconPositions, null, 2);
        savePositionsProcess.command = [
            "sh",
            "-c",
            "mkdir -p \"$(dirname '" + positionsFile + "')\" && echo '" + json.replace(/'/g, "'\\''") + "' > '" + positionsFile + "'"
        ];
        savePositionsProcess.running = true;
    }

    function loadPositions() {
        loadPositionsProcess.running = true;
    }

    function scanDesktop() {
        DaemonClient.sendCommand({ type: "get_desktop" });
    }

    function executeDesktopFile(filePath) {
        if (!filePath) return;
        executeCommand("/home/verse/Ambxst/scripts/open-file.sh '" + filePath.replace(/'/g, "'\\''") + "'");
    }

    function openFile(filePath) {
        if (!filePath) return;
        executeCommand("/home/verse/Ambxst/scripts/open-file.sh '" + filePath.replace(/'/g, "'\\''") + "'");
    }

    function trashFile(filePath) {
        DaemonClient.sendCommand({
            type: "trash_file",
            path: filePath
        });
    }

    function hasItemNamed(name) {
        let lower = name.toLowerCase();
        for (let i = 0; i < items.count; i++) {
            let it = items.get(i);
            if (it && it.name && it.name.toLowerCase() === lower) {
                return true;
            }
        }
        return false;
    }

    function executeCommand(cmd) {
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { property string cmd; command: ["sh", "-c", cmd]; onExited: destroy() }',
            root
        );
        proc.cmd = cmd;
        proc.running = true;
    }

    function addFolderShortcut(targetPath, customName, targetCol, targetRow) {
        if (!targetPath) return;
        let cleanTarget = targetPath.replace(/\/+$/, "");
        let name = customName || cleanTarget.split("/").pop();
        if (!name) return;

        let destPath = desktopDir + "/" + name;
        if (typeof targetCol === "number" && typeof targetRow === "number") {
            targetCol = Math.max(0, Math.min(targetCol, maxColumns - 1));
            targetRow = Math.max(0, Math.min(targetRow, maxRows - 1));
            iconPositions[destPath] = { col: targetCol, row: targetRow };
            savePositions();
        }

        let cmd = "mkdir -p '" + cleanTarget.replace(/'/g, "'\\''") + "' '" + desktopDir.replace(/'/g, "'\\''") + "' && ln -sf '" + cleanTarget.replace(/'/g, "'\\''") + "' '" + destPath.replace(/'/g, "'\\''") + "'";
        executeCommand(cmd);
    }

    function addFileShortcut(targetPath, customName, targetCol, targetRow) {
        if (!targetPath) return;
        let cleanTarget = targetPath.replace(/\/+$/, "");
        let name = customName || cleanTarget.split("/").pop();
        if (!name) return;

        let destPath = desktopDir + "/" + name;
        if (typeof targetCol === "number" && typeof targetRow === "number") {
            targetCol = Math.max(0, Math.min(targetCol, maxColumns - 1));
            targetRow = Math.max(0, Math.min(targetRow, maxRows - 1));
            iconPositions[destPath] = { col: targetCol, row: targetRow };
            savePositions();
        }

        let cmd = "mkdir -p '" + desktopDir.replace(/'/g, "'\\''") + "' && ln -sf '" + cleanTarget.replace(/'/g, "'\\''") + "' '" + destPath.replace(/'/g, "'\\''") + "'";
        executeCommand(cmd);
    }

    function addAppShortcut(appPath, targetCol, targetRow) {
        if (!appPath) return;
        let fileName = appPath.split("/").pop();
        if (!fileName) return;

        let destPath = desktopDir + "/" + fileName;
        if (typeof targetCol === "number" && typeof targetRow === "number") {
            targetCol = Math.max(0, Math.min(targetCol, maxColumns - 1));
            targetRow = Math.max(0, Math.min(targetRow, maxRows - 1));
            iconPositions[destPath] = { col: targetCol, row: targetRow };
            savePositions();
        }

        let cmd = "mkdir -p '" + desktopDir.replace(/'/g, "'\\''") + "' && cp '" + appPath.replace(/'/g, "'\\''") + "' '" + destPath.replace(/'/g, "'\\''") + "' && chmod 755 '" + destPath.replace(/'/g, "'\\''") + "'";
        executeCommand(cmd);
    }

    function addDownloadsFolder() {
        let home = Quickshell.env("HOME") || "/home/verse";
        addFolderShortcut(home + "/Downloads", "Downloads");
    }

    function browseAndAddFolder() {
        browseFolderProcess.running = true;
    }

    function browseAndAddFile() {
        browseFileProcess.running = true;
    }

    function browseAndAddApp() {
        browseAppProcess.running = true;
    }

    function addDroppedUrl(urlStr, dropX, dropY, cellWidth, cellHeight) {
        if (!urlStr) return;
        let path = decodeURIComponent(urlStr);
        if (path.startsWith("file://")) {
            path = path.substring(7);
        }
        path = path.replace(/\/+$/, "");
        if (!path || path.startsWith(desktopDir + "/")) {
            return;
        }

        let fileName = path.split("/").pop();
        if (!fileName) return;

        let col = Math.max(0, Math.min(Math.floor(dropX / (cellWidth || 1)), maxColumns - 1));
        let row = Math.max(0, Math.min(Math.floor(dropY / (cellHeight || 1)), maxRows - 1));

        if (fileName.endsWith(".desktop")) {
            addAppShortcut(path, col, row);
        } else {
            addFileShortcut(path, fileName, col, row);
        }
    }

    function createNewFolder() {
        createFolderProcess.running = true;
    }

    function openTerminal() {
        openTerminalProcess.running = true;
    }

    function openFileManager() {
        openFileManagerProcess.running = true;
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
    }

    Process {
        id: loadPositionsProcess
        running: false
        command: ["cat", positionsFile]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    try {
                        let parsed = JSON.parse(text);
                        root.iconPositions = parsed || {};
                    } catch (e) {
                        console.warn("error parsing desktop positions:", e);
                    }
                }
                root.positionsLoaded = true;
                root.checkGridReady();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                root.positionsLoaded = true;
                root.checkGridReady();
            }
        }
    }

    Process {
        id: createFolderProcess
        running: false
        command: [
            "sh",
            "-c",
            "d=\"" + desktopDir + "\"; mkdir -p \"$d\"; name=\"New Folder\"; i=2; while [ -d \"$d/$name\" ]; do name=\"New Folder $i\"; i=$((i+1)); done; mkdir \"$d/$name\""
        ]
    }

    Process {
        id: openTerminalProcess
        running: false
        command: [
            "sh",
            "-c",
            "ghostty --working-directory=\"" + desktopDir + "\" 2>/dev/null || xdg-terminal-exec \"" + desktopDir + "\" 2>/dev/null || kitty --directory \"" + desktopDir + "\" 2>/dev/null"
        ]
    }

    Process {
        id: openFileManagerProcess
        running: false
        command: ["xdg-open", desktopDir]
    }

    Process {
        id: browseFolderProcess
        running: false
        command: ["zenity", "--file-selection", "--directory", "--title=Select Folder to Pin to Desktop"]

        stdout: StdioCollector {
            onStreamFinished: {
                let chosen = text.trim();
                if (chosen.length > 0) {
                    root.addFolderShortcut(chosen);
                }
            }
        }
    }

    Process {
        id: browseFileProcess
        running: false
        command: ["zenity", "--file-selection", "--title=Select File to Pin to Desktop"]

        stdout: StdioCollector {
            onStreamFinished: {
                let chosen = text.trim();
                if (chosen.length > 0) {
                    root.addFileShortcut(chosen);
                }
            }
        }
    }

    Process {
        id: browseAppProcess
        running: false
        command: ["zenity", "--file-selection", "--filename=/usr/share/applications/", "--file-filter=Desktop Applications (*.desktop) | *.desktop", "--title=Select Application to Pin to Desktop"]

        stdout: StdioCollector {
            onStreamFinished: {
                let chosen = text.trim();
                if (chosen.length > 0) {
                    root.addAppShortcut(chosen);
                }
            }
        }
    }
}
