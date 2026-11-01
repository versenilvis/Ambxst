pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.services

Singleton {
    id: root

    // check if two app identifiers refer to the same application
    function isSameApp(appId1, appId2) {
        if (!appId1 || !appId2) return false;
        const a1 = appId1.toLowerCase();
        const a2 = appId2.toLowerCase();
        if (a1 === a2) return true;

        const clean1 = a1.replace(/(\.desktop)+$/, "");
        const clean2 = a2.replace(/(\.desktop)+$/, "");
        if (clean1 === clean2) return true;

        const entry1 = AppSearch.findApp(appId1);
        const entry2 = AppSearch.findApp(appId2);
        if (entry1 && entry2) {
            if (entry1.id && entry2.id && entry1.id.toLowerCase() === entry2.id.toLowerCase()) return true;
            if (entry1.desktop_path && entry2.desktop_path && entry1.desktop_path === entry2.desktop_path) return true;
        }
        if (entry1) {
            if (entry1.startupWmClass && entry1.startupWmClass.toLowerCase() === a2) return true;
            const execBase = entry1.execString ? entry1.execString.trim().split(/\s+/)[0].split('/').pop().toLowerCase() : "";
            if (execBase && (execBase === a2 || execBase === clean2 || a2.startsWith(execBase))) return true;
        }
        if (entry2) {
            if (entry2.startupWmClass && entry2.startupWmClass.toLowerCase() === a1) return true;
            const execBase = entry2.execString ? entry2.execString.trim().split(/\s+/)[0].split('/').pop().toLowerCase() : "";
            if (execBase && (execBase === a1 || execBase === clean1 || a1.startsWith(execBase))) return true;
        }
        return false;
    }

    // Check if an app is pinned
    function isPinned(appId) {
        const pinnedApps = Config.pinnedApps?.apps || [];
        return pinnedApps.some(id => isSameApp(id, appId));
    }

    // Toggle pin status of an app
    function togglePin(appId) {
        let pinnedApps = Config.pinnedApps?.apps || [];
        
        if (isPinned(appId)) {
            // Remove from pinned
            Config.pinnedApps.apps = pinnedApps.filter(id => !isSameApp(id, appId));
        } else {
            // Add to pinned
            const entry = AppSearch.findApp(appId);
            const idToPin = (entry && entry.id) ? entry.id : appId;
            Config.pinnedApps.apps = pinnedApps.concat([idToPin]);
        }
    }

    // Get desktop entry for an app
    function getDesktopEntry(appId) {
        if (!appId) return null;
        return AppSearch.findApp(appId) || DesktopEntries.heuristicLookup(appId) || null;
    }

    // Launch an app by its ID
    function launchApp(appId) {
        const entry = getDesktopEntry(appId);
        if (entry) {
            entry.execute();
        }
    }

    // Internal storage for app entries - prevents memory leaks
    property var _appCache: ({})
    property var _previousKeys: []

    // Main list of apps combining pinned and running apps
    property list<var> apps: []

    // Debounce timer to prevent rapid recalculations
    Timer {
        id: updateTimer
        interval: 100
        repeat: false
        onTriggered: root._updateApps()
    }

    // Trigger update when toplevels change
    property var toplevelsValues: ToplevelManager.toplevels?.values ?? []
    onToplevelsValuesChanged: updateTimer.restart()

    // update on config changes
    property var configPinnedApps: Config.pinnedApps?.apps ?? []
    property var configIgnoredAppRegexes: Config.dock?.ignoredAppRegexes ?? []

    onConfigPinnedAppsChanged: updateTimer.restart()
    onConfigIgnoredAppRegexesChanged: updateTimer.restart()

    // Initial update
    Component.onCompleted: {
        _updateApps();
    }

    function _updateApps() {
        var map = new Map();

        // Get config values
        const pinnedApps = Config.pinnedApps?.apps ?? [];
        const ignoredRegexStrings = Config.dock?.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));

        // Add pinned apps first
        for (const appId of pinnedApps) {
            const key = appId.toLowerCase();
            if (!map.has(key)) {
                map.set(key, {
                    appId: appId,
                    pinned: true,
                    toplevels: []
                });
            }
        }

        // Collect running apps that are not pinned
        var unpinnedRunningApps = [];
        const toplevels = ToplevelManager.toplevels.values;
        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i];
            // Skip ignored apps
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            
            // Check if this toplevel matches any pinned app
            let matchedPinned = false;
            for (const [key, value] of map) {
                if (value.pinned && isSameApp(value.appId, toplevel.appId)) {
                    value.toplevels.push(toplevel);
                    matchedPinned = true;
                    break;
                }
            }
            if (matchedPinned) continue;

            // Check if this toplevel matches an existing unpinned running app
            let matchedUnpinned = false;
            for (let j = 0; j < unpinnedRunningApps.length; j++) {
                if (isSameApp(unpinnedRunningApps[j].appId, toplevel.appId)) {
                    unpinnedRunningApps[j].toplevels.push(toplevel);
                    matchedUnpinned = true;
                    break;
                }
            }
            if (matchedUnpinned) continue;

            // Track as new unpinned running app
            unpinnedRunningApps.push({
                key: toplevel.appId.toLowerCase(),
                appId: toplevel.appId,
                toplevels: [toplevel]
            });
        }

        // Add separator only if there are pinned apps AND unpinned running apps
        if (pinnedApps.length > 0 && unpinnedRunningApps.length > 0) {
            map.set("SEPARATOR", { 
                appId: "SEPARATOR", 
                pinned: false, 
                toplevels: [] 
            });
        }

        // Add unpinned running apps to map
        for (const app of unpinnedRunningApps) {
            map.set(app.key, {
                appId: app.appId,
                pinned: false,
                toplevels: app.toplevels
            });
        }

        // Build new keys list
        var newKeys = Array.from(map.keys());

        // Destroy entries that are no longer needed
        for (const oldKey of _previousKeys) {
            if (!map.has(oldKey) && _appCache[oldKey]) {
                _appCache[oldKey].destroy();
                delete _appCache[oldKey];
            }
        }

        // Create or update entries
        var values = [];
        for (const [key, value] of map) {
            if (_appCache[key]) {
                // Update existing entry
                _appCache[key].toplevels = value.toplevels;
                _appCache[key].pinned = value.pinned;
                values.push(_appCache[key]);
            } else {
                // Create new entry
                const entry = appEntryComp.createObject(root, { 
                    appId: value.appId, 
                    toplevels: value.toplevels, 
                    pinned: value.pinned 
                });
                _appCache[key] = entry;
                values.push(entry);
            }
        }

        _previousKeys = newKeys;
        apps = values;
    }

    // Component for TaskbarAppEntry
    component TaskbarAppEntry: QtObject {
        required property string appId
        property var toplevels: []
        property int toplevelCount: toplevels.length
        property bool pinned
    }
    
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
