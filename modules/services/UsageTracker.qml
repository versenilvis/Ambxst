pragma Singleton
import QtQuick
import Quickshell
import qs.modules.services

Singleton {
    id: root

    property bool dataLoaded: false
    property var topAppsList: []

    // signal emitted when data is loaded
    signal usageDataReady()

    Connections {
        ignoreUnknownSignals: true
        target: DaemonClient
        function onTopAppsReceived(apps) {
            root.topAppsList = apps;
            root.dataLoaded = true;
            root.usageDataReady();
        }
    }

    // record that an app was used
    function recordUsage(appId) {
        if (!appId) {
            console.warn("UsageTracker: recordUsage called with empty appId");
            return;
        }

        DaemonClient.sendCommand({
            type: "record_usage",
            app_id: appId
        });
    }

    // get usage score for an app
    function getUsageScore(appId) {
        if (!appId || !topAppsList) return 0;
        for (var i = 0; i < topAppsList.length; i++) {
            if (topAppsList[i].app_id === appId) {
                return topAppsList[i].score;
            }
        }
        return 0;
    }

    // get all apps sorted by usage
    function getTopApps(limit) {
        if (!limit) limit = 10;
        return topAppsList.slice(0, limit);
    }

    // prune old entries handled in backend daemon
    function pruneOldEntries() {
    }
}
