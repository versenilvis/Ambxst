pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property int maxStoredNotifications: 50

    function notifToJSON(notif) {
        return {
            "id": notif.id,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
            "isCached": notif.isCached
        };
    }

    component NotifTimer: Timer {
        required property int id
        property int originalInterval: 5000
        property bool isPaused: false
        property real startTime: Date.now()

        interval: originalInterval
        running: !isPaused

        function pause() {
            if (!isPaused) {
                isPaused = true;
                stop();
            }
        }

        function resume() {
            if (isPaused) {
                isPaused = false;
                interval = originalInterval;
                startTime = Date.now();
                start();
            }
        }

        function triggerTimeout() {
            delete root.timersById[id];
            root.timeoutNotification(id);
            destroy();
        }

        onTriggered: triggerTimeout()

        onRunningChanged: {
            if (running) {
                startTime = Date.now();
            }
        }
    }

    property bool silent: false
    property var list: []
    property var popupList: list.filter(notif => notif.popup)
    property bool popupInhibited: silent
    property var latestTimeForApp: ({})
    property var totalCounts: ({})  // Conteo total independiente del almacenamiento: {appName: {summary: count}}
    property var timersById: ({})

    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    FileView {
        id: notifFileView
        path: Quickshell.dataPath("notifications.json")
        onLoaded: loadNotifications()
    }

    function stringifyList(list) {
        return JSON.stringify(list.map(notif => notifToJSON(notif)), null, 2);
    }

    function jsonToNotif(json) {
        return {
            "id": json.id,
            "actions": json.actions || [],
            "appIcon": json.appIcon || "",
            "appName": json.appName,
            "body": json.body,
            "image": json.image || "",
            "summary": json.summary,
            "time": json.time,
            "urgency": json.urgency,
            "isCached": json.isCached !== undefined ? json.isCached : true,
            "popup": false  // No popup para notificaciones cargadas
        };
    }

    function notificationToObject(notification) {
        const id = notification.id + root.idOffset;
        notification.closed.connect(function (reason) {
            if (reason === 3) {
                root.discardNotification(id);
            }
        });
        return {
            "id": id,
            "actions": notification.actions ? notification.actions.map(action => ({
                        "identifier": action.identifier,
                        "text": action.text
                    })) : [],
            "appIcon": notification.appIcon || "",
            "appName": notification.appName || "",
            "body": notification.body || "",
            "image": notification.image || "",
            "summary": notification.summary || "",
            "time": Date.now(),
            "urgency": notification.urgency !== undefined ? notification.urgency.toString() : "normal",
            "isCached": false,
            "popup": false
        };
    }

    function saveNotifications() {
        // Limitar notificaciones almacenadas a 5 por summary para evitar almacenamiento excesivo
        const limitedList = trimStoredNotifications(limitNotificationsPerSummary(root.list));
        notifFileView.setText(stringifyList(limitedList));
    }

    function limitNotificationsPerSummary(notifications) {
        var groups = {};

        notifications.forEach(notif => {
            const key = notif.appName + '|' + (notif.summary || '');
            if (!groups[key]) {
                groups[key] = [];
            }
            groups[key].push(notif);
        });

        const limitedNotifications = [];
        for (const key in groups) {
            const group = groups[key];
            group.sort((a, b) => b.time - a.time);
            limitedNotifications.push(...group.slice(0, 5));
        }

        return limitedNotifications;
    }

    function loadNotifications() {
        try {
            const data = JSON.parse(notifFileView.text());
            root.list = trimStoredNotifications(data.map(jsonToNotif));
            // Set idOffset to max id + 1
            let maxId = 0;
            root.list.forEach(notif => {
                if (notif.id > maxId)
                    maxId = notif.id;
            });
            root.idOffset = maxId + 1;
        } catch (e) {
            console.log("No saved notifications or error loading:", e);
            root.list = [];
            root.idOffset = 0;
        }
    }

    onListChanged: {
        // Update latest time for each app
        root.list.forEach(notif => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach(appName => {
            if (!root.list.some(notif => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif, index) => {
            // Verificar que la notificación es válida antes de agruparla
            if (!notif || !notif.appName || (!notif.summary && !notif.body)) {
                return;
            }

            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0,
                    totalCount: 0  // Conteo independiente del almacenamiento
                };
            }
            groups[notif.appName].notifications.push(notif);
            groups[notif.appName].totalCount++;
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });

        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property var appNameList: appNameListForGroups(root.groupsByAppName)
    property var popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone
    signal notify(notification: var)
    signal discard(id: var)
    signal discardAll
    signal timeout(id: var)

    NotificationServer {
        id: notifServer
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: notification => {
            // Verificar que la notificación tiene contenido válido antes de procesarla
            if (!notification || (!notification.summary && !notification.body)) {
                return;
            }

            notification.tracked = true;
            const newNotifObject = notificationToObject(notification);

            // Usar Qt.callLater para evitar race conditions al actualizar la lista
            Qt.callLater(() => {
                root.list = trimStoredNotifications([...root.list, newNotifObject]);
                saveNotifications();
            });

            // Popup - ahora se muestra en el notch en lugar de popup window
            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                root.timersById[newNotifObject.id] = notifTimerComponent.createObject(root, {
                    "id": newNotifObject.id,
                    "interval": notification.expireTimeout <= 0 ? 5000 : notification.expireTimeout // use default timeout if app sends 0 or less
                });
            }

            root.notify(newNotifObject);
        }
    }

    function trimStoredNotifications(notifications) {
        if (notifications.length <= root.maxStoredNotifications)
            return notifications;

        const sorted = notifications.slice(0).sort((a, b) => b.time - a.time);
        const keepById = {};
        sorted.slice(0, root.maxStoredNotifications).forEach(notif => {
            keepById[notif.id] = true;
        });
        return notifications.filter(notif => keepById[notif.id]);
    }

    function discardNotification(id) {
        const index = root.list.findIndex(notif => notif.id === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex(notif => notif.id + root.idOffset === id);
        if (index !== -1) {
            root.list.splice(index, 1);
            destroyTimer(id);
            triggerListChange();
            saveNotifications();
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss();
        }
        root.discard(id);
    }

    function discardNotifications(ids) {
        if (!ids || ids.length === 0)
            return;

        var idsMap = {};
        ids.forEach(id => {
            idsMap[id] = true;
        });

        const newList = root.list.filter(notif => !idsMap[notif.id]);
        const removedCount = root.list.length - newList.length;

        if (removedCount > 0) {
            root.list = newList;
            ids.forEach(id => destroyTimer(id));
            triggerListChange();
            saveNotifications();
        }

        ids.forEach(id => {
            const notifServerIndex = notifServer.trackedNotifications.values.findIndex(notif => notif.id + root.idOffset === id);
            if (notifServerIndex !== -1) {
                notifServer.trackedNotifications.values[notifServerIndex].dismiss();
            }
            root.discard(id);
        });
    }

    function discardAllNotifications() {
        Object.keys(root.timersById).forEach(id => destroyTimer(id));
        root.list = [];
        triggerListChange();
        saveNotifications();
        notifServer.trackedNotifications.values.forEach(notif => {
            notif.dismiss();
        });
        root.discardAll();
    }

    signal timeoutWithAnimation(id: var)

    Timer {
        id: timeoutAnimationTimer
        interval: 350
        running: false
        repeat: false
        property int notificationId: -1
        onTriggered: {
            const index = root.list.findIndex(notif => notif.id === notificationId);
            if (index !== -1 && root.list[index] != null) {
                root.list[index].popup = false;
                triggerListChange();
            }
            root.timeout(notificationId);
        }
    }

    function timeoutNotification(id) {
        root.timeoutWithAnimation(id);
        timeoutAnimationTimer.notificationId = id;
        timeoutAnimationTimer.restart();
    }

    function timeoutAll() {
        root.popupList.forEach(notif => {
            root.timeout(notif.id);
        });
        root.popupList.forEach(notif => {
            notif.popup = false;
            destroyTimer(notif.id);
        });
        triggerListChange();
    }

    function attemptInvokeAction(id, notifIdentifier, autoDiscard = true) {
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex(notif => notif.id + root.idOffset === id);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find(action => action.identifier === notifIdentifier);
            action.invoke();
        } else {}
        if (autoDiscard) {
            root.discardNotification(id);
        }
    }

    function pauseGroupTimers(appName) {
        root.popupList.forEach(notif => {
            const timer = root.timersById[notif.id];
            if (notif.appName === appName && timer) {
                timer.pause();
            }
        });
    }

    function resumeGroupTimers(appName) {
        root.popupList.forEach(notif => {
            const timer = root.timersById[notif.id];
            if (notif.appName === appName && timer) {
                timer.resume();
            }
        });
    }

    function pauseAllTimers() {
        root.popupList.forEach(notif => {
            const timer = root.timersById[notif.id];
            if (timer) {
                timer.pause();
            }
        });
    }

    function resumeAllTimers() {
        root.popupList.forEach(notif => {
            const timer = root.timersById[notif.id];
            if (timer) {
                timer.resume();
            }
        });
    }

    function hideAllPopups() {
        root.popupList.forEach(notif => {
            notif.popup = false;
            destroyTimer(notif.id);
        });
        triggerListChange();
    }

    function triggerListChange() {
        root.list = root.list.slice(0);
    }

    function destroyTimer(id) {
        const timer = root.timersById[id];
        if (!timer)
            return;
        timer.stop();
        timer.destroy();
        delete root.timersById[id];
    }

    Component.onCompleted: {
        notifFileView.reload();
        root.initDone();
    }
}
