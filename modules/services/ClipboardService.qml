pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool active: true
    property var items: []
    property var linkPreviewCache: ({})
    property bool _operationInProgress: false
    property int pageSize: 50
    property bool hasMoreItems: false
    property bool _isAppending: false
    property var _previewQueue: []

    readonly property string dbPath: Quickshell.env("HOME") + "/.local/share/Ambxst/clipboard.db"
    readonly property string binaryDataDir: Quickshell.env("HOME") + "/.local/share/Ambxst/clipboard-data"
    readonly property string linkPreviewScriptPath: Qt.resolvedUrl("../../scripts/link_preview.py").toString().replace("file://", "")

    property bool _initialized: false
    signal listCompleted()
    signal fullContentRetrieved(string itemId, string content)
    signal linkPreviewFetched(string url, var metadata, string requestItemId)

    property Connections daemonConnections: Connections {
        target: DaemonClient
        
        function onDaemonConnectedChanged() {
            if (DaemonClient.daemonConnected && root._initialized) {
                root.initializeClipboardBackend();
                root.list();
            }
        }

        function onClipboardReceived(itemsList) {
            root._applyItems(itemsList, root._isAppending);
            root._isAppending = false;
        }

        function onClipboardContentReceived(itemId, content) {
            if (content && root.isUrl(content)) {
                if (!root.linkPreviewCache[itemId]) {
                    root.fetchLinkPreview(content.trim(), itemId);
                }
            }
            root.fullContentRetrieved(itemId, content);
        }
    }

    property Process linkPreviewProcess: Process {
        property string requestItemId: ""
        property string _out: ""
        stdout: SplitParser {
            onRead: data => { linkPreviewProcess._out += data + "\n"; }
        }
        stderr: SplitParser { onRead: data => {} }
        onExited: exitCode => {
            if (exitCode === 0 && _out.trim().length > 0) {
                var raw = _out.trim();
                try {
                    var meta = JSON.parse(raw);
                    // store as parsed object under both id and url
                    root.linkPreviewCache[requestItemId] = meta;
                    if (meta.url) {
                        root.linkPreviewCache[meta.url.trim()] = meta;
                    }
                    root.linkPreviewFetched(meta.url || "", meta, requestItemId);
                } catch(e) {
                    // store raw string under id as fallback
                    root.linkPreviewCache[requestItemId] = raw;
                    root.linkPreviewFetched(raw, {}, requestItemId);
                }
            }
            _out = "";
            // process next queue item
            root._processQueue();
        }
    }

    function _applyItems(jsonArray, append) {
        if (!append && jsonArray.length === root.items.length && jsonArray.length > 0) {
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
        root.items = append ? root.items.concat(clipboardItems) : clipboardItems;
        root.hasMoreItems = jsonArray.length >= root.pageSize;
        root.listCompleted();
        root._operationInProgress = false;

        // auto-fetch link previews in background
        for (var j = 0; j < clipboardItems.length; j++) {
            var ci = clipboardItems[j];
            if (!ci.isFile && !ci.isImage && root.isUrl(ci.preview)) {
                if (ci.preview.endsWith("...")) {
                    // retrieve full content first
                    root.getFullContent(ci.id);
                } else {
                    if (!root.linkPreviewCache[ci.id]) {
                        root.fetchLinkPreview(ci.preview.trim(), ci.id);
                    }
                }
            }
        }
    }

    function initializeClipboardBackend() {
        DaemonClient.sendCommand({
            type: "init_clipboard",
            db_path: root.dbPath,
            data_dir: root.binaryDataDir
        });
    }

    function list() {
        root.initializeClipboardBackend();
        root._isAppending = false;
        DaemonClient.sendCommand({
            type: "list_clipboard",
            limit: root.pageSize,
            offset: 0
        });
    }

    function loadMore() {
        if (!root.hasMoreItems) return;
        root._isAppending = true;
        DaemonClient.sendCommand({
            type: "list_clipboard",
            limit: root.pageSize,
            offset: root.items.length
        });
    }

    function remove(itemId) {
        DaemonClient.sendCommand({
            type: "delete_clipboard",
            id: parseInt(itemId)
        });
    }

    function deleteItem(itemId) {
        remove(itemId);
    }

    function clear() {
        DaemonClient.sendCommand({
            type: "clear_clipboard"
        });
    }

    function togglePin(itemId) {
        DaemonClient.sendCommand({
            type: "toggle_pin_clipboard",
            id: parseInt(itemId)
        });
    }

    function togglePinned(itemId) {
        togglePin(itemId);
    }

    function setAlias(itemId, alias) {
        DaemonClient.sendCommand({
            type: "set_alias_clipboard",
            id: parseInt(itemId),
            alias: alias
        });
    }

    function copyToClipboard(itemId) {
        DaemonClient.sendCommand({
            type: "copy_to_clipboard",
            id: parseInt(itemId)
        });
    }

    function swapItems(id1, id2) {
        DaemonClient.sendCommand({
            type: "swap_clipboard",
            id1: parseInt(id1),
            id2: parseInt(id2)
        });
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
        DaemonClient.sendCommand({
            type: "get_content_clipboard",
            id: parseInt(itemId)
        });
    }

    function imageSource(item) {
        if (!item || !item.binaryPath) return "";
        return "file://" + item.binaryPath;
    }

    function isUrl(text) {
        if (!text) return false;
        var trimmed = text.trim();
        return /^https?:\/\/[^\s]+/.test(trimmed);
    }

    function _processQueue() {
        if (linkPreviewProcess.running) return;
        if (root._previewQueue.length === 0) return;

        var next = root._previewQueue.shift();
        linkPreviewProcess.requestItemId = next.itemId;
        linkPreviewProcess.command = ["python3", linkPreviewScriptPath, next.url, "5"];
        linkPreviewProcess.running = true;
    }

    function fetchLinkPreview(url, itemId) {
        if (root.linkPreviewCache[itemId]) return;
        
        // check if already in queue
        for (var i = 0; i < root._previewQueue.length; i++) {
            if (root._previewQueue[i].itemId === itemId) return;
        }
        
        root._previewQueue.push({url: url, itemId: itemId});
        root._processQueue();
    }

    function copyAndTypeEmoji(emojiText) {
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', Qt.application);
        p.command = ["sh", "-c", "printf '%s' '" + emojiText.replace(/'/g, "'\\''") + "' | wl-copy"];
        p.onExited.connect(function() { p.destroy(); });
        p.running = true;
    }

    Component.onCompleted: {
        root._initialized = true;
        if (DaemonClient.daemonConnected) {
            root.initializeClipboardBackend();
            root.list();
        }
    }
}
