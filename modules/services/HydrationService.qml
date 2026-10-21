pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

Singleton {
    id: root

    property string stateFile: Quickshell.statePath("hydration.json")
    property bool enabled: false
    property int intervalMinutes: 65
    property int remainingSeconds: 65 * 60
    property bool isRunning: true
    property bool alertActive: enabled && remainingSeconds <= 0
    property bool popupOpen: false

    property int todayCount: 0
    property int dailyGoal: 8
    readonly property real goalProgress: Math.min(1.0, Math.max(0.0, todayCount / Math.max(1, dailyGoal)))
    readonly property bool goalReached: todayCount >= dailyGoal

    property var history: []
    property int streak: 0
    property real average: 0.0
    property int bestCount: 0
    property string bestDate: ""

    property string lastCheckedDate: getTodayDateString()

    property int shelfTab: 0

    signal drank()

    readonly property string formattedTime: formatCountdown(remainingSeconds)

    function formatCountdown(sec) {
        if (sec <= 0) return "00:00";
        var m = Math.floor(sec / 60);
        var s = sec % 60;
        var pad = n => n < 10 ? "0" + n : "" + n;
        return pad(m) + ":" + pad(s);
    }

    function togglePopup(tabIndex) {
        if (typeof tabIndex !== "undefined") {
            if (popupOpen && shelfTab === tabIndex) {
                popupOpen = false;
            } else {
                shelfTab = tabIndex;
                popupOpen = true;
            }
        } else {
            popupOpen = !popupOpen;
        }
    }

    function openShelfTab(tabIndex) {
        shelfTab = tabIndex;
        popupOpen = true;
    }

    function openPopup() {
        popupOpen = true;
    }

    function closePopup() {
        popupOpen = false;
    }

    function setEnabled(val) {
        root.enabled = val;
        if (!root.enabled) {
            root.alertActive = false;
        }
        root.save();
    }

    function toggleEnabled() {
        root.setEnabled(!root.enabled);
    }

    function stepInterval(delta) {
        var next = Math.max(5, Math.min(180, intervalMinutes + delta));
        if (next !== intervalMinutes) {
            intervalMinutes = next;
            if (remainingSeconds > intervalMinutes * 60) {
                remainingSeconds = intervalMinutes * 60;
            }
            save();
        }
    }

    function setIntervalMinutes(mins) {
        intervalMinutes = Math.max(5, Math.min(180, mins));
        save();
    }

    function stepGoal(delta) {
        var next = Math.max(1, Math.min(30, dailyGoal + delta));
        if (next !== dailyGoal) {
            dailyGoal = next;
            save();
        }
    }

    function setDailyGoal(goal) {
        dailyGoal = Math.max(1, Math.min(30, goal));
        save();
    }

    function triggerAlert() {
        root.remainingSeconds = 0;
        root.alertActive = true;
        GlobalStates.notchBounce();

        try {
            notifProcess.command = [
                "notify-send",
                "-a", "Hydration",
                "-i", "dialog-information",
                "-u", "normal",
                "Time to Hydrate",
                "Take a sip of water to stay focused and refreshed"
            ];
            notifProcess.running = true;
        } catch (e) {
            console.warn("HydrationService: notify error:", e);
        }
    }

    function drink() {
        var todayKey = getTodayDateString();
        ensureTodayInHistory();

        var updated = [];
        for (var i = 0; i < history.length; i++) {
            var entry = history[i];
            if (entry.date === todayKey) {
                var newCount = (entry.count || 0) + 1;
                updated.push({
                    date: entry.date,
                    day: entry.day,
                    count: newCount
                });
                root.todayCount = newCount;
            } else {
                updated.push(entry);
            }
        }
        root.history = updated;
        root.remainingSeconds = root.intervalMinutes * 60;
        root.alertActive = false;

        calculateStats();
        save();
        root.drank();
    }

    function undoDrink() {
        if (root.todayCount <= 0) return;
        var todayKey = getTodayDateString();
        var updated = [];
        for (var i = 0; i < history.length; i++) {
            var entry = history[i];
            if (entry.date === todayKey) {
                var newCount = Math.max(0, (entry.count || 0) - 1);
                updated.push({
                    date: entry.date,
                    day: entry.day,
                    count: newCount
                });
                root.todayCount = newCount;
            } else {
                updated.push(entry);
            }
        }
        root.history = updated;
        calculateStats();
        save();
    }

    function resetData() {
        var list = [];
        var today = new Date();
        for (var i = 13; i >= 0; i--) {
            var d = new Date(today.getTime() - i * 86400000);
            var pad = n => n < 10 ? "0" + n : "" + n;
            var dateStr = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
            list.push({
                date: dateStr,
                day: getDayLetter(d),
                count: 0
            });
        }
        root.history = list;
        root.todayCount = 0;
        root.remainingSeconds = root.intervalMinutes * 60;
        root.alertActive = false;
        root.streak = 0;
        root.average = 0.0;
        root.bestCount = 0;
        root.bestDate = "None";
        root.save();
    }

    function getTodayDateString() {
        var d = new Date();
        var pad = n => n < 10 ? "0" + n : "" + n;
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    }

    function getDayLetter(d) {
        var letters = ["S", "M", "T", "W", "T", "F", "S"];
        return letters[d.getDay()];
    }

    function checkMidnightRollover() {
        var currentToday = getTodayDateString();
        if (currentToday !== root.lastCheckedDate) {
            root.lastCheckedDate = currentToday;
            ensureTodayInHistory();
            calculateStats();
            save();
        }
    }

    function ensureTodayInHistory() {
        var todayKey = getTodayDateString();
        var found = false;
        for (var i = 0; i < history.length; i++) {
            if (history[i].date === todayKey) {
                found = true;
                root.todayCount = history[i].count || 0;
                break;
            }
        }

        if (!found) {
            var list = history.slice(0);
            list.push({
                date: todayKey,
                day: getDayLetter(new Date()),
                count: 0
            });
            while (list.length > 14) {
                list.shift();
            }
            root.history = list;
            root.todayCount = 0;
        }
    }

    function generateDefaultHistory() {
        var list = [];
        var today = new Date();
        for (var i = 13; i >= 0; i--) {
            var d = new Date(today.getTime() - i * 86400000);
            var pad = n => n < 10 ? "0" + n : "" + n;
            var dateStr = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
            list.push({
                date: dateStr,
                day: getDayLetter(d),
                count: 0
            });
        }
        root.history = list;
        root.todayCount = 0;
    }

    function calculateStats() {
        if (!history || history.length === 0) {
            root.streak = 0;
            root.average = 0.0;
            root.bestCount = 0;
            root.bestDate = "None";
            return;
        }

        var total = 0;
        var daysWithCounts = 0;
        var currentStreak = 0;
        var maxCount = 0;
        var maxDateStr = "";

        for (var i = history.length - 1; i >= 0; i--) {
            var c = history[i].count || 0;
            total += c;
            if (c > 0) {
                daysWithCounts++;
                if (currentStreak === (history.length - 1 - i)) {
                    currentStreak++;
                }
            }

            if (c > maxCount) {
                maxCount = c;
                maxDateStr = history[i].date;
            }
        }

        root.streak = currentStreak;
        root.average = daysWithCounts > 0 ? (total / daysWithCounts) : 0;
        root.bestCount = maxCount;

        if (maxDateStr && maxCount > 0) {
            var parts = maxDateStr.split("-");
            var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
            var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
            root.bestDate = dayNames[d.getDay()] + ", " + d.getDate() + " " + monthNames[d.getMonth()];
        } else {
            root.bestDate = "None";
        }
    }

    Timer {
        id: secondTimer
        interval: 1000
        repeat: true
        running: root.enabled && root.isRunning
        onTriggered: {
            if (root.remainingSeconds > 0) {
                root.remainingSeconds--;
                if (root.remainingSeconds === 0) {
                    root.triggerAlert();
                }
            }

            // check midnight rollover every 60 seconds
            if (root.remainingSeconds % 60 === 0) {
                root.checkMidnightRollover();
            }
        }
    }

    Process {
        id: notifProcess
        running: false
    }

    Process {
        id: writeProcess
        running: false
    }

    function save() {
        try {
            var data = {
                enabled: root.enabled,
                intervalMinutes: root.intervalMinutes,
                remainingSeconds: root.remainingSeconds,
                dailyGoal: root.dailyGoal,
                history: root.history
            };
            var json = JSON.stringify(data);
            var cmd = "cat << 'EOF' > \"" + root.stateFile + "\"\n" + json + "\nEOF\n";
            writeProcess.command = ["bash", "-c", cmd];
            writeProcess.running = true;
        } catch (e) {
            console.warn("HydrationService: Failed to save:", e);
        }
    }

    Process {
        id: readProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var str = text ? text.trim() : "";
                    if (str) {
                        var parsed = JSON.parse(str);
                        if (typeof parsed.enabled === "boolean") root.enabled = parsed.enabled;
                        if (parsed.intervalMinutes) root.intervalMinutes = parsed.intervalMinutes;
                        if (typeof parsed.remainingSeconds === "number") root.remainingSeconds = parsed.remainingSeconds;
                        if (typeof parsed.dailyGoal === "number") root.dailyGoal = parsed.dailyGoal;
                        if (parsed.history && parsed.history.length > 0) {
                            root.history = parsed.history;
                        }
                    }
                } catch(e) {
                    console.warn("HydrationService: Failed to parse data:", e);
                }

                if (!root.history || root.history.length === 0) {
                    root.generateDefaultHistory();
                } else {
                    root.ensureTodayInHistory();
                }
                root.calculateStats();
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.generateDefaultHistory();
                root.calculateStats();
                root.save();
            }
        }
    }

    function load() {
        readProcess.command = ["cat", root.stateFile];
        readProcess.running = true;
    }

    IpcHandler {
        target: "hydration"

        function enable(): string {
            root.setEnabled(true);
            return "hydration enabled: true";
        }

        function disable(): string {
            root.setEnabled(false);
            return "hydration enabled: false";
        }

        function toggleEnabled(): string {
            root.toggleEnabled();
            return "hydration enabled: " + root.enabled;
        }

        function drink(): string {
            root.drink();
            return "drank water, total today: " + root.todayCount + "/" + root.dailyGoal;
        }

        function undo(): string {
            root.undoDrink();
            return "undid water drink, total today: " + root.todayCount;
        }

        function reset(): string {
            root.resetData();
            return "hydration data reset to clean zero";
        }

        function setInterval(mins: int): string {
            root.setIntervalMinutes(mins);
            return "interval set to: " + root.intervalMinutes + " min";
        }

        function setGoal(goal: int): string {
            root.setDailyGoal(goal);
            return "daily goal set to: " + root.dailyGoal + " drinks";
        }

        function alert(): string {
            root.triggerAlert();
            return "alert triggered";
        }

        function tab(idx: int): string {
            root.shelfTab = idx;
            root.popupOpen = true;
            return "shelf tab: " + root.shelfTab;
        }

        function toggle(): string {
            root.togglePopup();
            return "popup open: " + root.popupOpen;
        }
    }

    Component.onCompleted: {
        root.load();
    }
}
