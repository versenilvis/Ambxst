import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

PanelWindow {
    id: screenshotPopup
    
    required property var targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (screenshotPopup.visible && state === "active") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: state === "active"
    exclusionMode: ExclusionMode.Ignore

    property string state: "idle"
    property string currentMode: GlobalStates.screenshotCaptureMode || "region"
    property int timerSeconds: 0
    property bool countdownActive: false
    property int remainingCountdown: 0
    property string currentRatio: "Free"
    property int ratioW: 16
    property int ratioH: 9
    property var activeWindows: []

    property Process colorPickerProcess: Process {
        id: colorPickerProcess
        command: ["bash", "-c", "hyprpicker -a -n 2>/dev/null || true"]
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            screenshotPopup.remainingCountdown--;
            if (screenshotPopup.remainingCountdown <= 0) {
                countdownTimer.stop();
                screenshotPopup.countdownActive = false;
                screenshotPopup.performCapture();
            }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.screenshotToolVisible) {
            open();
        }
    }

    function getModes() {
        return [
            {
                name: "region",
                icon: Icons.regionScreenshot,
                text: "Area",
                tooltip: "Area (Select Region)",
                active: screenshotPopup.currentMode === "region"
            },
            {
                name: "window",
                icon: Icons.windowScreenshot,
                text: "Window",
                tooltip: "Window (Select Window)",
                active: screenshotPopup.currentMode === "window"
            },
            {
                name: "screen",
                icon: Icons.fullScreenshot,
                text: "Screen",
                tooltip: "Fullscreen",
                active: screenshotPopup.currentMode === "screen"
            },
            {
                name: "element",
                icon: Icons.cursor,
                text: "Element",
                tooltip: "Element",
                active: screenshotPopup.currentMode === "element"
            },
            {
                type: "separator"
            },
            {
                name: "text",
                icon: Icons.textT,
                text: "OCR",
                tooltip: "Text OCR (Vietnamese & English)",
                active: screenshotPopup.currentMode === "text"
            },
            {
                name: "color",
                icon: Icons.picker,
                text: "Color",
                tooltip: "Color Picker",
                active: false
            },
            {
                type: "separator"
            },
            {
                name: "timer",
                icon: Icons.timer,
                text: screenshotPopup.timerSeconds > 0 ? (screenshotPopup.timerSeconds + "s") : "Timer",
                tooltip: screenshotPopup.timerSeconds > 0 ? ("Timer: " + screenshotPopup.timerSeconds + "s") : "Timer: Off",
                active: screenshotPopup.timerSeconds > 0
            },
            {
                name: "ratio",
                icon: Icons.crop,
                text: screenshotPopup.currentRatio !== "Free" ? screenshotPopup.currentRatio : "Ratio",
                tooltip: "Aspect Ratio: " + screenshotPopup.currentRatio,
                active: screenshotPopup.currentRatio !== "Free"
            },
            {
                name: "watch",
                icon: Icons.xeyes,
                text: "Pin",
                tooltip: "Pin to Screen",
                active: screenshotPopup.currentMode === "watch"
            },
            {
                name: "record",
                icon: Icons.recordScreen,
                text: "Record",
                tooltip: "Screen Record",
                active: false
            },
            {
                type: "separator"
            },
            {
                name: "capture",
                icon: Icons.camera,
                text: "Capture",
                tooltip: "Take Screenshot (Enter / Space)",
                variant: "primary",
                active: false
            }
        ];
    }

    function open() {
        screenshotPopup.currentMode = GlobalStates.screenshotCaptureMode || "region";
        screenshotPopup.state = "loading";
        screenshotPopup.countdownActive = false;
        screenshotPopup.remainingCountdown = 0;
        Screenshot.freezeScreen();
    }

    function close() {
        countdownTimer.stop();
        screenshotPopup.countdownActive = false;
        screenshotPopup.state = "idle";
        GlobalStates.screenshotToolVisible = false;
    }

    function selectMode(name) {
        screenshotPopup.currentMode = name;
        GlobalStates.screenshotCaptureMode = name;
        if (name === "screen") {
            Screenshot.selectionW = 0;
            Screenshot.selectionH = 0;
        }
    }

    function cycleTimer() {
        if (timerSeconds === 0) timerSeconds = 3;
        else if (timerSeconds === 3) timerSeconds = 5;
        else if (timerSeconds === 5) timerSeconds = 10;
        else timerSeconds = 0;
    }

    function cycleRatio() {
        const ratios = [
            { name: "Free", w: 0, h: 0 },
            { name: "16:9", w: 16, h: 9 },
            { name: "4:3", w: 4, h: 3 },
            { name: "1:1", w: 1, h: 1 },
            { name: "3:2", w: 3, h: 2 },
            { name: "21:9", w: 21, h: 9 }
        ];
        let idx = ratios.findIndex(r => r.name === currentRatio);
        let next = (idx + 1) % ratios.length;
        currentRatio = ratios[next].name;
        ratioW = ratios[next].w;
        ratioH = ratios[next].h;
        if (Screenshot.selectionW > 0 && currentRatio !== "Free") {
            Screenshot.selectionH = Math.round(Screenshot.selectionW * ratioH / ratioW);
        }
    }

    function triggerRecord() {
        close();
        GlobalStates.screenRecordToolVisible = true;
    }

    function triggerColorPicker() {
        close();
        colorPickerProcess.running = true;
    }

    function executeCapture() {
        if (timerSeconds > 0 && !countdownActive) {
            startCountdown();
            return;
        }
        performCapture();
    }

    function startCountdown() {
        screenshotPopup.remainingCountdown = timerSeconds;
        screenshotPopup.countdownActive = true;
        countdownTimer.restart();
    }

    function performCapture() {
        if (currentMode === "text") {
            Screenshot.captureMode = "ocr";
            if (Screenshot.selectionW > 5 && Screenshot.selectionH > 5) {
                Screenshot.processRegion(Screenshot.selectionX, Screenshot.selectionY, Screenshot.selectionW, Screenshot.selectionH);
            } else {
                Screenshot.processMonitorScreen(screenshotPopup.targetScreen.name);
            }
            close();
        } else if (currentMode === "screen") {
            Screenshot.processMonitorScreen(screenshotPopup.targetScreen.name);
            close();
        } else if (currentMode === "region" || currentMode === "watch" || currentMode === "scrolling") {
            if (Screenshot.selectionW > 5 && Screenshot.selectionH > 5) {
                Screenshot.processRegion(Screenshot.selectionX, Screenshot.selectionY, Screenshot.selectionW, Screenshot.selectionH);
                close();
            } else {
                Screenshot.processMonitorScreen(screenshotPopup.targetScreen.name);
                close();
            }
        } else if (currentMode === "window" || currentMode === "element") {
            if (screenshotPopup.activeWindows.length > 0) {
                var win = screenshotPopup.activeWindows[0];
                Screenshot.processRegion(win.at[0], win.at[1], win.size[0], win.size[1]);
                close();
            } else {
                Screenshot.processMonitorScreen(screenshotPopup.targetScreen.name);
                close();
            }
        }
    }

    Connections {
        ignoreUnknownSignals: true
        enabled: Screenshot != null
        target: Screenshot
        function onMonitorScreenshotReady(monitorName, path) {
            if (monitorName === screenshotPopup.targetScreen.name) {
                previewImage.source = "";
                previewImage.source = "file://" + path;
                screenshotPopup.state = "active";
                Screenshot.selectionW = 0;
                Screenshot.selectionH = 0;
                mainFocusScope.forceActiveFocus();
                if (modeGrid) {
                    let modes = screenshotPopup.getModes();
                    for (let i = 0; i < modes.length; i++) {
                        if (modes[i].name === screenshotPopup.currentMode) {
                            modeGrid.currentIndex = i;
                            break;
                        }
                    }
                    modeGrid.forceActiveFocus();
                }
            }
        }
        function onWindowListReady(windows) {
            screenshotPopup.activeWindows = windows;
        }
        function onErrorOccurred(msg) {
            console.warn("Screenshot Error:", msg);
            close();
        }
    }

    mask: Region {
        item: screenshotPopup.visible ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [screenshotPopup]
        active: screenshotPopup.visible && screenshotPopup.state === "active"
    }

    FocusScope {
        id: mainFocusScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: close()
        Keys.onReturnPressed: executeCapture()
        Keys.onSpacePressed: executeCapture()

        // 1. Frozen screen background image
        Item {
            anchors.fill: parent
            clip: true
            
            Image {
                id: previewImage
                fillMode: Image.Stretch
                anchors.fill: parent
                visible: screenshotPopup.state === "active"
            }
        }

        // 2. Dimmer overlay
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: screenshotPopup.state === "active" ? 0.35 : 0
            visible: screenshotPopup.state === "active" && screenshotPopup.currentMode !== "screen"
        }

        // 3. Window Selection
        Item {
            anchors.fill: parent
            visible: screenshotPopup.state === "active" && (screenshotPopup.currentMode === "window" || screenshotPopup.currentMode === "element")

            Repeater {
                model: screenshotPopup.activeWindows
                delegate: Rectangle {
                    x: modelData.at[0] - screenshotPopup.screen.x
                    y: modelData.at[1] - screenshotPopup.screen.y
                    width: modelData.size[0]
                    height: modelData.size[1]
                    
                    color: "transparent"
                    border.color: hoverHandler.hovered ? Styling.srItem("overprimary") : "transparent"
                    border.width: 2

                    Rectangle {
                        anchors.fill: parent
                        color: Styling.srItem("overprimary")
                        opacity: hoverHandler.hovered ? 0.2 : 0
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    TapHandler {
                        onTapped: {
                            if (screenshotPopup.currentMode === "text") {
                                Screenshot.captureMode = "ocr";
                            }
                            Screenshot.processRegion(modelData.at[0], modelData.at[1], modelData.size[0], modelData.size[1]);
                            close();
                        }
                    }
                }
            }
        }

        // 4. Region Selection Area
        MouseArea {
            id: regionArea
            anchors.fill: parent
            enabled: screenshotPopup.state === "active" && (screenshotPopup.currentMode === "region" || screenshotPopup.currentMode === "text" || screenshotPopup.currentMode === "watch" || screenshotPopup.currentMode === "scrolling" || screenshotPopup.currentMode === "screen")
            hoverEnabled: true
            cursorShape: screenshotPopup.currentMode === "screen" ? Qt.ArrowCursor : Qt.CrossCursor

            property point startPointGlobal: Qt.point(0, 0)
            property bool selecting: false

            onPressed: mouse => {
                if (screenshotPopup.currentMode === "screen") return;

                var globalX = mouse.x + screenshotPopup.screen.x;
                var globalY = mouse.y + screenshotPopup.screen.y;

                startPointGlobal = Qt.point(globalX, globalY);
                
                Screenshot.selectionX = globalX;
                Screenshot.selectionY = globalY;
                Screenshot.selectionW = 0;
                Screenshot.selectionH = 0;
                selecting = true;
            }

            onClicked: {
                if (screenshotPopup.currentMode === "screen") {
                    screenshotPopup.executeCapture();
                }
            }

            onPositionChanged: mouse => {
                if (!selecting) return;
                
                var currentGlobalX = mouse.x + screenshotPopup.screen.x;
                var currentGlobalY = mouse.y + screenshotPopup.screen.y;

                var x = Math.min(startPointGlobal.x, currentGlobalX);
                var y = Math.min(startPointGlobal.y, currentGlobalY);
                var w = Math.abs(startPointGlobal.x - currentGlobalX);
                var h = Math.abs(startPointGlobal.y - currentGlobalY);

                if (screenshotPopup.currentRatio !== "Free" && screenshotPopup.ratioW > 0 && screenshotPopup.ratioH > 0) {
                    h = Math.round(w * screenshotPopup.ratioH / screenshotPopup.ratioW);
                    if (currentGlobalY < startPointGlobal.y) {
                        y = startPointGlobal.y - h;
                    }
                }

                Screenshot.selectionX = x;
                Screenshot.selectionY = y;
                Screenshot.selectionW = w;
                Screenshot.selectionH = h;
            }

            onReleased: {
                if (!selecting) return;
                selecting = false;
                
                if (Screenshot.selectionW > 5 && Screenshot.selectionH > 5) {
                    if (screenshotPopup.timerSeconds > 0) {
                        screenshotPopup.startCountdown();
                    } else {
                        screenshotPopup.executeCapture();
                    }
                }
            }
        }

        // Visual Selection Rectangle
        Rectangle {
            id: selectionRect
            visible: screenshotPopup.state === "active" && (screenshotPopup.currentMode === "region" || screenshotPopup.currentMode === "text" || screenshotPopup.currentMode === "watch" || screenshotPopup.currentMode === "scrolling") && Screenshot.selectionW > 2
            
            x: Screenshot.selectionX - screenshotPopup.screen.x
            y: Screenshot.selectionY - screenshotPopup.screen.y
            width: Screenshot.selectionW
            height: Screenshot.selectionH
            
            color: "transparent"
            border.color: Styling.srItem("overprimary")
            border.width: 2

            Rectangle {
                anchors.fill: parent
                color: Styling.srItem("overprimary")
                opacity: 0.18
            }

            // Dimension Badge in Ambxst style
            StyledRect {
                variant: "common"
                visible: parent.width > 30 && parent.height > 20
                anchors.bottom: parent.top
                anchors.bottomMargin: 6
                anchors.left: parent.left
                height: 24
                width: dimLabel.implicitWidth + 16
                radius: Styling.radius(4)
                enableShadow: true

                Text {
                    id: dimLabel
                    anchors.centerIn: parent
                    text: `${Math.round(selectionRect.width)} × ${Math.round(selectionRect.height)}` + (screenshotPopup.currentRatio !== "Free" ? ` (${screenshotPopup.currentRatio})` : "")
                    color: Colors.overBackground
                    font.family: Config.defaultFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        // Countdown Display in Ambxst style
        StyledRect {
            variant: "common"
            visible: screenshotPopup.countdownActive
            anchors.centerIn: parent
            width: 100
            height: 100
            radius: Styling.radius(20)
            enableShadow: true
            z: 300

            Text {
                anchors.centerIn: parent
                text: String(screenshotPopup.remainingCountdown)
                font.family: Config.defaultFont
                font.pixelSize: 48
                font.weight: Font.Bold
                color: Styling.srItem("primary")
            }
        }

        // 5. Controls UI in native Ambxst style
        Rectangle {
            id: controlsBar
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 48
            width: modeGrid.width + 24
            height: modeGrid.height + 16
            radius: Styling.radius(20)
            color: Colors.background
            border.color: Colors.surface
            border.width: 1
            visible: screenshotPopup.state === "active" && !screenshotPopup.countdownActive
            z: 200

            layer.enabled: true
            layer.effect: Shadow {}

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true 
            }

            ActionGrid {
                id: modeGrid
                anchors.centerIn: parent
                actions: screenshotPopup.getModes()
                textPosition: "bottom"
                buttonWidth: 54
                buttonHeight: 52
                iconSize: 20
                spacing: 4
                highlightRadius: Styling.radius(8)

                onActionTriggered: action => {
                    if (action.name === "timer") {
                        screenshotPopup.cycleTimer();
                    } else if (action.name === "ratio") {
                        screenshotPopup.cycleRatio();
                    } else if (action.name === "color") {
                        screenshotPopup.triggerColorPicker();
                    } else if (action.name === "record") {
                        screenshotPopup.triggerRecord();
                    } else if (action.name === "capture") {
                        screenshotPopup.executeCapture();
                    } else if (action.name === "watch") {
                        screenshotPopup.currentMode = "watch";
                        screenshotPopup.executeCapture();
                    } else {
                        screenshotPopup.selectMode(action.name);
                        if (action.name === "screen") {
                            screenshotPopup.executeCapture();
                        }
                    }
                }
            }
        }
    }
}
