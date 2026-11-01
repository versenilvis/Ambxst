pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services

Singleton {
    id: root

    property var iconCache: ({})

    function getCachedIcon(str) {
        if (!str) return "image-missing";
        if (iconCache[str]) return iconCache[str];

        const result = guessIcon(str);
        iconCache[str] = result;
        return result;
    }

    function iconExists(iconName) {
        return (Quickshell.iconPath(iconName, true).length > 0)
            && !iconName.includes("image-missing");
    }

    // Validate icon and return fallback if needed
    function validateIcon(iconName) {
        if (!iconName || iconName.length === 0) {
            return "image-missing";
        }

        // If it's an absolute path, check if file exists
        if (iconName.startsWith("/")) {
            // Use Quickshell.iconPath to check if the path is valid
            const resolvedPath = Quickshell.iconPath(iconName, true);
            if (resolvedPath.length === 0) {
                return "image-missing";
            }
            return iconName;
        }

        // For icon names (not paths), check if they exist in the theme
        if (iconExists(iconName)) {
            return iconName;
        }

        return "image-missing";
    }

    function findApp(appId) {
        if (!appId || appId.length === 0) return null;

        const raw = String(appId).trim();
        const lower = raw.toLowerCase();

        // check regex and direct substitutions
        let resolvedQuery = raw;
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const sub = regexSubstitutions[i];
            const replaced = raw.replace(sub.regex, sub.replace);
            if (replaced !== raw) {
                resolvedQuery = replaced;
                break;
            }
        }
        if (substitutions[raw]) resolvedQuery = substitutions[raw];
        else if (substitutions[lower]) resolvedQuery = substitutions[lower];

        const queryLower = resolvedQuery.toLowerCase();
        const withoutDesktop = queryLower.replace(/(\.desktop)+$/, "");
        const withDesktop = withoutDesktop + ".desktop";
        const baseName = withoutDesktop.split('/').pop();
        const lastSegment = withoutDesktop.split('.').pop();

        // 1. match against allApps loaded from daemon
        if (root.allApps && root.allApps.length > 0) {
            // exact id / filename match
            for (let i = 0; i < root.allApps.length; i++) {
                const app = root.allApps[i];
                const idLower = (app.id || "").toLowerCase();
                const idClean = idLower.replace(/(\.desktop)+$/, "");
                if (idLower === queryLower || idLower === withDesktop || idClean === withoutDesktop) {
                    return app;
                }
            }

            // startup_wm_class match
            for (let i = 0; i < root.allApps.length; i++) {
                const app = root.allApps[i];
                if (app.startupWmClass) {
                    const swc = app.startupWmClass.toLowerCase();
                    if (swc === lower || swc === queryLower || swc === withoutDesktop) {
                        return app;
                    }
                }
            }

            // executable basename match
            for (let i = 0; i < root.allApps.length; i++) {
                const app = root.allApps[i];
                if (!app.execString) continue;
                const execBase = app.execString.trim().split(/\s+/)[0].split('/').pop().toLowerCase();
                if (execBase && (execBase === queryLower || execBase === withoutDesktop || execBase === baseName)) {
                    return app;
                }
                if (execBase && execBase.length >= 3) {
                    if (queryLower.startsWith(execBase) || withoutDesktop.startsWith(execBase) || execBase.startsWith(withoutDesktop)) {
                        return app;
                    }
                }
            }

            // app name match
            for (let i = 0; i < root.allApps.length; i++) {
                const app = root.allApps[i];
                const nameLower = (app.name || "").toLowerCase();
                if (nameLower === queryLower || nameLower === withoutDesktop) {
                    return app;
                }
            }

            // last reverse-DNS segment match
            for (let i = 0; i < root.allApps.length; i++) {
                const app = root.allApps[i];
                const idClean = (app.id || "").toLowerCase().replace(/(\.desktop)+$/, "");
                const seg = idClean.split('.').pop();
                if (seg === withoutDesktop || seg === lastSegment) {
                    return app;
                }
            }

            // token combination match (e.g. ida + pro in class com.hex_rays.ida.pro._9_4)
            const tokens = lower.split(/[^a-z0-9]+/).filter(t => t.length > 1 && !["com", "org", "net", "io", "github", "gitlab"].includes(t));
            if (tokens.length >= 2) {
                for (let i = 0; i < root.allApps.length; i++) {
                    const app = root.allApps[i];
                    const target = ((app.id || "") + " " + (app.name || "")).toLowerCase();
                    if (tokens.every(token => target.includes(token))) {
                        return app;
                    }
                }
            }
        }

        // 2. fallback to quickshell desktop entries heuristic
        const entry = DesktopEntries.heuristicLookup(raw) || DesktopEntries.heuristicLookup(withoutDesktop);
        if (entry) return entry;

        return null;
    }

    function getIconFromDesktopEntry(className) {
        if (!className || className.length === 0) return null;

        const app = findApp(className);
        if (app && app.icon && app.icon !== "application-x-executable" && app.icon !== "image-missing") {
            return app.icon;
        }

        const normalizedClassName = className.toLowerCase().replace(/(\.desktop)+$/, "");

        for (let i = 0; i < list.length; i++) {
            const item = list[i];
            if (item.command && item.command.length > 0) {
                const executableLower = item.command[0].toLowerCase().split('/').pop();
                if (executableLower === normalizedClassName) {
                    return item.icon || "application-x-executable";
                }
            }
            if (item.name && item.name.toLowerCase() === normalizedClassName) {
                return item.icon || "application-x-executable";
            }
            if (item.keywords && item.keywords.length > 0) {
                for (let j = 0; j < item.keywords.length; j++) {
                    if (item.keywords[j].toLowerCase() === normalizedClassName) {
                        return item.icon || "application-x-executable";
                    }
                }
            }
        }
        return null;
    }

    function guessIcon(str) {
        if (!str || str.length === 0) return "image-missing";

        const raw = String(str).trim();
        const lower = raw.toLowerCase();
        const withoutDesktop = lower.replace(/(\.desktop)+$/, "");

        // check direct desktop entry lookup first
        const desktopIcon = getIconFromDesktopEntry(raw) || getIconFromDesktopEntry(withoutDesktop);
        if (desktopIcon) return desktopIcon;

        if (substitutions[raw]) return substitutions[raw];
        if (substitutions[lower]) return substitutions[lower];
        if (substitutions[withoutDesktop]) return substitutions[withoutDesktop];

        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = raw.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName !== raw) return replacedName;
        }

        if (iconExists(withoutDesktop)) return withoutDesktop;
        if (iconExists(raw)) return raw;

        const extensionGuess = withoutDesktop.split('.').pop();
        if (iconExists(extensionGuess)) return extensionGuess;

        const hyphenGuess = withoutDesktop.split('-')[0];
        if (iconExists(hyphenGuess)) return hyphenGuess;

        const dashedGuess = withoutDesktop.replace(/\s+/g, "-");
        if (iconExists(dashedGuess)) return dashedGuess;

        return withoutDesktop;
    }

    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
        "zen": "zen-browser",
        "antigravity-ide": "antigravity",
    })
    property list<var> regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /.*hex_rays.*ida.*/i,
            "replace": "ida-pro"
        }
    ]

    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .sort((a, b) => a.name.localeCompare(b.name))

    property var allApps: []
    property var searchResults: []
    property string _currentQuery: ""

    // fast fuzzy matching algorithm
    function fffMatch(query, target) {
        if (!query || query.length === 0) return 0;
        if (!target || target.length === 0) return null;

        let qIdx = 0;
        let score = 0;
        let consecutive = 0;
        let isStartOfWord = true;
        let firstMatchIndex = -1;

        for (let i = 0; i < target.length; i++) {
            const c = target[i];
            const currentIsStart = isStartOfWord;
            isStartOfWord = (c === ' ' || c === '-' || c === '_' || c === '.');

            if (c === query[qIdx]) {
                if (firstMatchIndex === -1) {
                    firstMatchIndex = i;
                }
                score += 10 + consecutive * 5;
                if (currentIsStart) {
                    score += 20;
                }
                consecutive += 1;
                qIdx += 1;
                if (qIdx === query.length) {
                    return score - firstMatchIndex;
                }
            } else {
                consecutive = 0;
            }
        }
        return null;
    }

    function localFilter(query) {
        if (!root.allApps || root.allApps.length === 0) {
            initFromDesktopEntries();
        }
        if (!root.allApps || root.allApps.length === 0) return [];

        const q = (query || "").trim().toLowerCase();
        if (q.length === 0) {
            return root.allApps.slice().sort((a, b) => {
                const uA = UsageTracker.getUsageScore(a.id) || 0;
                const uB = UsageTracker.getUsageScore(b.id) || 0;
                if (uB !== uA) return uB - uA;
                return a.name.localeCompare(b.name);
            });
        }

        const scored = [];
        for (let i = 0; i < root.allApps.length; i++) {
            const app = root.allApps[i];
            const nameLower = (app.name || "").toLowerCase();
            const idLower = (app.id || "").toLowerCase();
            const execLower = (app.execString || "").toLowerCase();
            const commentLower = (app.comment || "").toLowerCase();

            let score = -1;

            if (nameLower === q) {
                score = 10000;
            } else if (nameLower.startsWith(q)) {
                score = 5000 + (50 - Math.min(50, nameLower.length));
            } else {
                const words = nameLower.split(/[\s\-_.]+/);
                for (let w = 0; w < words.length; w++) {
                    if (words[w].startsWith(q)) {
                        score = 3500 + (50 - Math.min(50, words[w].length));
                        break;
                    }
                }
            }

            if (score === -1) {
                if (execLower.startsWith(q) || idLower.startsWith(q)) {
                    score = 2500;
                }
            }

            if (score === -1) {
                if (nameLower.includes(q)) {
                    score = 1500 - Math.min(50, nameLower.indexOf(q));
                }
            }

            if (score === -1) {
                if (commentLower.includes(q) || execLower.includes(q)) {
                    score = 800;
                }
            }

            if (score === -1 && app.categories) {
                for (let c = 0; c < app.categories.length; c++) {
                    if (app.categories[c].toLowerCase().includes(q)) {
                        score = 400;
                        break;
                    }
                }
            }

            if (score === -1) {
                const target = app._searchString || (nameLower + " " + execLower + " " + commentLower);
                const fff = fffMatch(q, target);
                if (fff !== null) {
                    score = fff;
                }
            }

            if (score >= 0) {
                const usage = UsageTracker.getUsageScore(app.id) || 0;
                scored.push({ app: app, score: score + Math.min(50, usage * 5) });
            }
        }

        scored.sort((a, b) => {
            if (b.score !== a.score) return b.score - a.score;
            const uA = UsageTracker.getUsageScore(a.app.id) || 0;
            const uB = UsageTracker.getUsageScore(b.app.id) || 0;
            if (uB !== uA) return uB - uA;
            return a.app.name.localeCompare(b.app.name);
        });

        return scored.map(item => item.app);
    }

    function searchApps(query) {
        root._currentQuery = query || "";
        root.searchResults = localFilter(root._currentQuery);
    }

    function getAllApps() {
        return localFilter("");
    }

    function fuzzyQuery(query) {
        return localFilter(query);
    }

    function invalidateCache() {
        root.searchResults = localFilter(root._currentQuery);
    }

    function initFromDesktopEntries() {
        const entries = root.list;
        if (!entries || entries.length === 0) return;
        const mapped = [];
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (!entry || !entry.name) continue;
            const iconName = entry.icon || "application-x-executable";
            const validatedIcon = getCachedIcon(iconName);
            const cmdStr = (entry.command && entry.command.length > 0) ? entry.command.join(" ") : "";
            mapped.push({
                id: entry.id || entry.name,
                name: entry.name,
                icon: validatedIcon,
                comment: entry.comment || "",
                execString: cmdStr,
                categories: entry.categories || [],
                runInTerminal: false,
                usageScore: 0,
                startupWmClass: "",
                desktop_path: "",
                _searchString: (entry.name + " " + (entry.comment || "") + " " + cmdStr).toLowerCase(),
                execute: () => {
                    entry.execute();
                }
            });
        }
        root.allApps = mapped;
        root.searchResults = localFilter(root._currentQuery);
    }

    Connections {
        ignoreUnknownSignals: true
        enabled: DaemonClient != null
        target: DaemonClient
        
        function onDaemonConnectedChanged() {
            if (DaemonClient.daemonConnected) {
                DaemonClient.searchApps("");
            }
        }

        function onAppSearchResultsReceived(data) {
            if (!data || data.length === 0) return;
            let mapped = data.map(app => {
                let iconToUse = app.icon || "application-x-executable";
                if (iconCache[iconToUse]) {
                    iconToUse = iconCache[iconToUse];
                } else {
                    let validated = validateIcon(iconToUse);
                    iconCache[iconToUse] = validated;
                    iconToUse = validated;
                }

                const searchStr = (app.name + " " + (app.generic_name || "") + " " + (app.exec || "") + " " + (app.keywords ? app.keywords.join(" ") : "")).toLowerCase();

                return {
                    id: app.id,
                    name: app.name,
                    icon: iconToUse,
                    comment: app.generic_name || "",
                    execString: app.exec,
                    categories: app.categories || [],
                    runInTerminal: false,
                    usageScore: 0,
                    startupWmClass: app.startup_wm_class || "",
                    desktop_path: app.desktop_path || "",
                    _searchString: searchStr,
                    execute: () => {
                        DaemonClient.sendCommand({
                            type: "record_usage",
                            app_id: app.id
                        });
                        DaemonClient.sendCommand({
                            type: "execute_desktop",
                            path: app.desktop_path
                        });
                    }
                };
            });
            
            root.allApps = mapped;
            root.searchResults = localFilter(root._currentQuery);
        }
    }

    Component.onCompleted: {
        initFromDesktopEntries();
        if (DaemonClient && DaemonClient.daemonConnected) {
            DaemonClient.searchApps("");
        }
    }
}
