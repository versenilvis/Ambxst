pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config

Rectangle {
    id: root
    focus: true
    color: "transparent"

    property bool showSearch: false
    property string searchText: ""
    property string prefixIcon: ""
    signal backspaceOnEmpty()

    property int cellSize: 42
    property int cellSpacing: 6
    property int columns: Math.max(8, Math.floor((width - 24) / (cellSize + cellSpacing)))

    property var recentEmojis: []
    property var groupMap: ({})
    property var rowsData: []
    property var flatVisibleEmojis: []
    property int focusedFlatIndex: 0
    property string activeCategoryId: recentEmojis.length > 0 ? "recent" : "Smileys & Emotion"

    readonly property var currentSelectedEmoji: (focusedFlatIndex >= 0 && focusedFlatIndex < flatVisibleEmojis.length) ? flatVisibleEmojis[focusedFlatIndex] : null

    onFocusedFlatIndexChanged: {
        if (flatVisibleEmojis && focusedFlatIndex >= 0 && focusedFlatIndex < flatVisibleEmojis.length) {
            var em = flatVisibleEmojis[focusedFlatIndex];
            if (em && em.categoryId && em.categoryId !== activeCategoryId) {
                activeCategoryId = em.categoryId;
            }
        }
    }

    // Skin tone picker state
    property var activeSkinToneEmoji: null
    property point skinTonePopupPos: Qt.point(0, 0)

    readonly property var skinTones: [
        { name: "Default", modifier: "" },
        { name: "Light", modifier: "🏻" },
        { name: "Medium-Light", modifier: "🏼" },
        { name: "Medium", modifier: "🏽" },
        { name: "Medium-Dark", modifier: "🏾" },
        { name: "Dark", modifier: "🏿" }
    ]

    // Categories with Phosphor SVG icons matching theme
    readonly property var categories: [
        { id: "recent", name: "Recent", icon: Icons.clock },
        { id: "Smileys & Emotion", name: "Smileys", icon: Icons.emoji },
        { id: "People & Body", name: "People", icon: Icons.user },
        { id: "Animals & Nature", name: "Nature", icon: Icons.cactus },
        { id: "Food & Drink", name: "Food", icon: Icons.caffeine },
        { id: "Travel & Places", name: "Travel", icon: Icons.paperPlane },
        { id: "Activities", name: "Activities", icon: Icons.gamepad },
        { id: "Objects", name: "Objects", icon: Icons.cube },
        { id: "Symbols", name: "Symbols", icon: Icons.at },
        { id: "Flags", name: "Flags", icon: Icons.globe }
    ]

    function navUp() { moveSelection(0, -1); }
    function navDown() { moveSelection(0, 1); }
    function navLeft() { moveSelection(-1, 0); }
    function navRight() { moveSelection(1, 0); }
    function navAccept() { acceptSelection(); }

    function focusSearchInput() {
        if (showSearch && searchInput) {
            searchInput.focusInput();
        } else {
            root.forceActiveFocus();
        }
    }

    onSearchTextChanged: {
        var q = searchText.trim();
        if (q.length === 0) {
            searchDebounceTimer.stop();
            rebuildRows();
        } else {
            searchDebounceTimer.restart();
        }
    }

    onColumnsChanged: {
        rebuildRows();
    }

    function moveSelection(dx, dy) {
        if (flatVisibleEmojis.length === 0) return;
        var cols = Math.max(1, root.columns);
        var current = focusedFlatIndex;
        var next = current + dx + (dy * cols);

        if (next < 0) next = 0;
        if (next >= flatVisibleEmojis.length) next = flatVisibleEmojis.length - 1;

        focusedFlatIndex = next;
        scrollToFocused();
    }

    function acceptSelection() {
        if (focusedFlatIndex >= 0 && focusedFlatIndex < flatVisibleEmojis.length) {
            copyEmoji(flatVisibleEmojis[focusedFlatIndex]);
        }
    }

    function scrollToFocused() {
        if (focusedFlatIndex < 0 || focusedFlatIndex >= flatVisibleEmojis.length) return;
        for (var i = 0; i < rowsData.length; i++) {
            var item = rowsData[i];
            if (item.type === "row" && focusedFlatIndex >= item.startIndex && focusedFlatIndex < item.startIndex + item.emojis.length) {
                emojiListView.positionViewAtIndex(i, ListView.Contain);
                break;
            }
        }
    }

    function jumpToCategory(catId) {
        activeCategoryId = catId;
        for (var i = 0; i < rowsData.length; i++) {
            var item = rowsData[i];
            if (item.type === "header" && item.categoryId === catId) {
                emojiListView.positionViewAtIndex(i, ListView.Beginning);
                for (var j = i + 1; j < rowsData.length; j++) {
                    if (rowsData[j].type === "row" && rowsData[j].emojis && rowsData[j].emojis.length > 0) {
                        focusedFlatIndex = rowsData[j].startIndex;
                        break;
                    }
                }
                break;
            }
        }
    }

    function updateCategoryFromScroll() {
        if (root.searchText.trim().length > 0 || rowsData.length === 0) return;
        var topRowIdx = emojiListView.indexAt(20, emojiListView.contentY + 20);
        if (topRowIdx >= 0 && topRowIdx < rowsData.length) {
            var item = rowsData[topRowIdx];
            if (item && item.categoryId && item.categoryId !== activeCategoryId) {
                activeCategoryId = item.categoryId;
            }
        }
    }

    function copyEmoji(emojiObj, modifier) {
        var char = emojiObj.emoji;
        if (modifier && modifier.length > 0) {
            char += modifier;
        }

        activeSkinToneEmoji = null;
        addToRecent(emojiObj, char);
        ClipboardService.copyAndTypeEmoji(char);

        GlobalStates.emojiVisible = false;
        GlobalStates.commandPaletteVisible = false;
    }

    function addToRecent(emojiObj, usedChar) {
        var baseEmoji = emojiObj.emoji;
        var updated = [];
        
        var newEntry = {
            emoji: usedChar || baseEmoji,
            baseEmoji: baseEmoji,
            name: emojiObj.name,
            slug: emojiObj.slug,
            group: emojiObj.group,
            search: emojiObj.search,
            skin_tone_support: emojiObj.skin_tone_support
        };

        updated.push(newEntry);

        for (var i = 0; i < recentEmojis.length; i++) {
            if (recentEmojis[i].emoji !== newEntry.emoji && updated.length < 30) {
                updated.push(recentEmojis[i]);
            }
        }

        recentEmojis = updated;
        saveRecentEmojis();
        rebuildRows();
    }

    function clearRecentEmojis() {
        recentEmojis = [];
        saveRecentEmojis();
        rebuildRows();
    }

    function buildSearchRows(filtered) {
        var rows = [];
        var flat = [];
        var cols = Math.max(1, root.columns);

        rows.push({
            type: "header",
            categoryId: "search",
            title: `Search Results (${filtered.length})`,
            canClear: false
        });

        for (var r = 0; r < filtered.length; r += cols) {
            var chunk = filtered.slice(r, r + cols);
            var rowStartIndex = flat.length;
            for (var c = 0; c < chunk.length; c++) {
                var item = chunk[c];
                item.flatIndex = flat.length;
                item.categoryId = item.group || "Smileys & Emotion";
                flat.push(item);
            }
            rows.push({
                type: "row",
                categoryId: chunk[0].categoryId,
                startIndex: rowStartIndex,
                emojis: chunk
            });
        }

        flatVisibleEmojis = flat;
        rowsData = rows;
        if (flat.length > 0) {
            focusedFlatIndex = 0;
            if (flat[0] && flat[0].categoryId) {
                activeCategoryId = flat[0].categoryId;
            }
        }
    }

    function rebuildRows() {
        var q = searchText.trim();
        if (q.length > 0) {
            searchDebounceTimer.restart();
            return;
        }

        var rows = [];
        var flat = [];
        var cols = Math.max(1, root.columns);
            // Categorized mode
            // 1. Recently used
            if (recentEmojis.length > 0) {
                rows.push({
                    type: "header",
                    categoryId: "recent",
                    title: "Recently Used",
                    canClear: true
                });

                for (var r = 0; r < recentEmojis.length; r += cols) {
                    var chunk = recentEmojis.slice(r, r + cols);
                    var rowStartIndex = flat.length;
                    for (var c = 0; c < chunk.length; c++) {
                        var e = chunk[c];
                        e.flatIndex = flat.length;
                        e.categoryId = "recent";
                        flat.push(e);
                    }
                    rows.push({
                        type: "row",
                        categoryId: "recent",
                        startIndex: rowStartIndex,
                        emojis: chunk
                    });
                }
            }

            // 2. Categories
            for (var g = 1; g < categories.length; g++) {
                var cat = categories[g];
                var list = groupMap[cat.id] || [];
                if (list.length === 0) continue;

                rows.push({
                    type: "header",
                    categoryId: cat.id,
                    title: cat.name,
                    canClear: false
                });

                for (var r = 0; r < list.length; r += cols) {
                    var chunk = list.slice(r, r + cols);
                    var rowStartIndex = flat.length;
                    for (var c = 0; c < chunk.length; c++) {
                        var e = chunk[c];
                        e.flatIndex = flat.length;
                        e.categoryId = cat.id;
                        flat.push(e);
                    }
                    rows.push({
                        type: "row",
                        categoryId: cat.id,
                        startIndex: rowStartIndex,
                        emojis: chunk
                    });
                }
            }
        }

        flatVisibleEmojis = flat;
        rowsData = rows;
        if (flat.length > 0) {
            if (focusedFlatIndex < 0 || focusedFlatIndex >= flat.length) {
                focusedFlatIndex = 0;
            }
            if (flat[focusedFlatIndex] && flat[focusedFlatIndex].categoryId) {
                activeCategoryId = flat[focusedFlatIndex].categoryId;
            }
        } else {
            activeCategoryId = recentEmojis.length > 0 ? "recent" : "Smileys & Emotion";
        }
    }

    // debounce timer for search query
    Timer {
        id: searchDebounceTimer
        interval: 30
        repeat: false
        onTriggered: {
            var q = root.searchText.trim();
            if (q.length > 0) {
                DaemonClient.sendCommand({ type: "search_emojis", query: q, limit: 120 });
            }
        }
    }

    // daemon event connection for emojis
    Connections {
        target: DaemonClient
        function onEmojiGroupsReceived(data) {
            if (!data) return;
            root.groupMap = data;
            if (root.searchText.trim().length === 0) {
                root.rebuildRows();
            }
        }
        function onEmojiSearchResultsReceived(data) {
            if (!data) return;
            if (root.searchText.trim().length > 0) {
                root.buildSearchRows(data);
            }
        }
        function onDaemonConnectedChanged() {
            if (DaemonClient.daemonConnected && Object.keys(root.groupMap).length === 0) {
                DaemonClient.sendCommand({ type: "get_all_emojis" });
            }
        }
    }

    Component.onCompleted: {
        DaemonClient.sendCommand({ type: "get_all_emojis" });
    }

    // Load recents
    Process {
        id: recentProcess
        running: true
        command: ["bash", "-c", "cat " + Quickshell.dataDir + "/emojis.json 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.recentEmojis = JSON.parse(text.trim());
                } catch (e) {
                    root.recentEmojis = [];
                }
                root.rebuildRows();
            }
        }
    }

    Process {
        id: saveProcess
        running: false
    }

    function saveRecentEmojis() {
        var jsonStr = JSON.stringify(recentEmojis, null, 2);
        saveProcess.command = ["bash", "-c", "mkdir -p '" + Quickshell.dataDir + "' && cat << 'EOF' > '" + Quickshell.dataDir + "/emojis.json'\n" + jsonStr + "\nEOF"];
        saveProcess.running = true;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // Optional internal search (when showSearch is true)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            visible: root.showSearch

            SearchInput {
                id: searchInput
                anchors.fill: parent
                text: root.searchText
                placeholderText: "Search emojis..."
                prefixIcon: root.prefixIcon

                onSearchTextChanged: text => {
                    root.searchText = text;
                }

                onBackspaceOnEmpty: {
                    root.backspaceOnEmpty();
                }

                onAccepted: {
                    root.acceptSelection();
                }

                onDownPressed: {
                    root.navDown();
                }

                onUpPressed: {
                    root.navUp();
                }

                onLeftPressed: {
                    root.navLeft();
                }

                onRightPressed: {
                    root.navRight();
                }

                onEscapePressed: {
                    if (root.searchText.length > 0) {
                        root.searchText = "";
                    } else {
                        GlobalStates.emojiVisible = false;
                        GlobalStates.commandPaletteVisible = false;
                    }
                }
            }
        }

        // Category Navigation Bar with Phosphor theme icons
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: "transparent"
            visible: root.searchText.trim().length === 0

            Row {
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: root.categories

                    Rectangle {
                        id: catChip
                        required property var modelData
                        required property int index

                        width: 38
                        height: 28
                        radius: Styling.radius(-8)

                        readonly property bool active: root.activeCategoryId === catChip.modelData.id

                        color: catChip.active ? Styling.srItem("primary") : (catMouse.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration / 2
                                easing.type: Easing.OutQuart
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: catChip.modelData.icon
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: catChip.active ? Styling.srItem("overprimary") : (catMouse.containsMouse ? Colors.overBackground : Colors.outline)

                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation {
                                    duration: Config.animDuration / 2
                                    easing.type: Easing.OutQuart
                                }
                            }
                        }

                        MouseArea {
                            id: catMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.jumpToCategory(catChip.modelData.id)
                        }

                        StyledToolTip {
                            visible: catMouse.containsMouse
                            tooltipText: catChip.modelData.name
                            delay: 200
                        }
                    }
                }
            }
        }

        // Emojis Virtualized ListView (Rows)
        ListView {
            id: emojiListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 4

            model: root.rowsData

            onContentYChanged: {
                if (emojiListView.moving || emojiListView.dragging) {
                    root.updateCategoryFromScroll();
                }
            }

            delegate: Item {
                id: rowDelegate
                required property var modelData
                required property int index

                readonly property var rowItem: modelData

                width: emojiListView.width
                height: rowItem.type === "header" ? 30 : root.cellSize

                // 1. Header Delegate
                Item {
                    anchors.fill: parent
                    visible: rowDelegate.rowItem.type === "header"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowDelegate.rowItem.title || ""
                        font.family: Config.defaultFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Colors.outline
                    }

                    // Clear button for Recent
                    Button {
                        id: clearBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!rowDelegate.rowItem.canClear
                        width: 22
                        height: 22

                        background: Rectangle {
                            radius: Styling.radius(4)
                            color: clearBtn.hovered ? Colors.errorContainer : "transparent"
                        }

                        contentItem: Text {
                            text: Icons.trash
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: clearBtn.hovered ? Colors.error : Colors.outline
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: root.clearRecentEmojis()

                        StyledToolTip {
                            visible: clearBtn.hovered
                            tooltipText: "Clear recent"
                            delay: 200
                        }
                    }
                }

                // 2. Row Delegate (Emoji Grid Row)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    spacing: root.cellSpacing
                    visible: rowDelegate.rowItem.type === "row"

                    Repeater {
                        model: rowDelegate.rowItem.emojis || []

                        delegate: Rectangle {
                            id: cellItem
                            required property var modelData
                            required property int index

                            readonly property var emData: modelData

                            width: root.cellSize
                            height: root.cellSize
                            radius: Styling.radius(6)

                            readonly property bool isSelected: root.focusedFlatIndex === cellItem.emData.flatIndex

                            color: {
                                if (isSelected) return Styling.srItem("primary");
                                if (cellMouse.containsMouse) return Colors.surfaceContainerHigh;
                                return "transparent";
                            }

                            border.color: isSelected ? Styling.srItem("overprimary") : "transparent"
                            border.width: isSelected ? 1 : 0

                            Text {
                                anchors.centerIn: parent
                                text: cellItem.emData ? cellItem.emData.emoji : ""
                                font.pixelSize: 22
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            // Skin tone indicator dot
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 3
                                width: 4
                                height: 4
                                radius: 2
                                color: Styling.srItem("primary")
                                visible: !!cellItem.emData.skin_tone_support && !cellItem.isSelected
                            }

                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton

                                onEntered: {
                                    root.focusedFlatIndex = cellItem.emData.flatIndex;
                                }

                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton && cellItem.emData.skin_tone_support) {
                                        var mapped = cellItem.mapToItem(root, 0, 0);
                                        root.skinTonePopupPos = Qt.point(mapped.x, mapped.y);
                                        root.activeSkinToneEmoji = cellItem.emData;
                                    } else {
                                        root.copyEmoji(cellItem.emData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Skin Tone Selector Popup
    Rectangle {
        id: skinTonePopup
        visible: root.activeSkinToneEmoji != null
        x: Math.min(Math.max(8, root.skinTonePopupPos.x - 40), root.width - width - 8)
        y: Math.max(8, root.skinTonePopupPos.y - height - 6)
        width: skinToneRow.width + 12
        height: 44
        radius: Styling.radius(8)
        color: Colors.surfaceContainerHigh
        border.color: Colors.surface
        border.width: 1
        z: 999

        layer.enabled: true
        layer.effect: Shadow {}

        Row {
            id: skinToneRow
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: root.skinTones

                Rectangle {
                    required property var modelData
                    width: 32
                    height: 32
                    radius: Styling.radius(4)
                    color: skinToneMouse.containsMouse ? Styling.srItem("primary") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: root.activeSkinToneEmoji ? (root.activeSkinToneEmoji.baseEmoji || root.activeSkinToneEmoji.emoji) + modelData.modifier : ""
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: skinToneMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (root.activeSkinToneEmoji) {
                                root.copyEmoji(root.activeSkinToneEmoji, modelData.modifier);
                            }
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 998
        visible: root.activeSkinToneEmoji != null
        onClicked: root.activeSkinToneEmoji = null
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (activeSkinToneEmoji != null) {
                activeSkinToneEmoji = null;
                event.accepted = true;
            } else if (searchText.length > 0) {
                searchText = "";
                event.accepted = true;
            } else {
                GlobalStates.emojiVisible = false;
                GlobalStates.commandPaletteVisible = false;
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Left) {
            navLeft();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            navRight();
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            navUp();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            navDown();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            navAccept();
            event.accepted = true;
        }
    }
}
