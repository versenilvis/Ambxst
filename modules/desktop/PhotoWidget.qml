pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

BaseWidget {
    id: root

    required property var widgetData

    widgetId: widgetData.id
    title: "Photo"
    icon: Icons.image

    persistToWidgetService: false
    hasCardBackground: false
    cornerRadius: widgetData.cornerRadius ?? 20

    property string imagePath: widgetData.imagePath || ""
    property int minWidth: 80
    property int minHeight: 80
    property bool isResizing: false
    property bool isRatioLocked: false
    property bool isSymmetricResize: false
    property bool lockAspectRatio: widgetData.lockAspectRatio === true

    disableAnimations: isResizing

    property real savedWidth: Math.max(minWidth, widgetData.width ?? 240)
    property real savedHeight: Math.max(minHeight, widgetData.height ?? 240)

    savedX: widgetData.x ?? 32
    savedY: widgetData.y ?? 300
    x: savedX
    y: savedY
    width: savedWidth
    height: savedHeight
    locked: widgetData.locked === true

    function clampPositionToParent() {
        if (!root.parent || root.parent.width <= 0 || root.parent.height <= 0) return;
        root._clamping = true;
        const clampedW = Math.max(root.minWidth, Math.min(root.parent.width, root.savedWidth));
        const clampedH = Math.max(root.minHeight, Math.min(root.parent.height, root.savedHeight));
        root.width = clampedW;
        root.height = clampedH;
        const maxX = Math.max(0, root.parent.width - clampedW);
        const maxY = Math.max(0, root.parent.height - clampedH);
        root.x = Math.max(0, Math.min(maxX, root.savedX));
        root.y = Math.max(0, Math.min(maxY, root.savedY));
        root._clamping = false;
    }

    Component.onCompleted: {
        clampPositionToParent();
    }

    onPositionChangedByUser: (newX, newY) => {
        WidgetService.updatePhotoWidget(root.widgetId, { x: newX, y: newY });
    }

    onLockChangedByUser: isLocked => {
        WidgetService.updatePhotoWidget(root.widgetId, { locked: isLocked });
    }

    function syncFromData(item) {
        if (!item) return;
        root.savedX = item.x ?? 32;
        root.savedY = item.y ?? 300;
        root.savedWidth = Math.max(root.minWidth, item.width ?? 240);
        root.savedHeight = Math.max(root.minHeight, item.height ?? 240);
        root.locked = item.locked === true;
        root.lockAspectRatio = item.lockAspectRatio === true;
        root.imagePath = item.imagePath || "";
        root.cornerRadius = item.cornerRadius ?? 20;
        root.clampPositionToParent();
    }

    Connections {
        target: WidgetService
        function onPhotoWidgetUpdated(updatedId) {
            if (updatedId !== root.widgetId) return;
            const list = WidgetService.photoWidgets || [];
            for (let i = 0; i < list.length; i++) {
                if (list[i].id === root.widgetId) {
                    root.imagePath = list[i].imagePath || "";
                    root.cornerRadius = list[i].cornerRadius ?? 20;
                    break;
                }
            }
        }
        function onPhotoWidgetsRestored() {
            const list = WidgetService.photoWidgets || [];
            for (let i = 0; i < list.length; i++) {
                if (list[i].id === root.widgetId) {
                    root.syncFromData(list[i]);
                    break;
                }
            }
        }
    }

    function formatRatioLabel(w, h) {
        if (h <= 0) return "";
        const ratio = w / h;
        const presets = [
            { label: "1:1", val: 1.0 },
            { label: "16:9", val: 16 / 9 },
            { label: "9:16", val: 9 / 16 },
            { label: "4:3", val: 4 / 3 },
            { label: "3:4", val: 3 / 4 },
            { label: "21:9", val: 21 / 9 },
            { label: "3:2", val: 3 / 2 },
            { label: "2:3", val: 2 / 3 }
        ];
        for (let i = 0; i < presets.length; i++) {
            if (Math.abs(ratio - presets[i].val) < 0.04) {
                return presets[i].label;
            }
        }
        return ratio.toFixed(2) + ":1";
    }

    function setAspectRatio(ratioW, ratioH) {
        const parentH = root.parent ? root.parent.height : 1080;
        let nextH = Math.round(root.width * ratioH / ratioW);
        nextH = Math.max(root.minHeight, Math.min(parentH - root.y, nextH));
        root.height = nextH;
        root.savedHeight = nextH;
        WidgetService.updatePhotoWidget(root.widgetId, {
            x: root.x,
            y: root.y,
            width: root.width,
            height: root.height
        });
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: "#0c0c11"

        Image {
            id: photoImage
            anchors.fill: parent
            source: root.imagePath ? ("file://" + root.imagePath) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            cache: true
        }

        Text {
            anchors.centerIn: parent
            visible: root.imagePath.length === 0 || photoImage.status === Image.Error
            text: Icons.image
            font.family: Icons.font
            font.pixelSize: Math.min(root.width, root.height) * 0.25
            color: Colors.outline
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: "transparent"
        border.width: (root.isResizing || root.isSelected) ? 2 : 1
        border.color: {
            if (root.isResizing || root.isSelected) return Colors.primary;
            if (root.isHovered && !root.locked) return Qt.rgba(1, 1, 1, 0.28);
            return Qt.rgba(1, 1, 1, 0.08);
        }
    }

    // dimension and ratio pill shown while resizing
    Rectangle {
        anchors.centerIn: parent
        width: sizeLabel.implicitWidth + 20
        height: sizeLabel.implicitHeight + 10
        radius: height / 2
        color: "#cc0c0c11"
        border.color: Qt.rgba(1, 1, 1, 0.16)
        border.width: 1
        visible: root.isResizing
        z: 12

        Text {
            id: sizeLabel
            anchors.centerIn: parent
            text: Math.round(root.width) + " × " + Math.round(root.height) + " (" + root.formatRatioLabel(root.width, root.height) + (root.isRatioLocked ? " • locked" : "") + (root.isSymmetricResize ? " • sym" : "") + ")"
            font.family: Config.theme.font
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: Colors.overBackground
        }
    }

    // subtle bottom-right resize grip indicator
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: 12
        height: 12
        radius: 6
        color: Colors.primary
        opacity: (root.isHovered && !root.locked) || root.isResizing ? 0.85 : 0.0
        visible: !root.locked
        z: 10

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: 120 }
        }
    }

    component ResizeHandle: MouseArea {
        property bool resizeLeft: false
        property bool resizeRight: false
        property bool resizeTop: false
        property bool resizeBottom: false

        property point startMouse: Qt.point(0, 0)
        property real startX: 0
        property real startY: 0
        property real startW: 0
        property real startH: 0
        property real startRatio: 1.0

        enabled: !root.locked
        visible: !root.locked
        hoverEnabled: true
        preventStealing: true
        z: 15

        onPressed: mouse => {
            if (!root.parent) return;
            startMouse = mapToItem(root.parent, mouse.x, mouse.y);
            startX = root.x;
            startY = root.y;
            startW = root.width;
            startH = root.height;
            startRatio = startH > 0 ? (startW / startH) : 1.0;
            root.isResizing = true;
            root.isRatioLocked = root.lockAspectRatio || ((mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0) || ((Qt.application.keyboardModifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0);
            root.isSymmetricResize = ((mouse.modifiers & Qt.AltModifier) !== 0) || ((Qt.application.keyboardModifiers & Qt.AltModifier) !== 0);
        }

        onPositionChanged: mouse => {
            if (!pressed || !root.parent) return;
            const cur = mapToItem(root.parent, mouse.x, mouse.y);
            const dx = cur.x - startMouse.x;
            const dy = cur.y - startMouse.y;
            const maxParentW = root.parent.width > 0 ? root.parent.width : 1920;
            const maxParentH = root.parent.height > 0 ? root.parent.height : 1080;
            const keepRatio = root.lockAspectRatio || ((mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0) || ((Qt.application.keyboardModifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0);
            const keepCenter = ((mouse.modifiers & Qt.AltModifier) !== 0) || ((Qt.application.keyboardModifiers & Qt.AltModifier) !== 0);
            root.isRatioLocked = keepRatio;
            root.isSymmetricResize = keepCenter;

            const centerX = startX + startW / 2;
            const centerY = startY + startH / 2;
            const maxCenterW = Math.min(centerX, maxParentW - centerX) * 2;
            const maxCenterH = Math.min(centerY, maxParentH - centerY) * 2;
            const mult = keepCenter ? 2 : 1;

            if (keepRatio) {
                const horiz = resizeLeft || resizeRight;
                const vert = resizeTop || resizeBottom;
                const maxWBound = keepCenter ? maxCenterW : (resizeLeft ? (startX + startW) : (maxParentW - startX));
                const maxHBound = keepCenter ? maxCenterH : (resizeTop ? (startY + startH) : (maxParentH - startY));
                let nextX = startX;
                let nextY = startY;
                let nextW = startW;
                let nextH = startH;

                if (horiz && vert) {
                    const rawW = resizeRight ? (startW + mult * dx) : (startW - mult * dx);
                    const rawH = resizeBottom ? (startH + mult * dy) : (startH - mult * dy);
                    nextW = Math.abs(rawW - startW) / startW >= Math.abs(rawH - startH) / startH
                        ? rawW
                        : rawH * startRatio;
                    const minW = Math.max(root.minWidth, root.minHeight * startRatio);
                    const maxW = Math.min(maxWBound, maxHBound * startRatio);
                    nextW = Math.max(minW, Math.min(maxW, nextW));
                    nextH = nextW / startRatio;
                } else if (horiz) {
                    const rawW = resizeRight ? (startW + mult * dx) : (startW - mult * dx);
                    const minW = Math.max(root.minWidth, root.minHeight * startRatio);
                    const maxW = Math.min(maxWBound, (keepCenter ? maxCenterH : (maxParentH - startY)) * startRatio);
                    nextW = Math.max(minW, Math.min(maxW, rawW));
                    nextH = nextW / startRatio;
                } else if (vert) {
                    const rawH = resizeBottom ? (startH + mult * dy) : (startH - mult * dy);
                    const minH = Math.max(root.minHeight, root.minWidth / startRatio);
                    const maxH = Math.min(maxHBound, (keepCenter ? maxCenterW : (maxParentW - startX)) / startRatio);
                    nextH = Math.max(minH, Math.min(maxH, rawH));
                    nextW = nextH * startRatio;
                }

                if (keepCenter) {
                    if (horiz) nextX = centerX - nextW / 2;
                    if (vert) nextY = centerY - nextH / 2;
                } else {
                    if (resizeLeft) nextX = startX + (startW - nextW);
                    if (resizeTop) nextY = startY + (startH - nextH);
                }

                const snapped = WidgetService.computeSnapForResize(
                    root.widgetId, nextX, nextY, nextW, nextH,
                    keepCenter || resizeLeft, keepCenter || resizeRight, keepCenter || resizeTop, keepCenter || resizeBottom, 6
                );
                if (!keepCenter) {
                    if (snapped.width !== nextW && horiz) {
                        const minW = Math.max(root.minWidth, root.minHeight * startRatio);
                        const maxW = Math.min(maxWBound, maxHBound * startRatio);
                        nextW = Math.max(minW, Math.min(maxW, snapped.width));
                        nextH = nextW / startRatio;
                    } else if (snapped.height !== nextH && vert) {
                        const minH = Math.max(root.minHeight, root.minWidth / startRatio);
                        const maxH = Math.min(maxHBound, maxWBound / startRatio);
                        nextH = Math.max(minH, Math.min(maxH, snapped.height));
                        nextW = nextH * startRatio;
                    }
                    if (resizeLeft) nextX = startX + (startW - nextW);
                    if (resizeTop) nextY = startY + (startH - nextH);
                }
                root.x = Math.round(nextX);
                root.y = Math.round(nextY);
                root.width = Math.round(nextW);
                root.height = Math.round(nextH);
                return;
            }

            let nextX = startX;
            let nextY = startY;
            let nextW = startW;
            let nextH = startH;

            if (keepCenter) {
                if (resizeRight || resizeLeft) {
                    const rawW = resizeRight ? (startW + 2 * dx) : (startW - 2 * dx);
                    nextW = Math.max(root.minWidth, Math.min(maxCenterW, rawW));
                    nextX = centerX - nextW / 2;
                }
                if (resizeBottom || resizeTop) {
                    const rawH = resizeBottom ? (startH + 2 * dy) : (startH - 2 * dy);
                    nextH = Math.max(root.minHeight, Math.min(maxCenterH, rawH));
                    nextY = centerY - nextH / 2;
                }
                root.x = Math.round(nextX);
                root.y = Math.round(nextY);
                root.width = Math.round(nextW);
                root.height = Math.round(nextH);
                return;
            }

            if (resizeRight) {
                nextW = Math.max(root.minWidth, Math.min(maxParentW - startX, startW + dx));
            } else if (resizeLeft) {
                nextW = Math.max(root.minWidth, Math.min(startX + startW, startW - dx));
                nextX = startX + (startW - nextW);
            }

            if (resizeBottom) {
                nextH = Math.max(root.minHeight, Math.min(maxParentH - startY, startH + dy));
            } else if (resizeTop) {
                nextH = Math.max(root.minHeight, Math.min(startY + startH, startH - dy));
                nextY = startY + (startH - nextH);
            }

            const snapped = WidgetService.computeSnapForResize(
                root.widgetId, nextX, nextY, nextW, nextH,
                resizeLeft, resizeRight, resizeTop, resizeBottom, 6
            );
            root.x = Math.round(snapped.x);
            root.y = Math.round(snapped.y);
            root.width = Math.round(Math.max(root.minWidth, snapped.width));
            root.height = Math.round(Math.max(root.minHeight, snapped.height));
        }

        onReleased: {
            if (root.isResizing) {
                root.isResizing = false;
                root.isRatioLocked = false;
                root.isSymmetricResize = false;
                root.savedX = root.x;
                root.savedY = root.y;
                root.savedWidth = root.width;
                root.savedHeight = root.height;
                WidgetService.updatePhotoWidget(root.widgetId, {
                    x: root.x,
                    y: root.y,
                    width: root.width,
                    height: root.height
                });
            }
        }
    }

    // edge resize handles
    ResizeHandle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        width: 8
        resizeLeft: true
        cursorShape: Qt.SizeHorCursor
    }

    ResizeHandle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        width: 8
        resizeRight: true
        cursorShape: Qt.SizeHorCursor
    }

    ResizeHandle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 8
        resizeTop: true
        cursorShape: Qt.SizeVerCursor
    }

    ResizeHandle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 8
        resizeBottom: true
        cursorShape: Qt.SizeVerCursor
    }

    // corner resize handles
    ResizeHandle {
        anchors.left: parent.left
        anchors.top: parent.top
        width: 14
        height: 14
        resizeLeft: true
        resizeTop: true
        cursorShape: Qt.SizeFDiagCursor
    }

    ResizeHandle {
        anchors.right: parent.right
        anchors.top: parent.top
        width: 14
        height: 14
        resizeRight: true
        resizeTop: true
        cursorShape: Qt.SizeBDiagCursor
    }

    ResizeHandle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 14
        height: 14
        resizeLeft: true
        resizeBottom: true
        cursorShape: Qt.SizeBDiagCursor
    }

    ResizeHandle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 16
        height: 16
        resizeRight: true
        resizeBottom: true
        cursorShape: Qt.SizeFDiagCursor
    }

    function openWidgetMenu() {
        let items = [
            {
                text: "Change Image...",
                icon: Icons.image,
                isSeparator: false,
                onTriggered: function() {
                    WidgetService.browseAndChangePhotoImage(root.widgetId);
                }
            },
            {
                isSeparator: true,
                text: ""
            },
            {
                text: "Ratio 1:1 (Square)",
                icon: Icons.crop,
                isSeparator: false,
                onTriggered: function() { root.setAspectRatio(1, 1); }
            },
            {
                text: "Ratio 16:9 (Wide)",
                icon: Icons.crop,
                isSeparator: false,
                onTriggered: function() { root.setAspectRatio(16, 9); }
            },
            {
                text: "Ratio 4:3",
                icon: Icons.crop,
                isSeparator: false,
                onTriggered: function() { root.setAspectRatio(4, 3); }
            },
            {
                text: "Ratio 9:16 (Tall)",
                icon: Icons.crop,
                isSeparator: false,
                onTriggered: function() { root.setAspectRatio(9, 16); }
            },
            {
                isSeparator: true,
                text: ""
            },
            {
                text: root.lockAspectRatio ? "Unlock Aspect Ratio" : "Lock Aspect Ratio",
                icon: Icons.crop,
                isSeparator: false,
                onTriggered: function() {
                    root.lockAspectRatio = !root.lockAspectRatio;
                    WidgetService.updatePhotoWidget(root.widgetId, { lockAspectRatio: root.lockAspectRatio });
                }
            },
            {
                text: root.locked ? "Unlock Position & Size" : "Lock Position & Size",
                icon: Icons.lock,
                isSeparator: false,
                onTriggered: function() {
                    root.locked = !root.locked;
                    WidgetService.updatePhotoWidget(root.widgetId, { locked: root.locked });
                }
            },
            {
                text: "Remove Photo Widget",
                icon: Icons.trash,
                textColor: Colors.overError,
                highlightColor: Colors.error,
                isSeparator: false,
                onTriggered: function() {
                    WidgetService.removePhotoWidget(root.widgetId);
                }
            }
        ];
        Visibilities.contextMenu.openCustomMenu(items, 210);
    }
}
