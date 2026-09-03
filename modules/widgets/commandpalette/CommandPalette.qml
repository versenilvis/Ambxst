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
import qs.modules.services
import qs.config
import qs.modules.widgets.dashboard.widgets
import qs.modules.widgets.dashboard.clipboard
import qs.modules.widgets.dashboard.emoji

FloatingWindow {
    id: root

    visible: GlobalStates.commandPaletteVisible
    title: "Command Palette"
    color: "transparent"

    minimumSize: Qt.size(1000, 650)
    maximumSize: Qt.size(1000, 650)

    readonly property int currentTab: GlobalStates.commandPaletteTab
    readonly property var tabModel: [
        { name: "Apps", icon: Icons.apps },
        { name: "Clipboard", icon: Icons.clipboard },
        { name: "Emoji", icon: Icons.emoji }
    ]

    // Footer hints are per tab: the palette tells you what Enter does *here*
    readonly property var tabHints: [
        [{ key: "↑↓", label: "navigate" }, { key: "↵", label: "open" }, { key: "clip", label: "jump to clipboard" }],
        [{ key: "↵", label: "copy & close" }, { key: "⌘↵", label: "open" }, { key: "⌘P", label: "pin" }],
        [{ key: "↵", label: "copy & type" }, { key: "↑↓←→", label: "navigate" }]
    ]

    Shortcut {
        sequence: "Escape"
        onActivated: GlobalStates.commandPaletteVisible = false
    }

    Shortcut {
        sequence: "Ctrl+Tab"
        enabled: root.visible
        onActivated: {
            GlobalStates.commandPaletteTab = (root.currentTab + 1) % root.tabModel.length;
        }
    }

    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        enabled: root.visible
        onActivated: {
            let prevIndex = root.currentTab - 1;
            if (prevIndex < 0) {
                prevIndex = root.tabModel.length - 1;
            }
            GlobalStates.commandPaletteTab = prevIndex;
        }
    }

    readonly property var searchPlaceholders: ["Search applications…", "Search clipboard…", "Search emoji…"]

    // Route the shared field's text to whichever tab is showing. Apps also mirrors
    // into GlobalStates because its launcher already reads from there.
    function applySearch(text) {
        const item = root.currentTabItem();
        if (root.currentTab === 0) {
            GlobalStates.launcherSearchText = text;
        }
        if (item && item.searchText !== undefined) {
            item.searchText = text;
        }
    }

    function currentTabItem() {
        if (root.currentTab === 0)
            return widgetsLoader.item;
        if (root.currentTab === 1)
            return clipboardLoader.item;
        return emojiLoader.item;
    }

    function focusCurrentTab() {
        Qt.callLater(() => sharedSearch.forceActiveFocus());
    }

    onVisibleChanged: {
        if (visible) {
            focusCurrentTab();
        } else {
            GlobalStates.clearLauncherState();
        }
    }

    onCurrentTabChanged: {
        sharedSearch.text = "";
        if (visible) {
            focusCurrentTab();
        }
    }

    // prefix jump to clipboard or emoji tab
    Connections {
        target: GlobalStates
        function onLauncherSearchTextChanged() {
            if (!root.visible || root.currentTab !== 0) {
                return;
            }
            const text = GlobalStates.launcherSearchText;
            const clipPrefix = (Config.prefix && Config.prefix.clipboard ? Config.prefix.clipboard : "cc") + " ";
            const emojiPrefix = (Config.prefix && Config.prefix.emoji ? Config.prefix.emoji : "ee") + " ";
            if (text === clipPrefix || text === "clip ") {
                if (widgetsLoader.item)
                    widgetsLoader.item.clearSearch();
                GlobalStates.commandPaletteTab = 1;
            } else if (text === emojiPrefix || text === "emoji ") {
                if (widgetsLoader.item)
                    widgetsLoader.item.clearSearch();
                GlobalStates.commandPaletteTab = 2;
            }
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
        color: Colors.background
        radius: Styling.radius(0)
        border.width: 1
        border.color: Colors.surfaceContainer

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // One shared search field for every tab. Each tab keeps its own filtering
            // logic, it just no longer draws its own input (see each tab's showSearch).
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 18
                Layout.bottomMargin: 4
                spacing: 13

                // The active tab's own glyph, so the field says what it is searching
                Text {
                    text: root.tabModel[root.currentTab].icon
                    font.family: Icons.font
                    font.pixelSize: 21
                    color: Colors.outline
                }

                TextField {
                    id: sharedSearch
                    Layout.fillWidth: true
                    background: null
                    color: Colors.overBackground
                    placeholderTextColor: Colors.outline
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(9)
                    placeholderText: root.searchPlaceholders[root.currentTab]
                    text: ""

                    onTextChanged: root.applySearch(text)

                    Keys.onEscapePressed: GlobalStates.commandPaletteVisible = false
                }
            }

            // Mode chips: labeled and clickable, instead of an icon-only sidebar
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 10
                Layout.bottomMargin: 12
                spacing: 8

                Repeater {
                    model: root.tabModel

                    Rectangle {
                        id: chip
                        required property int index
                        required property var modelData

                        readonly property bool active: root.currentTab === chip.index

                        implicitWidth: chipRow.implicitWidth + 26
                        implicitHeight: 30
                        radius: Styling.radius(-4)
                        color: chip.active ? Colors.primary : Colors.surfaceContainerLowest

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration / 2
                                easing.type: Easing.OutQuart
                            }
                        }

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 7

                            Text {
                                text: chip.modelData.icon
                                textFormat: Text.RichText
                                font.family: Icons.font
                                font.pixelSize: 14
                                color: chip.active ? Colors.overPrimary : Colors.outline
                            }

                            Text {
                                text: chip.modelData.name
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: chip.active ? Font.Bold : Font.Normal
                                color: chip.active ? Colors.overPrimary : Colors.outline
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.commandPaletteTab = chip.index
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: "ctrl+tab to switch"
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.outlineVariant
                }

                Rectangle {
                    implicitWidth: escLabel.implicitWidth + 14
                    implicitHeight: 22
                    radius: Styling.radius(-10)
                    color: "transparent"
                    border.width: 1
                    border.color: Colors.surfaceContainer

                    Text {
                        id: escLabel
                        anchors.centerIn: parent
                        text: "esc"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outlineVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.commandPaletteVisible = false
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.preferredHeight: 1
                color: Colors.surfaceContainer
            }

            // Tab content. Each tab loads on first use and then stays loaded, so
            // switching keeps its search text and scroll position without paying
            // for all three up front (ClipboardTab alone is ~3.6k lines).
            StackLayout {
                id: contentStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 12
                currentIndex: root.currentTab

                Loader {
                    id: widgetsLoader
                    active: root.currentTab === 0 || widgetsLoader.status === Loader.Ready
                    sourceComponent: WidgetsTab {
                        leftPanelWidth: 0
                        showSearch: false
                    }
                }

                Loader {
                    id: clipboardLoader
                    active: root.currentTab === 1 || clipboardLoader.status === Loader.Ready
                    sourceComponent: ClipboardTab {
                        leftPanelWidth: 270
                        showSearch: false
                        onBackspaceOnEmpty: GlobalStates.commandPaletteTab = 0
                        onRequestOpenItem: (itemId, items, currentContent, filePathGetter, urlChecker) => {
                            root.openItem(itemId, items, currentContent, filePathGetter, urlChecker);
                        }
                    }
                    onLoaded: {
                        if (root.currentTab === 1)
                            root.focusCurrentTab();
                    }
                }

                Loader {
                    id: emojiLoader
                    active: root.currentTab === 2 || emojiLoader.status === Loader.Ready
                    sourceComponent: EmojiTab {
                        leftPanelWidth: 270
                        showSearch: false
                        onBackspaceOnEmpty: GlobalStates.commandPaletteTab = 0
                    }
                    onLoaded: {
                        if (root.currentTab === 2)
                            root.focusCurrentTab();
                    }
                }
            }

            // Contextual keyboard hints
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                color: Colors.surfaceContainerLowest
                bottomLeftRadius: Styling.radius(0)
                bottomRightRadius: Styling.radius(0)

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Colors.surfaceContainer
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 18

                    Repeater {
                        model: root.tabHints[root.currentTab]

                        RowLayout {
                            id: hint
                            required property var modelData
                            spacing: 7

                            Rectangle {
                                implicitWidth: hintKey.implicitWidth + 12
                                implicitHeight: 19
                                radius: Styling.radius(-11)
                                color: Colors.surfaceContainer

                                Text {
                                    id: hintKey
                                    anchors.centerIn: parent
                                    text: hint.modelData.key
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.overBackground
                                }
                            }

                            Text {
                                text: hint.modelData.label
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.outline
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Quick toggles live here rather than inside the Apps tab: the
                    // footer is otherwise half empty, and they stay reachable from
                    // every tab instead of only from Apps.
                    RowLayout {
                        spacing: 2

                        ControlButton {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            iconName: {
                                if (!NetworkService.wifiEnabled)
                                    return Icons.wifiOff;
                                const strength = NetworkService.networkStrength;
                                if (strength === 0)
                                    return Icons.wifiHigh;
                                if (strength < 25)
                                    return Icons.wifiNone;
                                if (strength < 50)
                                    return Icons.wifiLow;
                                if (strength < 75)
                                    return Icons.wifiMedium;
                                return Icons.wifiHigh;
                            }
                            isActive: NetworkService.wifiEnabled
                            tooltipText: NetworkService.wifiEnabled ? "Wi-Fi: On" : "Wi-Fi: Off"
                            onClicked: NetworkService.toggleWifi()
                        }

                        ControlButton {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            iconName: {
                                if (!BluetoothService.enabled)
                                    return Icons.bluetoothOff;
                                if (BluetoothService.connected)
                                    return Icons.bluetoothConnected;
                                return Icons.bluetooth;
                            }
                            isActive: BluetoothService.enabled
                            tooltipText: {
                                if (!BluetoothService.enabled)
                                    return "Bluetooth: Off";
                                if (BluetoothService.connected)
                                    return "Bluetooth: Connected";
                                return "Bluetooth: On";
                            }
                            onClicked: BluetoothService.toggle()
                        }

                        ControlButton {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            iconName: Icons.nightLight
                            isActive: NightLightService.active
                            tooltipText: NightLightService.active ? "Night Light: On" : "Night Light: Off"
                            onClicked: NightLightService.toggle()
                        }

                        ControlButton {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            iconName: Icons.caffeine
                            isActive: CaffeineService.inhibit
                            tooltipText: CaffeineService.inhibit ? "Caffeine: On" : "Caffeine: Off"
                            onClicked: CaffeineService.toggleInhibit()
                        }

                        ControlButton {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            iconName: Icons.gameMode
                            isActive: GameModeService.toggled
                            tooltipText: GameModeService.toggled ? "Game Mode: On" : "Game Mode: Off"
                            onClicked: GameModeService.toggle()
                        }
                    }
                }
            }
        }
    }
}
