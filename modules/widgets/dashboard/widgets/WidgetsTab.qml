import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
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
    implicitWidth: 280
    implicitHeight: 450

    property int leftPanelWidth: 0
    // See ClipboardTab: the palette owns the search field when this is false.
    property bool showSearch: true
    property alias searchText: appLauncher.searchText

    // The palette owns the visible search field, so it forwards navigation keys
    // here; re-emit them on the (hidden) internal input that already has all the
    // list-navigation wiring attached.
    function navUp() { searchInput.upPressed(); }
    function navDown() { searchInput.downPressed(); }
    function navLeft() { searchInput.leftPressed(); }
    function navRight() { searchInput.rightPressed(); }
    function navAccept() { searchInput.accepted(); }


    function focusAppSearch() {
        Qt.callLater(() => {
            appLauncher.focusSearchInput();
        });
    }

    function focusSearchInput() {
        focusAppSearch();
    }

    function clearSearch() {
        appLauncher.clearSearch();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // app launcher
        Rectangle {
            id: appLauncher
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            property string searchText: GlobalStates.launcherSearchText
            property bool showResults: searchText.length > 0
            property int selectedIndex: GlobalStates.launcherSelectedIndex

            // options menu state
            property int expandedItemIndex: -1
            property int selectedOptionIndex: 0
            property bool keyboardNavigation: false

            // animated model for smooth filtering
            property var filteredApps: []
            property var appsById: ({})

            // incremental loading state
            property var pendingApps: []
            property int loadedCount: 0
            property int batchSize: 10

            Timer {
                id: incrementalLoader
                interval: 100
                repeat: true
                running: false
                onTriggered: {
                    if (appLauncher.loadedCount >= appLauncher.pendingApps.length || appLauncher.batchSize <= 0) {
                        running = false;
                        return;
                    }

                    let endIndex = Math.min(appLauncher.loadedCount + appLauncher.batchSize, appLauncher.pendingApps.length);
                    for (let i = appLauncher.loadedCount; i < endIndex; i++) {
                        let app = appLauncher.pendingApps[i];
                        appsModel.append({
                            appId: app.id,
                            appName: app.name,
                            appIcon: app.icon,
                            appComment: app.comment,
                            appExecString: app.execString,
                            appCategories: app.categories,
                            appRunInTerminal: app.runInTerminal
                        });
                    }
                    appLauncher.loadedCount = endIndex;
                }
            }

            function updateFilteredApps() {
                if (searchText.length > 0) {
                    AppSearch.searchApps(searchText);
                } else {
                    AppSearch.searchApps("");
                }
            }

            property var searchResultsList: AppSearch.searchResults
            onSearchResultsListChanged: {
                appLauncher.filteredApps = AppSearch.searchResults;
            }

            onFilteredAppsChanged: {
                resultsList.enableScrollAnimation = false;
                resultsList.contentY = 0;
                if (appLauncher.searchText.length > 0) {
                    GlobalStates.launcherSelectedIndex = 0;
                    appLauncher.selectedIndex = 0;
                    resultsList.currentIndex = 0;
                }
                updateAppsModel();
                Qt.callLater(() => {
                    resultsList.enableScrollAnimation = true;
                });
            }

            function updateAppsModel() {
                incrementalLoader.stop();
                
                let newApps = filteredApps;
                appLauncher.pendingApps = newApps;

                appsById = {};
                for (let i = 0; i < newApps.length; i++) {
                    appsById[newApps[i].id] = newApps[i];
                }

                appsModel.clear();
                
                let loadAll = (appLauncher.searchText.length > 0) || (newApps.length <= 100);
                let initialBatch = loadAll ? newApps.length : Math.min(appLauncher.batchSize, newApps.length);
                for (let i = 0; i < initialBatch; i++) {
                    let app = newApps[i];
                    appsModel.append({
                        appId: app.id,
                        appName: app.name,
                        appIcon: app.icon,
                        appComment: app.comment,
                        appExecString: app.execString,
                        appCategories: app.categories,
                        appRunInTerminal: app.runInTerminal
                    });
                }
                
                appLauncher.loadedCount = initialBatch;
                
                if (appLauncher.loadedCount < newApps.length) {
                    incrementalLoader.start();
                }
            }

            function executeApp(appId) {
                let app = appsById[appId];
                if (app && app.execute) {
                    app.execute();
                    UsageTracker.recordUsage(appId);
                    GlobalStates.commandPaletteVisible = false;
                }
            }

            ListModel {
                id: appsModel
            }

            Component.onCompleted: {
                updateFilteredApps();
                updateAppsModel();
                focusSearchInput();
                
                UsageTracker.usageDataReady.connect(() => {
                    AppSearch.invalidateCache();
                    updateFilteredApps();
                });
            }

            onSearchTextChanged: {
                if (searchText.length > 0) {
                    GlobalStates.launcherSelectedIndex = 0;
                    appLauncher.selectedIndex = 0;
                    resultsList.currentIndex = 0;
                } else {
                    GlobalStates.launcherSelectedIndex = -1;
                    appLauncher.selectedIndex = -1;
                    resultsList.currentIndex = -1;
                }
                updateFilteredApps();
            }

            onSelectedIndexChanged: {
                if (selectedIndex === -1 && resultsList.count > 0) {
                    resultsList.contentY = 0;
                }

                if (expandedItemIndex >= 0 && selectedIndex !== expandedItemIndex) {
                    expandedItemIndex = -1;
                    selectedOptionIndex = 0;
                    keyboardNavigation = false;
                }
            }

            function clearSearch() {
                GlobalStates.clearLauncherState();
                searchInput.clear();
                searchInput.focusInput();
            }

            function focusSearchInput() {
                searchInput.focusInput();
            }

            function adjustScrollForExpandedItem(index) {
                if (index < 0 || index >= appsModel.count)
                    return;

                var itemY = 0;
                for (var i = 0; i < index; i++) {
                    itemY += 48;
                }

                var listHeight = 36 * 3;
                var expandedHeight = 48 + 4 + listHeight + 8;

                var maxContentY = Math.max(0, resultsList.contentHeight - resultsList.height);

                var viewportTop = resultsList.contentY;
                var viewportBottom = viewportTop + resultsList.height;

                var itemBottom = itemY + expandedHeight;

                if (itemY < viewportTop) {
                    resultsList.contentY = itemY;
                } else if (itemBottom > viewportBottom) {
                    resultsList.contentY = Math.min(itemBottom - resultsList.height, maxContentY);
                }
            }

            Behavior on height {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            Item {
                id: mainLayout
                anchors.fill: parent

                SearchInput {
                    id: searchInput
                    width: parent.width
                    anchors.top: parent.top
                    height: root.showSearch ? implicitHeight : 0
                    visible: root.showSearch
                    text: GlobalStates.launcherSearchText
                    placeholderText: "Search applications..."
                    iconText: ""

                    onSearchTextChanged: text => {
                        GlobalStates.launcherSearchText = text;
                        appLauncher.searchText = text;

                        resultsList.enableScrollAnimation = false;

                        if (text.length > 0) {
                            GlobalStates.launcherSelectedIndex = 0;
                            appLauncher.selectedIndex = 0;
                            resultsList.currentIndex = 0;

                            resultsList.contentY = 0;
                        } else {
                            GlobalStates.launcherSelectedIndex = -1;
                            appLauncher.selectedIndex = -1;
                            resultsList.currentIndex = -1;

                            resultsList.contentY = 0;
                        }

                        Qt.callLater(() => {
                            resultsList.enableScrollAnimation = true;
                        });
                    }

                    onAccepted: {
                        if (appLauncher.expandedItemIndex >= 0) {
                            let selectedApp = appsModel.get(appLauncher.expandedItemIndex);
                            if (selectedApp) {
                                let options = [function () {
                                        appLauncher.executeApp(selectedApp.appId);
                                        GlobalStates.commandPaletteVisible = false;
                                    }, function () {
                                        TaskbarApps.togglePin(selectedApp.appId);
                                        appLauncher.expandedItemIndex = -1;
                                    }, function () {
                                        let desktopDir = Quickshell.env("XDG_DESKTOP_DIR") || Quickshell.env("HOME") + "/Desktop";
                                        let timestamp = Date.now();
                                        let fileName = selectedApp.appId + "-" + timestamp + ".desktop";
                                        let filePath = desktopDir + "/" + fileName;

                                        let desktopContent = "[Desktop Entry]\n" + "Version=1.0\n" + "Type=Application\n" + "Name=" + selectedApp.appName + "\n" + "Exec=" + selectedApp.appExecString + "\n" + "Icon=" + selectedApp.appIcon + "\n" + (selectedApp.appComment ? "Comment=" + selectedApp.appComment + "\n" : "") + (selectedApp.appCategories.length > 0 ? "Categories=" + selectedApp.appCategories.join(";") + ";\n" : "") + (selectedApp.appRunInTerminal ? "Terminal=true\n" : "Terminal=false\n");

                                        let writeCmd = "printf '%s' '" + desktopContent.replace(/'/g, "'\\''") + "' > \"" + filePath + "\" && chmod 755 \"" + filePath + "\" && gio set \"" + filePath + "\" metadata::trusted true";
                                        copyProcess.command = ["sh", "-c", writeCmd];
                                        copyProcess.running = true;
                                        appLauncher.expandedItemIndex = -1;
                                    }];

                                if (appLauncher.selectedOptionIndex >= 0 && appLauncher.selectedOptionIndex < options.length) {
                                    options[appLauncher.selectedOptionIndex]();
                                }
                            }
                        } else {
                            let targetIdx = appLauncher.selectedIndex >= 0 ? appLauncher.selectedIndex : 0;
                            if (targetIdx < appsModel.count) {
                                let selectedApp = appsModel.get(targetIdx);
                                if (selectedApp) {
                                    appLauncher.executeApp(selectedApp.appId);
                                    GlobalStates.commandPaletteVisible = false;
                                }
                            } else if (appLauncher.filteredApps.length > 0) {
                                let fallbackApp = appLauncher.filteredApps[0];
                                if (fallbackApp) {
                                    appLauncher.executeApp(fallbackApp.id);
                                    GlobalStates.commandPaletteVisible = false;
                                }
                            }
                        }
                    }

                    onShiftAccepted: {
                        if (appLauncher.selectedIndex >= 0 && appLauncher.selectedIndex < resultsList.count) {
                            if (appLauncher.expandedItemIndex === appLauncher.selectedIndex) {
                                appLauncher.expandedItemIndex = -1;
                                appLauncher.selectedOptionIndex = 0;
                                appLauncher.keyboardNavigation = false;
                            } else {
                                appLauncher.expandedItemIndex = appLauncher.selectedIndex;
                                appLauncher.selectedOptionIndex = 0;
                                appLauncher.keyboardNavigation = true;
                            }
                        }
                    }

                    onEscapePressed: {
                        if (appLauncher.expandedItemIndex >= 0) {
                            appLauncher.expandedItemIndex = -1;
                            appLauncher.selectedOptionIndex = 0;
                            appLauncher.keyboardNavigation = false;
                        } else {
                            GlobalStates.commandPaletteVisible = false;
                        }
                    }

                    onDownPressed: {
                        if (appLauncher.expandedItemIndex >= 0) {
                            if (appLauncher.selectedOptionIndex < 2) {
                                appLauncher.selectedOptionIndex++;
                                appLauncher.keyboardNavigation = true;
                            }
                        } else if (resultsList.count > 0) {
                            if (appLauncher.selectedIndex === -1) {
                                GlobalStates.launcherSelectedIndex = 0;
                                appLauncher.selectedIndex = 0;
                                resultsList.currentIndex = 0;
                            } else if (appLauncher.selectedIndex < resultsList.count - 1) {
                                GlobalStates.launcherSelectedIndex++;
                                appLauncher.selectedIndex++;
                                resultsList.currentIndex = appLauncher.selectedIndex;
                            }
                        }
                    }

                    onUpPressed: {
                        if (appLauncher.expandedItemIndex >= 0) {
                            if (appLauncher.selectedOptionIndex > 0) {
                                appLauncher.selectedOptionIndex--;
                                appLauncher.keyboardNavigation = true;
                            }
                        } else if (appLauncher.selectedIndex > 0) {
                            GlobalStates.launcherSelectedIndex--;
                            appLauncher.selectedIndex--;
                            resultsList.currentIndex = appLauncher.selectedIndex;
                        } else if (appLauncher.selectedIndex === 0 && appLauncher.searchText.length === 0) {
                            GlobalStates.launcherSelectedIndex = -1;
                            appLauncher.selectedIndex = -1;
                            resultsList.currentIndex = -1;
                        }
                    }

                    onPageDownPressed: {
                        if (resultsList.count > 0) {
                            let visibleItems = Math.floor(resultsList.height / 48);
                            let newIndex = Math.min(appLauncher.selectedIndex + visibleItems, resultsList.count - 1);
                            if (appLauncher.selectedIndex === -1) {
                                newIndex = Math.min(visibleItems - 1, resultsList.count - 1);
                            }
                            GlobalStates.launcherSelectedIndex = newIndex;
                            appLauncher.selectedIndex = newIndex;
                            resultsList.currentIndex = appLauncher.selectedIndex;
                        }
                    }

                    onPageUpPressed: {
                        if (resultsList.count > 0) {
                            let visibleItems = Math.floor(resultsList.height / 48);
                            let newIndex = Math.max(appLauncher.selectedIndex - visibleItems, 0);
                            if (appLauncher.selectedIndex === -1) {
                                newIndex = Math.max(resultsList.count - visibleItems, 0);
                            }
                            GlobalStates.launcherSelectedIndex = newIndex;
                            appLauncher.selectedIndex = newIndex;
                            resultsList.currentIndex = appLauncher.selectedIndex;
                        }
                    }

                    onHomePressed: {
                        if (resultsList.count > 0) {
                            GlobalStates.launcherSelectedIndex = 0;
                            appLauncher.selectedIndex = 0;
                            resultsList.currentIndex = 0;
                        }
                    }

                    onEndPressed: {
                        if (resultsList.count > 0) {
                            GlobalStates.launcherSelectedIndex = resultsList.count - 1;
                            appLauncher.selectedIndex = resultsList.count - 1;
                            resultsList.currentIndex = appLauncher.selectedIndex;
                        }
                    }
                }

                ListView {
                    id: resultsList
                    width: parent.width
                    anchors.top: searchInput.bottom
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 8
                    visible: true

                    clip: true
                    interactive: appLauncher.expandedItemIndex === -1
                    cacheBuffer: 96
                    reuseItems: true

                    property bool isScrolling: dragging || flicking

                    model: appsModel
                    currentIndex: appLauncher.selectedIndex

                    property bool enableScrollAnimation: true

                    Behavior on contentY {
                        enabled: Config.animDuration > 0 && resultsList.enableScrollAnimation && !resultsList.moving
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex !== appLauncher.selectedIndex) {
                            GlobalStates.launcherSelectedIndex = currentIndex;
                            appLauncher.selectedIndex = currentIndex;
                        }

                        if (currentIndex >= 0) {
                            var itemY = 0;
                            for (var i = 0; i < currentIndex && i < appsModel.count; i++) {
                                var itemHeight = 48;
                                if (i === appLauncher.expandedItemIndex) {
                                    var listHeight = 36 * 3;
                                    itemHeight = 48 + 4 + listHeight + 8;
                                }
                                itemY += itemHeight;
                            }

                            var currentItemHeight = 48;
                            if (currentIndex === appLauncher.expandedItemIndex) {
                                var listHeight = 36 * 3;
                                currentItemHeight = 48 + 4 + listHeight + 8;
                            }

                            var viewportTop = resultsList.contentY;
                            var viewportBottom = viewportTop + resultsList.height;

                            if (itemY < viewportTop) {
                                resultsList.contentY = itemY;
                            } else if (itemY + currentItemHeight > viewportBottom) {
                                resultsList.contentY = itemY + currentItemHeight - resultsList.height;
                            }
                        }
                    }

                    delegate: Rectangle {
                        required property string appId
                        required property string appName
                        required property string appIcon
                        required property string appComment
                        required property string appExecString
                        required property var appCategories
                        required property bool appRunInTerminal
                        required property int index

                        property bool isExpanded: index === appLauncher.expandedItemIndex

                        width: resultsList.width
                        height: {
                            let baseHeight = 48;
                            if (isExpanded) {
                                var listHeight = 36 * 3;
                                return baseHeight + 4 + listHeight + 8;
                            }
                            return baseHeight;
                        }
                        color: "transparent"

                        Behavior on height {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: isExpanded ? 48 : parent.height
                            hoverEnabled: !resultsList.isScrolling
                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                            onEntered: {
                                if (resultsList.isScrolling)
                                    return;
                                if (appLauncher.expandedItemIndex === -1) {
                                    GlobalStates.launcherSelectedIndex = index;
                                    appLauncher.selectedIndex = index;
                                    resultsList.currentIndex = index;
                                }
                            }

                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    if (!isExpanded) {
                                        appLauncher.executeApp(appId);
                                        GlobalStates.commandPaletteVisible = false;
                                    }
                                } else if (mouse.button === Qt.RightButton) {
                                    if (appLauncher.expandedItemIndex === index) {
                                        appLauncher.expandedItemIndex = -1;
                                        appLauncher.selectedOptionIndex = 0;
                                        appLauncher.keyboardNavigation = false;
                                        GlobalStates.launcherSelectedIndex = index;
                                        appLauncher.selectedIndex = index;
                                        resultsList.currentIndex = index;
                                    } else {
                                        appLauncher.expandedItemIndex = index;
                                        GlobalStates.launcherSelectedIndex = index;
                                        appLauncher.selectedIndex = index;
                                        resultsList.currentIndex = index;
                                        appLauncher.selectedOptionIndex = 0;
                                        appLauncher.keyboardNavigation = false;
                                    }
                                }
                            }
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            height: 32
                            spacing: 12

                            Item {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32

                                Image {
                                    id: appIconImage
                                    anchors.fill: parent
                                    source: "image://icon/" + appIcon
                                    fillMode: Image.PreserveAspectFit
                                    visible: !Config.tintIcons
                                    
                                    onStatusChanged: {
                                        if (status === Image.Error) {
                                            source = "image://icon/image-missing";
                                        }
                                    }
                                }

                                Tinted {
                                    anchors.fill: parent
                                    visible: Config.tintIcons
                                    sourceItem: Image {
                                        id: tintedAppIcon
                                        source: "image://icon/" + appIcon
                                        fillMode: Image.PreserveAspectFit
                                        
                                        onStatusChanged: {
                                            if (status === Image.Error) {
                                                source = "image://icon/image-missing";
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    width: parent.width
                                    text: appName
                                    color: {
                                        if (isExpanded) {
                                            return Styling.srItem("pane");
                                        } else if (appLauncher.selectedIndex === index) {
                                            return Styling.srItem("primary");
                                        } else {
                                            return Colors.overBackground;
                                        }
                                    }
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        enabled: Config.animDuration > 0
                                        ColorAnimation {
                                            duration: Config.animDuration / 2
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: appComment || ""
                                    color: {
                                        if (isExpanded) {
                                            return Styling.srItem("pane");
                                        } else if (appLauncher.selectedIndex === index) {
                                            return Styling.srItem("primary");
                                        } else {
                                            return Colors.outline;
                                        }
                                    }
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    elide: Text.ElideRight
                                    visible: text !== ""

                                    Behavior on color {
                                        enabled: Config.animDuration > 0
                                        ColorAnimation {
                                            duration: Config.animDuration / 2
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.bottomMargin: 8
                            spacing: 4
                            visible: isExpanded
                            opacity: isExpanded ? 1 : 0

                            Behavior on opacity {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutQuart
                                }
                            }

                            ClippingRectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36 * 3
                                color: Colors.background
                                radius: Styling.radius(0)

                                ListView {
                                    id: optionsListView
                                    anchors.fill: parent
                                    clip: true
                                    interactive: false
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: [
                                        {
                                            text: "Launch",
                                            icon: Icons.launch,
                                            highlightColor: Styling.srItem("overprimary"),
                                            textColor: Styling.srItem("primary"),
                                            action: function () {
                                                appLauncher.executeApp(appId);
                                                GlobalStates.commandPaletteVisible = false;
                                            }
                                        },
                                        {
                                            text: TaskbarApps.isPinned(appId) ? "Unpin from Dock" : "Pin to Dock",
                                            icon: TaskbarApps.isPinned(appId) ? Icons.unpin : Icons.pin,
                                            highlightColor: TaskbarApps.isPinned(appId) ? Colors.error : Colors.tertiary,
                                            textColor: TaskbarApps.isPinned(appId) ? Styling.srItem("error") : Styling.srItem("tertiary"),
                                            action: function () {
                                                TaskbarApps.togglePin(appId);
                                                appLauncher.expandedItemIndex = -1;
                                            }
                                        },
                                        {
                                            text: "Create Shortcut",
                                            icon: Icons.shortcut,
                                            highlightColor: Colors.secondary,
                                            textColor: Styling.srItem("secondary"),
                                            action: function () {
                                                let desktopDir = Quickshell.env("XDG_DESKTOP_DIR") || Quickshell.env("HOME") + "/Desktop";
                                                let timestamp = Date.now();
                                                let fileName = appId + "-" + timestamp + ".desktop";
                                                let filePath = desktopDir + "/" + fileName;

                                                let desktopContent = "[Desktop Entry]\n" + "Version=1.0\n" + "Type=Application\n" + "Name=" + selectedApp.appName + "\n" + "Exec=" + selectedApp.appExecString + "\n" + "Icon=" + selectedApp.appIcon + "\n" + (selectedApp.appComment ? "Comment=" + selectedApp.appComment + "\n" : "") + (selectedApp.appCategories.length > 0 ? "Categories=" + selectedApp.appCategories.join(";") + ";\n" : "") + (selectedApp.appRunInTerminal ? "Terminal=true\n" : "Terminal=false\n");

                                                let writeCmd = "printf '%s' '" + desktopContent.replace(/'/g, "'\\''") + "' > \"" + filePath + "\" && chmod 755 \"" + filePath + "\" && gio set \"" + filePath + "\" metadata::trusted true";
                                                copyProcess.command = ["sh", "-c", writeCmd];
                                                copyProcess.running = true;
                                                appLauncher.expandedItemIndex = -1;
                                            }
                                        }
                                    ]
                                    currentIndex: appLauncher.selectedOptionIndex
                                    highlightFollowsCurrentItem: true
                                    highlightRangeMode: ListView.ApplyRange
                                    preferredHighlightBegin: 0
                                    preferredHighlightEnd: height

                                    highlight: StyledRect {
                                        variant: {
                                            if (optionsListView.currentIndex >= 0 && optionsListView.currentIndex < optionsListView.count) {
                                                var item = optionsListView.model[optionsListView.currentIndex];
                                                if (item && item.highlightColor) {
                                                    if (item.highlightColor === Colors.secondary)
                                                        return "secondary";
                                                    if (item.highlightColor === Colors.tertiary)
                                                        return "tertiary";
                                                    if (item.highlightColor === Colors.error)
                                                        return "error";
                                                    return "primary";
                                                }
                                            }
                                            return "primary";
                                        }
                                        radius: Styling.radius(0)
                                        visible: optionsListView.currentIndex >= 0
                                        z: -1
                                    }

                                    highlightMoveDuration: Config.animDuration > 0 ? Config.animDuration / 2 : 0
                                    highlightMoveVelocity: -1
                                    highlightResizeDuration: Config.animDuration / 2
                                    highlightResizeVelocity: -1

                                    delegate: Item {
                                        required property var modelData
                                        required property int index

                                        width: optionsListView.width
                                        height: 36

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "transparent"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 8

                                                Text {
                                                    text: modelData && modelData.icon ? modelData.icon : ""
                                                    font.family: Icons.font
                                                    font.pixelSize: 14
                                                    font.weight: Font.Bold
                                                    textFormat: Text.RichText
                                                    color: {
                                                        if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                                                            return modelData.textColor;
                                                        }
                                                        return Colors.overSurface;
                                                    }

                                                    Behavior on color {
                                                        enabled: Config.animDuration > 0
                                                        ColorAnimation {
                                                            duration: Config.animDuration / 2
                                                            easing.type: Easing.OutQuart
                                                        }
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData && modelData.text ? modelData.text : ""
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Config.theme.fontSize
                                                    font.weight: optionsListView.currentIndex === index ? Font.Bold : Font.Normal
                                                    color: {
                                                        if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                                                            return modelData.textColor;
                                                        }
                                                        return Colors.overSurface;
                                                    }
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1

                                                    Behavior on color {
                                                        enabled: Config.animDuration > 0
                                                        ColorAnimation {
                                                            duration: Config.animDuration / 2
                                                            easing.type: Easing.OutQuart
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                onEntered: {
                                                    optionsListView.currentIndex = index;
                                                    appLauncher.selectedOptionIndex = index;
                                                    appLauncher.keyboardNavigation = false;
                                                }

                                                onClicked: {
                                                    if (modelData && modelData.action) {
                                                        modelData.action();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    highlight: Item {
                        width: resultsList.width
                        height: {
                            let baseHeight = 48;
                            if (resultsList.currentIndex === appLauncher.expandedItemIndex) {
                                var listHeight = 36 * 3;
                                return baseHeight + 4 + listHeight + 8;
                            }
                            return baseHeight;
                        }

                        y: {
                            var yPos = 0;
                            for (var i = 0; i < resultsList.currentIndex && i < appsModel.count; i++) {
                                var itemHeight = 48;
                                if (i === appLauncher.expandedItemIndex) {
                                    var listHeight = 36 * 3;
                                    itemHeight = 48 + 4 + listHeight + 8;
                                }
                                yPos += itemHeight;
                            }
                            return yPos;
                        }

                        Behavior on y {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration / 2
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on height {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        onHeightChanged: {
                            if (appLauncher.expandedItemIndex >= 0 && height > 48) {
                                Qt.callLater(() => {
                                    appLauncher.adjustScrollForExpandedItem(appLauncher.expandedItemIndex);
                                });
                            }
                        }

                        StyledRect {
                            anchors.fill: parent
                            variant: {
                                if (appLauncher.expandedItemIndex >= 0 && appLauncher.selectedIndex === appLauncher.expandedItemIndex) {
                                    return "pane";
                                } else {
                                    return "primary";
                                }
                            }
                            radius: Styling.radius(4)
                            visible: appLauncher.selectedIndex >= 0
                        }
                    }

                    highlightFollowsCurrentItem: false
                }
            }

            Process {
                id: copyProcess
                running: false

                onExited: function (code) {}
            }
        }

    }

    Component.onCompleted: {
        Qt.callLater(focusAppSearch);
    }
}
