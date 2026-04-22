pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool active: true
    property var items: []
    property var imageDataById: ({})
    property var linkPreviewCache: ({})
    property int revision: 0
    property bool _operationInProgress: false

    readonly property string dbPath: Quickshell.dataPath("clipboard.db")
    readonly property string binaryDataDir: Quickshell.dataPath("clipboard-data")
    readonly property string globalLogPath: Quickshell.dataPath("ambxst.log")
    readonly property string daemonPath: Qt.resolvedUrl("../../daemon/clipboard/ambxst-clipboard").toString().replace("file://", "")
    readonly property string linkPreviewScriptPath: Qt.resolvedUrl("../../scripts/link_preview.py").toString().replace("file://", "")
    readonly property string socketPath: "/tmp/ambxst-clipboard.sock"

    property bool _initialized: false
    signal listCompleted()
    signal fullContentRetrieved(string itemId, string content)
    signal linkPreviewFetched(string url, var metadata, string requestItemId)

    property Process clipboardDaemon: Process {
        running: root._initialized
        command: [daemonPath, "-db", dbPath, "-data", binaryDataDir, "-log", globalLogPath]
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (!line) return;
                try {
                    var msg = JSON.parse(line);
                    if (msg.event === "DATA" && msg.items) {
                        root._applyItems(msg.items);
                    }
                } catch (e) {}
            }
        }
        stderr: SplitParser { onRead: data => {} }
        onRunningChanged: {
            if (running) {
                root._fetchListCmd();
                initialListTimer.start();
            } else if (root._initialized) {
                restartTimer.start();
            }
        }
    }

    property Timer restartTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            clipboardDaemon.running = false;
            clipboardDaemon.running = true;
        }
    }

    property Timer initialListTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: root._fetchListCmd()
    }

    property Process _cmdProcess: Process {
        property string _pendingCmd: ""
        onRunningChanged: {
            if (!running && _pendingCmd !== "") {
                _pendingCmd = "";
            }
        }
    }

    property Process _getContentProcess: Process {
        property string _itemId: ""
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (!line) return;
                try {
                    var msg = JSON.parse(line);
                    if (msg.ok && msg.data !== undefined) {
                        root.fullContentRetrieved(_getContentProcess._itemId, msg.data);
                    }
                } catch(e) {}
            }
        }
        stderr: SplitParser { onRead: data => {} }
    }

    property Process _getImageProcess: Process {
        property string _itemId: ""
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (!line) return;
                try {
                    var msg = JSON.parse(line);
                    if (msg.ok && msg.data) {
                        root.imageDataById[_getImageProcess._itemId] = msg.data;
                        root.revision++;
                    }
                } catch(e) {}
            }
        }
        stderr: SplitParser { onRead: data => {} }
    }

    property Process loadImageProcess: _getImageProcess

    property Process linkPreviewProcess: Process {
        property string requestItemId: ""
        property string _out: ""
        stdout: SplitParser {
            onRead: data => { linkPreviewProcess._out += data + "\n"; }
        }
        stderr: SplitParser { onRead: data => {} }
        onExited: {
            if (exitCode === 0 && _out.trim().length > 0) {
                var raw = _out.trim();
                root.linkPreviewCache[requestItemId] = raw;
                root.revision++;
                try {
                    var meta = JSON.parse(raw);
                    root.linkPreviewFetched(meta.url || "", meta, requestItemId);
                } catch(e) {
                    root.linkPreviewFetched(raw, {}, requestItemId);
                }
            }
            _out = "";
        }
    }

    function _applyItems(jsonArray) {
        if (jsonArray.length === root.items.length && jsonArray.length > 0) {
            var first = jsonArray[0];
            var cur = root.items[0];
            if (cur && cur.hash === (first.content_hash || "") && cur.id === first.id.toString()) {
                root.listCompleted();
                return;
            }
        }
        var clipboardItems = [];
        for (var i = 0; i < jsonArray.length; i++) {
            var item = jsonArray[i];
            var isFile = item.mime_type === "text/uri-list";
            var preview = item.preview;
            if (isFile && item.full_content) {
                var uri = item.full_content.trim();
                if (uri.startsWith("file://")) {
                    var fp = uri.substring(7);
                    var fn = fp.split('/').pop();
                    try { fn = decodeURIComponent(fn); } catch(e) {}
                    preview = "[File] " + fn;
                }
            } else if (item.is_image === 1) {
                preview = "[Image]";
            }
            clipboardItems.push({
                id: item.id.toString(),
                preview: preview,
                fullContent: item.full_content || item.preview,
                mime: item.mime_type,
                isImage: item.is_image === 1,
                isFile: isFile,
                binaryPath: item.binary_path || "",
                hash: item.content_hash || "",
                size: item.size || 0,
                createdAt: item.created_at || 0,
                pinned: item.pinned === 1,
                alias: item.alias || "",
                displayIndex: (item.display_index !== null && item.display_index !== undefined) ? item.display_index : -1
            });
        }
        root.items = clipboardItems;
        root.listCompleted();
        root._operationInProgress = false;
    }

    function _runDaemonCmd(jsonStr) {
        _cmdProcess.command = [daemonPath, "-socket", socketPath, "-cmd", jsonStr];
        _cmdProcess.running = true;
    }

    property Process _listProcess: Process {
        property string _out: ""
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (!line) return;
                try {
                    var msg = JSON.parse(line);
                    if (msg.ok && msg.data) {
                        root._applyItems(msg.data);
                    }
                } catch(e) {}
            }
        }
        stderr: SplitParser { onRead: data => {} }
    }

    function _fetchListCmd() {
        if (_listProcess.running) return;
        _listProcess.command = [daemonPath, "-socket", socketPath, "-cmd", '{"cmd":"LIST"}'];
        _listProcess.running = true;
    }

    function list() {
        _fetchListCmd();
    }

    function remove(itemId) {
        _runDaemonCmd('{"cmd":"DELETE","id":"' + itemId + '"}');
    }

    function deleteItem(itemId) {
        remove(itemId);
    }

    function clear() {
        _runDaemonCmd('{"cmd":"CLEAR"}');
    }

    function togglePin(itemId) {
        _runDaemonCmd('{"cmd":"TOGGLE_PIN","id":"' + itemId + '"}');
    }

    function togglePinned(itemId) {
        togglePin(itemId);
    }

    function setAlias(itemId, alias) {
        var escaped = alias.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        _runDaemonCmd('{"cmd":"SET_ALIAS","id":"' + itemId + '","alias":"' + escaped + '"}');
    }

    function copyToClipboard(itemId) {
        _runDaemonCmd('{"cmd":"COPY_TO_CLIPBOARD","id":"' + itemId + '"}');
    }

    function swapItems(id1, id2) {
        _runDaemonCmd('{"cmd":"SWAP","id":"' + id1 + '","id2":"' + id2 + '"}');
    }

    function moveItemUp(itemId) {
        for (var i = 1; i < items.length; i++) {
            if (items[i].id === itemId) {
                swapItems(items[i].id, items[i-1].id);
                break;
            }
        }
    }

    function moveItemDown(itemId) {
        for (var i = 0; i < items.length - 1; i++) {
            if (items[i].id === itemId) {
                swapItems(items[i].id, items[i+1].id);
                break;
            }
        }
    }

    function getFullContent(itemId) {
        _getContentProcess._itemId = itemId;
        _getContentProcess.command = [daemonPath, "-socket", socketPath, "-cmd", '{"cmd":"GET_CONTENT","id":"' + itemId + '"}'];
        _getContentProcess.running = true;
    }

    function getImageData(itemId) {
        return root.imageDataById[itemId] || null;
    }

    function decodeToDataUrl(itemId, mime) {
        if (_getImageProcess.running) return;
        _getImageProcess._itemId = itemId;
        _getImageProcess.command = [daemonPath, "-socket", socketPath, "-cmd", '{"cmd":"GET_IMAGE","id":"' + itemId + '"}'];
        _getImageProcess.running = true;
    }

    function fetchLinkPreview(url, itemId) {
        if (root.linkPreviewCache[itemId]) return;
        linkPreviewProcess.requestItemId = itemId;
        linkPreviewProcess.command = ["python3", linkPreviewScriptPath, url, "5"];
        linkPreviewProcess.running = true;
    }

    function copyAndTypeEmoji(emojiText) {
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', Qt.application);
        p.command = ["sh", "-c", "printf '%s' '" + emojiText.replace(/'/g, "'\\''") + "' | wl-copy && sleep 0.1 && wtype -M ctrl -P v -p v -m ctrl"];
        p.onExited.connect(function() { p.destroy(); });
        p.running = true;
    }

    Component.onCompleted: {
        root._initialized = true;
    }
}
