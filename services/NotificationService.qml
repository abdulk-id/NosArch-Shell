pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: notifService

    property list<var> notifications: []
    property bool doNotDisturb: false
    readonly property int count: notifications.length
    property int _seqCounter: 0

    Component {
        id: notifDataComp
        NotificationData {}
    }

    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        keepOnReload: false

        onNotification: function (notification) {
            if (notifService.doNotDisturb) {
                return;
            }

            if (!notification.appName && !notification.summary && !notification.body && !notification.image) {
                return;
            }

            notification.tracked = true;

            const idString = String(notification.id || "");
            if (idString !== "") {
                const existing = notifService.notifications.find(function (notification) {
                    return notification.notifId === idString;
                });

                if (existing && !existing.closed) {
                    existing.closed = true;
                    notifService.notifications = notifService.notifications.filter(function (notification) {
                        return notification !== existing;
                    });
                    existing.destroy();
                }
            }

            const data = notifDataComp.createObject(notifService, {
                notification: notification,
                seqId: String(notifService._seqCounter++)
            });

            notifService.notifications = [data, ...notifService.notifications];

            if (notifService.notifications.length > 5) {
                notifService.notifications[notifService.notifications.length - 1].dismiss();
            }
        }
    }

    function _remove(notifData): void {
        notifService.notifications = notifService.notifications.filter(function (notification) {
            return notification !== notifData;
        });
    }

    function dismiss(notifData): void {
        if (notifData) {
            notifData.dismiss();
        }
    }

    function dismissAll(): void {
        const toRemove = [...notifService.notifications];
        notifService.notifications = [];
        for (const notification of toRemove) {
            if (!notification.closed) {
                notification.closed = true;
                if (notification.notification) {
                    try {
                        notification.notification.dismiss();
                    } catch (e) {}
                }
                notification.destroy();
            }
        }
    }
}
