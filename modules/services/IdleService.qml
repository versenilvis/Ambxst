pragma Singleton

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.modules.services

Singleton {
    id: root

    // General Idle Settings
    property string lockCmd: Config.system.idle.general.lock_cmd ?? "ambxst lock"
    property string beforeSleepCmd: Config.system.idle.general.before_sleep_cmd ?? "loginctl lock-session"
    property string afterSleepCmd: Config.system.idle.general.after_sleep_cmd ?? "ambxst screen on"



    // Master Idle Logic
    property int elapsedIdleTime: 0
    property var triggeredListeners: [] // Keeps track of indices that have fired
    property bool resumeCooldown: false // Prevent immediate resume after listener triggers
    property bool pendingReset: false // Track if reset was requested during cooldown
    property bool ignoreNextResume: false

    // Master Monitor: Detects "absence of activity" almost immediately
    IdleMonitor {
        id: masterMonitor
        timeout: 1 // 1 second threshold to consider the session "idle"
        respectInhibitors: true

        onIsIdleChanged: {
            if (isIdle) {
                idleTimer.start();
            } else {
                idleTimer.stop();
                if (root.ignoreNextResume) {
                    root.ignoreNextResume = false;
                    console.log("IdleMonitor: Ignored fake resume event from screen off");
                } else if (root.resumeCooldown) {
                    root.pendingReset = true;
                } else {
                    root.resetIdleState();
                }
            }
        }
    }
    
    // Cooldown timer - prevents resume for a short period after listener triggers
    Timer {
        id: cooldownTimer
        interval: 2500 // 2.5 seconds to safely cover fake resume and its 1s idle reset
        repeat: false
        onTriggered: {
            root.resumeCooldown = false;
            root.ignoreNextResume = false; // Clear flag in case fake resume never arrived
            
            // If the user is active at the end of the cooldown, it means real activity
            if (!masterMonitor.isIdle) {
                root.pendingReset = false;
                root.resetIdleState();
            }
        }
    }

    Timer {
        id: idleTimer
        interval: 1000 // 1 second tick
        repeat: true
        onTriggered: {
            root.elapsedIdleTime += 1;
            root.checkListeners();
        }
    }

    function checkListeners() {
        // Skip idle actions if media is playing (YouTube, Spotify, etc.)
        if (Config.system.idle.general.inhibit_on_media && MprisController.isPlaying) {
            if (root.triggeredListeners.length > 0) {
                root.resetIdleState();
            }
            root.elapsedIdleTime = 0; // Reset timer while media plays
            return;
        }
        
        let listeners = Config.system.idle.listeners;
        for (let i = 0; i < listeners.length; i++) {
            let listener = listeners[i];
            let tVal = listener.timeout || 60;

            // If time matches and hasn't been triggered yet
            if (root.elapsedIdleTime >= tVal && !root.triggeredListeners.includes(i)) {
                if (listener.onTimeout) {
                    console.log("Idle timer " + tVal + "s reached: " + listener.onTimeout);
                    root.executeCommand(listener.onTimeout);
                    
                    root.resumeCooldown = true;
                    root.ignoreNextResume = root.isScreenOffCommand(listener.onTimeout);
                    cooldownTimer.restart();
                }
                root.triggeredListeners.push(i);
            }
        }
    }

    function resetIdleState() {
        let listeners = Config.system.idle.listeners;

        // Execute resume commands for all triggered listeners
        // We iterate backwards to undo latest states first (optional preference)
        for (let i = root.triggeredListeners.length - 1; i >= 0; i--) {
            let idx = root.triggeredListeners[i];
            let listener = listeners[idx];

            if (listener && listener.onResume) {
                if (root.isDpmsOnCommand(listener.onResume)) {
                    console.log("Idle resume skipped duplicate DPMS on command");
                } else {
                    console.log("Idle resuming (undoing " + (listener.timeout || 0) + "s): " + listener.onResume);
                    root.executeCommand(listener.onResume);
                }
            }
        }

        // Reset counters
        root.elapsedIdleTime = 0;
        root.triggeredListeners = [];
    }

    function isDpmsOnCommand(cmd) {
        const value = (cmd || "").trim();
        return value === "ambxst screen on" || value === "hyprctl dispatch dpms on";
    }

    function isScreenOffCommand(cmd) {
        const value = (cmd || "").trim();
        return value === "ambxst screen off" 
            || value === "hyprctl dispatch dpms off"
            || value.includes("wlopm --off")
            || value.includes("dpms off");
    }

    function executeCommand(cmd) {
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { property string cmd; command: ["sh", "-c", cmd]; onExited: destroy() }',
            root
        );
        proc.cmd = cmd;
        proc.running = true;
    }

    Component.onCompleted: {
        // do not kill hypridle as it is needed to handle system sleep inhibitor locks
    }
}
