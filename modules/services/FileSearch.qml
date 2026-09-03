pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services

Singleton {
    id: root

    property var searchResults: []
    property string _pendingQuery: ""

    property Timer searchTimer: Timer {
        id: searchTimer
        interval: 120
        repeat: false
        onTriggered: DaemonClient.searchFiles(root._pendingQuery)
    }

    function searchFiles(query) {
        if (!DaemonClient.daemonConnected) {
            console.warn("Cannot search files: daemon disconnected");
            return;
        }

        root._pendingQuery = query || "";
        if (root._pendingQuery.length === 0) {
            searchTimer.stop();
            root.searchResults = [];
            DaemonClient.searchFiles("");
            return;
        }

        searchTimer.restart();
    }

    function clearSearch() {
        searchTimer.stop();
        root._pendingQuery = "";
        root.searchResults = [];
    }

    Connections {
        ignoreUnknownSignals: true
        enabled: DaemonClient != null
        target: DaemonClient

        function onFileSearchResultsReceived(data) {
            root.searchResults = data || [];
        }
    }
}
