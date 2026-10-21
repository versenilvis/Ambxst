import QtQuick
import qs.modules.theme
import qs.config

Item {
    id: root

    property real waterLevel: 0.48
    property real waveAmplitude: 4.5
    property real waveSpeed: 0.05
    property color colorTop: "#00C6FF"
    property color colorBottom: "#0072FF"

    property real _phase: 0.0
    property real _extraBounce: 0.0

    function splash() {
        splashAnim.restart();
    }

    SequentialAnimation {
        id: splashAnim
        NumberAnimation {
            target: root
            property: "_extraBounce"
            to: 8.0
            duration: 180
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "_extraBounce"
            to: 0.0
            duration: 500
            easing.type: Easing.OutBounce
        }
    }

    Timer {
        id: animTimer
        interval: 33
        repeat: true
        running: root.visible
        onTriggered: {
            root._phase += root.waveSpeed;
            if (root._phase > Math.PI * 4) {
                root._phase -= Math.PI * 4;
            }
            waveCanvas.requestPaint();
        }
    }

    Canvas {
        id: waveCanvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var w = width;
            var h = height;
            if (w <= 0 || h <= 0) return;

            var baseWaterY = h * (1.0 - root.waterLevel);
            var amp = root.waveAmplitude + root._extraBounce;

            // back wave layer (subtle, darker)
            ctx.beginPath();
            ctx.moveTo(0, baseWaterY);
            for (var x = 0; x <= w; x += 4) {
                var yBack = baseWaterY + Math.sin((x / 28.0) + root._phase * 0.7) * (amp * 0.65);
                ctx.lineTo(x, yBack);
            }
            ctx.lineTo(w, h);
            ctx.lineTo(0, h);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(0.0, 0.45, 0.9, 0.35);
            ctx.fill();

            // front wave layer (vibrant gradient)
            ctx.beginPath();
            ctx.moveTo(0, baseWaterY);
            for (var x2 = 0; x2 <= w; x2 += 3) {
                var yFront = baseWaterY + Math.sin((x2 / 24.0) + root._phase) * amp;
                ctx.lineTo(x2, yFront);
            }
            ctx.lineTo(w, h);
            ctx.lineTo(0, h);
            ctx.closePath();

            var grad = ctx.createLinearGradient(0, baseWaterY - amp, 0, h);
            grad.addColorStop(0.0, root.colorTop);
            grad.addColorStop(1.0, root.colorBottom);
            ctx.fillStyle = grad;
            ctx.fill();
        }
    }
}
