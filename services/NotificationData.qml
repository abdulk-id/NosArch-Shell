import QtQuick
import Quickshell.Services.Notifications

QtObject {
    id: notifData

    property Notification notification: null

    property string seqId: ""

    // Notification data
    property string notifId: ""
    property string summary: ""
    property string body: ""
    property string appIcon: ""
    property string appName: ""
    property string image: ""
    property int urgency: NotificationUrgency.Normal
    property var actions: []
    property real expireTimeout: defaultTimeout
    readonly property int defaultTimeout: 5000  // ms — fallback auto-dismiss when app sends -1/0

    // UI State
    property bool closed: false
    property bool hovered: false

    readonly property Connections _conn: Connections {
        target: notifData.notification

        function onClosed(): void {
            if (notifData.closed)
                return;
            notifData.closed = true;
            NotificationService._remove(notifData);
            notifData.destroy();
        }

        function onSummaryChanged(): void {
            if (notifData.notification) {
                notifData.summary = notifData.notification.summary || "";
            }
        }
        function onBodyChanged(): void {
            if (notifData.notification) {
                notifData.body = notifData.notification.body || "";
            }
        }
        function onAppIconChanged(): void {
            if (notifData.notification) {
                notifData.appIcon = notifData.notification.appIcon || "";
            }
        }
        function onAppNameChanged(): void {
            if (notifData.notification) {
                notifData.appName = notifData.notification.appName || "";
            }
        }
        function onImageChanged(): void {
            if (notifData.notification) {
                notifData.image = notifData.notification.image || "";
            }
        }
        function onUrgencyChanged(): void {
            if (notifData.notification) {
                notifData.urgency = notifData.notification.urgency;
            }
        }
        function onExpireTimeoutChanged(): void {
            if (notifData.notification) {
                notifData.expireTimeout = notifData.notification.expireTimeout;
            }
        }
        function onActionsChanged(): void {
            if (!notifData.notification) {
                return;
            }

            notifData.actions = notifData.notification.actions.map(function (action) {
                return {
                    identifier: action.identifier,
                    text: action.text
                };
            });
        }
    }

    readonly property Timer _timer: Timer {
        running: !notifData.closed && !notifData.hovered && notifData.urgency !== NotificationUrgency.Critical
        interval: notifData.expireTimeout > 0 ? notifData.expireTimeout : notifData.defaultTimeout  // no * 1000: Quickshell passes raw D-Bus ms, not seconds
        onTriggered: {
            notifData.dismiss();
        }
    }

    Component.onCompleted: {
        if (!notification) {
            return;
        }

        notifId = String(notification.id || "");
        summary = notification.summary || "";
        body = notification.body || "";
        appIcon = notification.appIcon || "";
        appName = notification.appName || "";
        image = notification.image || "";
        urgency = notification.urgency;

        const rawTimeout = notification.expireTimeout;
        expireTimeout = rawTimeout > 0 ? rawTimeout : defaultTimeout;

        actions = notification.actions.map(function (action) {
            return {
                identifier: action.identifier,
                text: action.text
            };
        });
    }

    function dismiss(): void {
        if (closed) {
            return;
        }

        closed = true;
        NotificationService._remove(notifData);

        if (notification) {
            try {
                notification.dismiss();
            } catch (e) {}
        }

        destroy();
    }

    function invokeAction(identifier): void {
        if (!identifier || closed) {
            return;
        }

        closed = true;
        NotificationService._remove(notifData);

        if (notification) {
            const action = notification.actions.find(function (action) {
                return action.identifier === identifier;
            });
            if (action) {
                try {
                    action.invoke();
                } catch (e) {}
            }
        }

        destroy();
    }
}
