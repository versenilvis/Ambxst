import QtQuick
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.config

Item {
    id: root

    property bool expandedState: false

    readonly property bool isRecordingActive: ScreenRecorder.isRecording
    readonly property bool isBatteryActive: Battery.available && !Battery.isCharging && Battery.percentage < 20
    readonly property bool isBluetoothActive: BluetoothService.connected

    // priority order: recording > low battery > bluetooth > media
    readonly property string fullTreatmentKind: {
        if (isRecordingActive) return "recording"
        if (isBatteryActive) return "battery"
        if (isBluetoothActive) return "bluetooth"
        return "media"
    }

    readonly property bool mediaCompact: fullTreatmentKind !== "media"
    readonly property bool recordingCompact: fullTreatmentKind !== "recording"
    readonly property bool batteryCompact: fullTreatmentKind !== "battery"
    readonly property bool bluetoothCompact: fullTreatmentKind !== "bluetooth"

    // media player helpers
    readonly property var player: MprisController.activePlayer
    readonly property bool isMediaPlaying: Boolean(player && player.playbackState === MprisPlaybackState.Playing)

    function getMediaIcon(p) {
        if (!p)
            return Icons.player
        const dbusName = (p.dbusName || "").toLowerCase()
        const desktopEntry = (p.desktopEntry || "").toLowerCase()
        const identity = (p.identity || "").toLowerCase()
        if (dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify"))
            return Icons.spotify
        if (dbusName.includes("chromium") || dbusName.includes("chrome") || desktopEntry.includes("chromium") || desktopEntry.includes("chrome"))
            return Icons.chromium
        if (dbusName.includes("firefox") || desktopEntry.includes("firefox"))
            return Icons.firefox
        if (dbusName.includes("telegram") || desktopEntry.includes("telegram") || identity.includes("telegram"))
            return Icons.telegram
        return Icons.player
    }

    // calendar state
    property string calDay: ""
    property string calMonth: ""
    property string calWeekday: ""
    property string calWeekNum: ""

    function getIsoWeek(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
        const dayNum = d.getUTCDay() || 7
        d.setUTCDate(d.getUTCDate() + 4 - dayNum)
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
        return Math.ceil((((d - yearStart) / 86400000) + 1) / 7)
    }

    function updateCalendar() {
        const now = new Date()
        calDay = String(now.getDate())
        calMonth = Qt.formatDateTime(now, Qt.locale(), "MMM")
        calWeekday = Qt.formatDateTime(now, Qt.locale(), "ddd")
        calWeekNum = "W" + getIsoWeek(now)
    }

    // calendar timer aligned to minute boundary
    Timer {
        id: calTimer
        interval: Math.max(100, (60 - new Date().getSeconds()) * 1000 - new Date().getMilliseconds() + 50)
        running: root.expandedState
        repeat: true
        onTriggered: {
            root.updateCalendar()
            calTimer.interval = Math.max(100, (60 - new Date().getSeconds()) * 1000 - new Date().getMilliseconds() + 50)
        }
    }

    onExpandedStateChanged: {
        if (expandedState) {
            updateCalendar()
            calTimer.interval = Math.max(100, (60 - new Date().getSeconds()) * 1000 - new Date().getMilliseconds() + 50)
        }
    }

    Component.onCompleted: {
        updateCalendar()
    }

    // media position update timer
    Timer {
        id: mediaTimer
        interval: 1000
        repeat: true
        running: root.expandedState && root.isMediaPlaying
        onTriggered: {
            if (root.player) {
                root.player.positionChanged()
            }
        }
    }

    implicitWidth: rowContainer.width
    implicitHeight: rowContainer.height

    Rectangle {
        id: rowContainer
        anchors.centerIn: parent
        width: contentRow.implicitWidth + 16
        height: Math.max(contentRow.implicitHeight + 8, 44)
        radius: Styling.radius(0)
        color: Colors.surfaceContainerLowest

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 6

            // kind 1: now playing
            StatusPill {
                id: mediaPill
                accentColor: Colors.primary
                icon: root.getMediaIcon(root.player)
                artworkUrl: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
                valueText: (root.player && root.player.trackTitle) ? root.player.trackTitle : "Not playing"
                contextText: (root.player && root.player.trackArtist) ? root.player.trackArtist : "No media"
                progress: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : -1
                compact: root.mediaCompact
                clickable: root.player !== null
                onClicked: {
                    if (root.player) {
                        root.player.togglePlaying()
                    }
                }
                anchors.verticalCenter: parent.verticalCenter
            }

            // divider before recording
            Rectangle {
                width: 1
                height: 24
                color: Colors.surfaceContainer
                visible: root.isRecordingActive
                anchors.verticalCenter: parent.verticalCenter
            }

            // kind 4: screen recording
            StatusPill {
                id: recordingPill
                visible: root.isRecordingActive
                accentColor: Colors.red
                icon: Icons.recordScreen
                valueText: ScreenRecorder.duration !== "" ? ScreenRecorder.duration : "00:00"
                contextText: "Recording"
                compact: root.recordingCompact
                clickable: true
                onClicked: ScreenRecorder.toggleRecording()
                anchors.verticalCenter: parent.verticalCenter
            }

            // divider before battery
            Rectangle {
                width: 1
                height: 24
                color: Colors.surfaceContainer
                visible: root.isBatteryActive
                anchors.verticalCenter: parent.verticalCenter
            }

            // kind 5: low battery
            StatusPill {
                id: batteryPill
                visible: root.isBatteryActive
                accentColor: Colors.yellow
                icon: Icons.batteryLow
                valueText: Math.round(Battery.percentage) + "%"
                contextText: Battery.timeToEmpty !== "" ? Battery.timeToEmpty : "Low battery"
                compact: root.batteryCompact
                anchors.verticalCenter: parent.verticalCenter
            }

            // divider before bluetooth
            Rectangle {
                width: 1
                height: 24
                color: Colors.surfaceContainer
                visible: root.isBluetoothActive
                anchors.verticalCenter: parent.verticalCenter
            }

            // kind 6: bluetooth
            StatusPill {
                id: bluetoothPill
                visible: root.isBluetoothActive
                accentColor: Colors.cyan
                icon: Icons.bluetoothConnected
                valueText: String(BluetoothService.connectedDevices)
                contextText: BluetoothService.connectedDevices === 1 ? "device" : "devices"
                compact: root.bluetoothCompact
                anchors.verticalCenter: parent.verticalCenter
            }

            // divider before calendar
            Rectangle {
                width: 1
                height: 24
                color: Colors.surfaceContainer
                anchors.verticalCenter: parent.verticalCenter
            }

            // kind 3: calendar
            StatusPill {
                id: calPill
                accentColor: Colors.primary
                icon: Icons.clock
                valueText: root.calDay + " " + root.calMonth
                contextText: root.calWeekday + " · " + root.calWeekNum
                anchors.verticalCenter: parent.verticalCenter
            }

            // divider before mirror
            Rectangle {
                width: 1
                height: 24
                color: Colors.surfaceContainer
                anchors.verticalCenter: parent.verticalCenter
            }

            // kind 2: mirror
            StatusPill {
                id: mirrorPill
                accentColor: Colors.primary
                icon: GlobalStates.mirrorWindowVisible ? Icons.webcamSlash : Icons.webcam
                contextText: "Mirror"
                iconAboveLabel: true
                chipFilled: GlobalStates.mirrorWindowVisible
                clickable: true
                onClicked: GlobalStates.mirrorWindowVisible = !GlobalStates.mirrorWindowVisible
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
