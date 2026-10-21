import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.notch
import qs.modules.widgets.dashboard.widgets
import qs.modules.widgets.hydration
import qs.config

NotchAnimationBehavior {
    id: root
    focus: true

    property int leftPanelWidth: 0

    property var state: QtObject {
        property int currentTab: GlobalStates.dashboardCurrentTab
    }

    readonly property int tabCount: 3
    readonly property real nonAnimWidth: 570
    readonly property real nonAnimHeight: stack.currentItem ? stack.currentItem.implicitHeight : 210

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    isVisible: GlobalStates.dashboardOpen

    readonly property bool isMediaPlaying: {
        let p = MprisController.activePlayer;
        if (!p) return false;
        let playing = p.isPlaying === true;
        let hasTitle = p.trackTitle && p.trackTitle.trim() !== "" && p.trackTitle !== "Unknown Title" && p.trackTitle !== "Unknown Track" && p.trackTitle !== "Unknown";
        return playing && hasTitle;
    }

    onIsVisibleChanged: {
        if (isVisible) {
            let targetTab = 1;
            if (GlobalStates.dashboardCurrentTab === 2) {
                targetTab = 2;
            } else if (root.isMediaPlaying) {
                targetTab = 0;
            } else {
                targetTab = 1;
            }
            stack.navigateToTab(targetTab);
        }
    }

    Component.onCompleted: {
        let initialTab = GlobalStates.dashboardCurrentTab === 2 ? 2 : (root.isMediaPlaying ? 0 : 1);
        root.state.currentTab = initialTab;
        GlobalStates.dashboardCurrentTab = initialTab;
    }

    // sync external changes to current tab
    property int globalDashboardTab: GlobalStates.dashboardCurrentTab
    onGlobalDashboardTabChanged: {
        let target = GlobalStates.dashboardCurrentTab;
        if (target === 0 && !root.isMediaPlaying) {
            target = 1;
            GlobalStates.dashboardCurrentTab = 1;
        }
        if (target !== root.state.currentTab) {
            stack.navigateToTab(target);
        }
    }

    Keys.onEscapePressed: event => {
        Visibilities.setActiveModule("");
        event.accepted = true;
    }

    // main content stack
    Item {
        anchors.fill: parent
        clip: true

        StackView {
            id: stack
            anchors.fill: parent

            AppleNowPlayingTab {
                id: nowPlayingTabItem
                visible: false
                anchors.fill: parent
                onOpenMenu: stack.navigateToTab(1)
            }

            DashboardMenuView {
                id: menuTabItem
                visible: false
                anchors.fill: parent
                onRequestBack: stack.navigateToTab(0)
                onOpenHydration: stack.navigateToTab(2)
            }

            HydrationView {
                id: hydrationTabItem
                arrowPosition: "none"
                anchors.fill: parent
                visible: false
                onRequestBack: stack.navigateToTab(1)
            }

            readonly property var components: [nowPlayingTabItem, menuTabItem, hydrationTabItem]
            initialItem: components[GlobalStates.dashboardCurrentTab === 2 ? 2 : (root.isMediaPlaying ? 0 : 1)]

            function navigateToTab(index) {
                if (index >= 0 && index < components.length) {
                    if (index !== root.state.currentTab) {
                        let targetItem = components[index];
                        let direction = index > root.state.currentTab ? StackView.PushTransition : StackView.PopTransition;
                        stack.replace(targetItem, {}, direction);
                    }
                    root.state.currentTab = index;
                    GlobalStates.dashboardCurrentTab = index;
                }
            }

                pushEnter: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 180
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "x"
                        from: 20
                        to: 0
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                pushExit: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: 180
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "x"
                        from: 0
                        to: -20
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                popEnter: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 180
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "x"
                        from: -20
                        to: 0
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                popExit: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: 180
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "x"
                        from: 0
                        to: 20
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

    // keyboard shortcuts
    Shortcut {
        sequence: "Ctrl+Tab"
        enabled: GlobalStates.dashboardOpen
        onActivated: {
            let nextIndex = (root.state.currentTab + 1) % root.tabCount;
            stack.navigateToTab(nextIndex);
        }
    }

    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        enabled: GlobalStates.dashboardOpen
        onActivated: {
            let prevIndex = root.state.currentTab - 1;
            if (prevIndex < 0) {
                prevIndex = root.tabCount - 1;
            }
            stack.navigateToTab(prevIndex);
        }
    }

    property real animatedWidth: implicitWidth
    property real animatedHeight: implicitHeight

    width: animatedWidth
    height: animatedHeight

    onImplicitWidthChanged: animatedWidth = implicitWidth
    onImplicitHeightChanged: animatedHeight = implicitHeight

    Behavior on animatedWidth {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.25
        }
    }

    Behavior on animatedHeight {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.25
        }
    }
}
