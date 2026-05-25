import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.modules.globals
import qs.modules.theme
import qs.modules.components
import qs.modules.corners
import qs.modules.services
import qs.config

Item {
    id: notchContainer

    z: 1000

    property Component defaultViewComponent
    property Component notificationViewComponent
    property var stackView: stackViewInternal
    property bool isExpanded: stackViewInternal.depth > 1
    property bool isHovered: false

    // Screen-specific visibility properties passed from parent
    property var visibilities
    readonly property bool screenNotchOpen: visibilities ? (visibilities.dashboard || visibilities.powermenu || visibilities.tools) : false
    readonly property bool hasActiveNotifications: Notifications.popupList.length > 0
    property bool notificationExpanded: false

    onHasActiveNotificationsChanged: {
        if (hasActiveNotifications) {
            bounceAnimation.start()
        } else {
            triggerCollapseSpring()
        }
    }

    SequentialAnimation {
        id: bounceAnimation

        ScriptAction {
            script: {
                // stop any active physics simulation
                physicsTimer.stop()
                notchRect.scaleX = 1.0
                notchRect.scaleY = 1.0
                notchRect.translateY = 0.0
                notchRect.velScaleX = 0.0
                notchRect.velScaleY = 0.0
                notchRect.velTranslateY = 0.0
            }
        }

        // squash down
        ParallelAnimation {
            NumberAnimation {
                target: notchRect
                property: "scaleX"
                to: 1.22
                duration: 150
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: notchRect
                property: "scaleY"
                to: 0.75
                duration: 150
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: notchRect
                property: "translateY"
                to: 16
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        // return to baseline and start expanding (balloon outwards)
        ParallelAnimation {
            NumberAnimation {
                target: notchRect
                property: "scaleX"
                to: 1.08
                duration: 220
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: notchRect
                property: "scaleY"
                to: 1.08
                duration: 220
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: notchRect
                property: "translateY"
                to: 0
                duration: 220
                easing.type: Easing.OutQuad
            }

            ScriptAction {
                script: {
                    notchContainer.notificationExpanded = true
                }
            }
        }

        // shrink smaller than target size (jelly return phase 1)
        ParallelAnimation {
            NumberAnimation {
                target: notchRect
                property: "scaleX"
                to: 0.97
                duration: 180
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: notchRect
                property: "scaleY"
                to: 0.97
                duration: 180
                easing.type: Easing.OutQuad
            }
        }

        // bounce back outwards (jelly return phase 2)
        ParallelAnimation {
            NumberAnimation {
                target: notchRect
                property: "scaleX"
                to: 1.01
                duration: 150
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: notchRect
                property: "scaleY"
                to: 1.01
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        // settle to normal
        ParallelAnimation {
            NumberAnimation {
                target: notchRect
                property: "scaleX"
                to: 1.0
                duration: 150
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: notchRect
                property: "scaleY"
                to: 1.0
                duration: 150
                easing.type: Easing.OutQuad
            }
        }
    }

    function triggerCollapseSpring() {
        // stop any active animations
        bounceAnimation.stop()
        physicsTimer.stop()

        // trigger state collapse
        notchContainer.notificationExpanded = false

        // calculate width delta
        let prevW = notchRect.width
        let targetW = 180
        let diffW = targetW - prevW

        let intensity = 1.0

        // apply spring velocity impulses
        if (diffW < 0) {
            notchRect.velScaleX = (diffW * 0.024) * intensity
            notchRect.velScaleY = -(diffW * 0.016) * intensity
            notchRect.velTranslateY = Math.abs(diffW) * 2.0 * intensity
        }

        physicsTimer.start()
    }

    Timer {
        id: physicsTimer
        interval: 16
        repeat: true
        running: false

        onTriggered: {
            let dt = 0.016
            let tensionX = 60
            let frictionX = 7
            let tensionY = 60
            let frictionY = 7
            let tensionTransY = 190
            let frictionTransY = 18

            // scaleX spring solver
            let dispX = notchRect.scaleX - 1.0
            let forceX = -tensionX * dispX
            let dampX = -frictionX * notchRect.velScaleX
            let accelX = forceX + dampX
            notchRect.velScaleX += accelX * dt
            notchRect.scaleX += notchRect.velScaleX * dt

            // scaleY spring solver
            let dispY = notchRect.scaleY - 1.0
            let forceY = -tensionY * dispY
            let dampY = -frictionY * notchRect.velScaleY
            let accelY = forceY + dampY
            notchRect.velScaleY += accelY * dt
            notchRect.scaleY += notchRect.velScaleY * dt

            // translateY spring solver
            let dispTransY = notchRect.translateY - 0.0
            let forceTransY = -tensionTransY * dispTransY
            let dampTransY = -frictionTransY * notchRect.velTranslateY
            let accelTransY = forceTransY + dampTransY
            notchRect.velTranslateY += accelTransY * dt
            notchRect.translateY += notchRect.velTranslateY * dt

            // check if settled
            if (Math.abs(dispX) < 0.01 && Math.abs(notchRect.velScaleX) < 0.05 &&
                Math.abs(dispY) < 0.01 && Math.abs(notchRect.velScaleY) < 0.05 &&
                Math.abs(dispTransY) < 0.1 && Math.abs(notchRect.velTranslateY) < 0.2) {
                notchRect.scaleX = 1.0
                notchRect.scaleY = 1.0
                notchRect.translateY = 0.0
                notchRect.velScaleX = 0.0
                notchRect.velScaleY = 0.0
                notchRect.velTranslateY = 0.0
                stop()
            }
        }
    }

    property int defaultHeight: Config.showBackground ? (screenNotchOpen || hasActiveNotifications ? Math.max(stackContainer.height, 44) : 44) : (screenNotchOpen || hasActiveNotifications ? Math.max(stackContainer.height, 40) : 40)
    property int islandHeight: screenNotchOpen || hasActiveNotifications ? Math.max(stackContainer.height, 36) : 36

    // Corner size calculation for dynamic width (only for default theme)
    readonly property int cornerSize: Config.roundness > 0 ? Config.roundness + 4 : 0
    readonly property int totalCornerWidth: Config.notchTheme === "default" ? cornerSize * 2 : 0

    implicitWidth: screenNotchOpen 
        ? Math.max(stackContainer.width + totalCornerWidth, 290) 
        : stackContainer.width + totalCornerWidth
    implicitHeight: Config.notchTheme === "default" ? defaultHeight : (Config.notchTheme === "island" ? islandHeight : defaultHeight)

    Behavior on implicitWidth {
        enabled: (screenNotchOpen || stackViewInternal.busy) && Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: isExpanded ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: isExpanded ? 1.2 : 1.0
        }
    }

    Behavior on implicitHeight {
        enabled: (screenNotchOpen || stackViewInternal.busy) && Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: isExpanded ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: isExpanded ? 1.2 : 1.0
        }
    }

    // StyledRect extendido que cubre todo (notch + corners) para usar como máscara
    StyledRect {
        variant: "bg"
        id: notchFullBackground
        visible: Config.notchTheme === "default"
        anchors.centerIn: parent
        width: parent.implicitWidth
        height: parent.implicitHeight
        enabled: false // No interactuable
        enableBorder: false // No usar border de StyledRect, el Canvas se encarga
        animateRadius: false // Custom animation below

        property int defaultRadius: Config.roundness > 0 ? (screenNotchOpen || hasActiveNotifications ? Config.roundness + 20 : Config.roundness + 4) : 0

        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: defaultRadius
        bottomRightRadius: defaultRadius

        Behavior on bottomLeftRadius {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: screenNotchOpen || hasActiveNotifications ? Easing.OutBack : Easing.OutQuart
                easing.overshoot: screenNotchOpen || hasActiveNotifications ? 1.2 : 1.0
            }
        }

        Behavior on bottomRightRadius {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: screenNotchOpen || hasActiveNotifications ? Easing.OutBack : Easing.OutQuart
                easing.overshoot: screenNotchOpen || hasActiveNotifications ? 1.2 : 1.0
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: notchFullMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // Máscara completa para el notch + corners
    Item {
        id: notchFullMask
        visible: false
        anchors.centerIn: parent
        width: parent.implicitWidth
        height: parent.implicitHeight
        layer.enabled: true
        layer.smooth: true

    // Left corner mask
    Item {
        id: leftCornerMaskPart
        anchors.top: parent.top
        anchors.left: parent.left
        width: Config.notchTheme === "default" && Config.roundness > 0 ? Config.roundness + 4 : 0
        height: width

        RoundCorner {
            anchors.fill: parent
            corner: RoundCorner.CornerEnum.TopRight
            size: Math.max(parent.width, 1)
            color: "white"
        }
    }

        // Center rect mask
        Rectangle {
            id: centerMaskPart
            anchors.top: parent.top
            anchors.left: leftCornerMaskPart.right
            anchors.right: rightCornerMaskPart.left
            height: parent.height
            color: "white"

            topLeftRadius: notchRect.topLeftRadius
            topRightRadius: notchRect.topRightRadius
            bottomLeftRadius: notchRect.bottomLeftRadius
            bottomRightRadius: notchRect.bottomRightRadius
        }

    // Right corner mask
    Item {
        id: rightCornerMaskPart
        anchors.top: parent.top
        anchors.right: parent.right
        width: Config.notchTheme === "default" && Config.roundness > 0 ? Config.roundness + 4 : 0
        height: width

        RoundCorner {
            anchors.fill: parent
            corner: RoundCorner.CornerEnum.TopLeft
            size: Math.max(parent.width, 1)
            color: "white"
        }
    }
    }

    // Contenedor del notch (solo visual, sin fondo)
    Item {
        id: notchRect
        anchors.centerIn: parent
        width: parent.implicitWidth - totalCornerWidth
        height: parent.implicitHeight

        property real scaleX: 1.0
        property real scaleY: 1.0
        property real translateY: 0.0
        property real velScaleX: 0.0
        property real velScaleY: 0.0
        property real velTranslateY: 0.0

        transform: [
            Scale {
                origin.x: notchRect.width / 2
                origin.y: notchRect.height / 2
                xScale: notchRect.scaleX
                yScale: notchRect.scaleY
            },
            Translate {
                y: notchRect.translateY
            }
        ]

        property int defaultRadius: Config.roundness > 0 ? (screenNotchOpen || hasActiveNotifications ? Config.roundness + 20 : Config.roundness + 4) : 0
        property int islandRadius: Config.roundness > 0 ? (screenNotchOpen || hasActiveNotifications ? Config.roundness + 20 : Config.roundness + 4) : 0

        property int topLeftRadius: Config.notchTheme === "default" ? 0 : islandRadius
        property int topRightRadius: Config.notchTheme === "default" ? 0 : islandRadius
        property int bottomLeftRadius: Config.notchTheme === "island" ? islandRadius : defaultRadius
        property int bottomRightRadius: Config.notchTheme === "island" ? islandRadius : defaultRadius

        // Fondo del notch solo para theme "island"
        StyledRect {
            variant: "bg"
            id: notchIslandBg
            visible: Config.notchTheme === "island"
            anchors.fill: parent
            layer.enabled: false
            clip: false // Desactivar clip para que no corte el border
            enableBorder: true // En island sí usar border de StyledRect
            animateRadius: false // Custom animation below
            
            // Usar el islandRadius como radius base también
            radius: parent.islandRadius

            topLeftRadius: parent.topLeftRadius
            topRightRadius: parent.topRightRadius
            bottomLeftRadius: parent.bottomLeftRadius
            bottomRightRadius: parent.bottomRightRadius
            
            Behavior on topLeftRadius {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: screenNotchOpen || hasActiveNotifications ? Easing.OutBack : Easing.OutQuart
                    easing.overshoot: screenNotchOpen || hasActiveNotifications ? 1.2 : 1.0
                }
            }

            Behavior on topRightRadius {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: screenNotchOpen || hasActiveNotifications ? Easing.OutBack : Easing.OutQuart
                    easing.overshoot: screenNotchOpen || hasActiveNotifications ? 1.2 : 1.0
                }
            }

            Behavior on bottomLeftRadius {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: screenNotchOpen || hasActiveNotifications ? Easing.OutBack : Easing.OutQuart
                    easing.overshoot: screenNotchOpen || hasActiveNotifications ? 1.2 : 1.0
                }
            }

            Behavior on bottomRightRadius {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: screenNotchOpen || hasActiveNotifications ? Easing.OutBack : Easing.OutQuart
                    easing.overshoot: screenNotchOpen || hasActiveNotifications ? 1.2 : 1.0
                }
            }
        }

        // HoverHandler para detectar hover sin bloquear eventos
        HoverHandler {
            id: notchHoverHandler
            enabled: true

            onHoveredChanged: {
                isHovered = hovered;
                if (stackViewInternal.currentItem && stackViewInternal.currentItem.hasOwnProperty("notchHovered")) {
                    stackViewInternal.currentItem.notchHovered = hovered;
                }
            }
        }

        Item {
            id: stackContainer
            anchors.centerIn: parent
            width: stackViewInternal.currentItem ? stackViewInternal.currentItem.implicitWidth + (screenNotchOpen ? 32 : 0) : (screenNotchOpen ? 32 : 0)
            height: stackViewInternal.currentItem ? stackViewInternal.currentItem.implicitHeight + (screenNotchOpen ? 32 : 0) : (screenNotchOpen ? 32 : 0)
            clip: true

            // Propiedad para controlar el blur durante las transiciones
            property real transitionBlur: 0.0

            // Aplicar MultiEffect con blur animable
            layer.enabled: transitionBlur > 0.0
            layer.effect: MultiEffect {
                blurEnabled: Config.performance.blurTransition
                blurMax: 64
                blur: Math.min(Math.max(stackContainer.transitionBlur, 0.0), 1.0)
            }

            // Animación simple de blur → nitidez durante transiciones
            PropertyAnimation {
                id: blurTransitionAnimation
                target: stackContainer
                property: "transitionBlur"
                from: 1.0
                to: 0.0
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }

            StackView {
                id: stackViewInternal
                anchors.fill: parent
                anchors.margins: screenNotchOpen ? 16 : 0
                initialItem: defaultViewComponent

                Component.onCompleted: {
                    isShowingDefault = true;
                    isShowingNotifications = false;
                }

                // Activar blur al inicio de transición y animarlo a nítido
                onBusyChanged: {
                    if (busy) {
                        stackContainer.transitionBlur = 1.0;
                        blurTransitionAnimation.start();
                    }
                }

                pushEnter: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "scale"
                        from: 0.8
                        to: 1
                        duration: Config.animDuration
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }

                pushExit: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "scale"
                        from: 1
                        to: 1.05
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }

                popEnter: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "scale"
                        from: 1.05
                        to: 1
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }

                popExit: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "scale"
                        from: 1
                        to: 0.95
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }

                replaceEnter: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "scale"
                        from: 0.8
                        to: 1
                        duration: Config.animDuration
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }

                replaceExit: Transition {
                    PropertyAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        property: "scale"
                        from: 1
                        to: 1.05
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }
    }

    // Propiedades para mejorar el control del estado de las vistas
    property bool isShowingNotifications: false
    property bool isShowingDefault: false

    // Unified outline canvas (single continuous stroke around silhouette)
    Canvas {
        id: outlineCanvas
        anchors.centerIn: parent
        width: parent.implicitWidth
        height: parent.implicitHeight
        z: 5000
        antialiasing: true
        
        readonly property var borderData: Config.theme.srBg.border
        readonly property int borderWidth: borderData[1]
        readonly property color borderColor: Config.resolveColor(borderData[0])
        
        visible: Config.notchTheme === "default" && borderWidth > 0
        
        onPaint: {
            if (Config.notchTheme !== "default")
                return; // Only draw for default theme
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            
            if (borderWidth <= 0)
                return; // No outline when borderWidth is 0
            
            ctx.strokeStyle = borderColor;
            ctx.lineWidth = borderWidth;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";

            // Offset to move path inward by half the border width
            var offset = borderWidth / 2;
            
            var rTop = Config.roundness > 0 ? Config.roundness + 4 : 0;
            var bl = notchRect.bottomLeftRadius;
            var br = notchRect.bottomRightRadius;
            var wCenter = notchRect.width;
            var yBottom = height - offset;

            ctx.beginPath();
            if (rTop > 0) {
                // Start at top-left, adjusted inward
                ctx.moveTo(offset, offset);
                // Left top corner arc - center at (offset, rTop), radius reduced by offset
                ctx.arc(offset, rTop, rTop - offset, 3 * Math.PI / 2, 2 * Math.PI);
                // This ends at (rTop, rTop)
            } else {
                ctx.moveTo(offset, offset);
                ctx.lineTo(rTop, rTop);
            }
            // Left vertical line down
            ctx.lineTo(rTop, yBottom - bl);
            // Bottom left corner
            if (bl > 0) {
                ctx.arcTo(rTop, yBottom, rTop + bl, yBottom, bl - offset);
            }
            // Bottom horizontal line
            ctx.lineTo(rTop + wCenter - br, yBottom);
            // Bottom right corner
            if (br > 0) {
                ctx.arcTo(rTop + wCenter, yBottom, rTop + wCenter, yBottom - br, br - offset);
            }
            // Right vertical line up
            ctx.lineTo(rTop + wCenter, rTop);
            // Right top corner arc - center at (width - offset, rTop), from 180° to 270°
            if (rTop > 0) {
                ctx.arc(width - offset, rTop, rTop - offset, Math.PI, 3 * Math.PI / 2);
                // This ends at (width - offset - (rTop - offset), offset) = (width - rTop, offset)
            }
            ctx.stroke();
        }
        Connections {
            target: Colors
            function onPrimaryChanged() {
                outlineCanvas.requestPaint();
            }
        }
        Connections {
            target: Config.theme.srBg
            function onBorderChanged() {
                outlineCanvas.requestPaint();
            }
        }
        Connections {
            target: notchRect
            function onBottomLeftRadiusChanged() {
                outlineCanvas.requestPaint();
            }
            function onBottomRightRadiusChanged() {
                outlineCanvas.requestPaint();
            }
            function onWidthChanged() {
                outlineCanvas.requestPaint();
            }
            function onHeightChanged() {
                outlineCanvas.requestPaint();
            }
        }
        Connections {
            target: notchContainer
            function onImplicitWidthChanged() {
                outlineCanvas.requestPaint();
            }
            function onImplicitHeightChanged() {
                outlineCanvas.requestPaint();
            }
        }
        Connections {
            target: Config
            function onNotchThemeChanged() {
                outlineCanvas.requestPaint();
            }
        }
        Connections {
            target: leftCornerMaskPart
            function onWidthChanged() {
                outlineCanvas.requestPaint();
            }
        }
        Connections {
            target: rightCornerMaskPart
            function onWidthChanged() {
                outlineCanvas.requestPaint();
            }
        }
    }
}
