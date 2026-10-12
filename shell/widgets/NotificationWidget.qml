import QtQuick

import "."
import "../ui" as UI
import "../../services" as Services

// NotificationWidget — waiting indicator and do-not-disturb toggle (ticket 16).
//
// The bar shows whether anything is waiting (accent while notifications are
// queued), toggles do-not-disturb on click, and uses a distinct icon and colour
// while DND is active. Do-not-disturb is read from NotificationService, which
// in turn reads ShellState — one value for the indicator and for suppressing
// incoming notifications.
BarWidget {
    id: notification

    readonly property bool doNotDisturb: Services.NotificationService.doNotDisturb
    readonly property int waitingCount: Services.NotificationService.count
    readonly property bool hasWaiting: notification.waitingCount > 0

    readonly property string visualRole: notification.doNotDisturb
        ? "dnd"
        : (notification.hasWaiting ? "waiting" : "idle")

    readonly property string indicatorIcon: notification.doNotDisturb ? "" : ""

    tooltip: notification.doNotDisturb
        ? "Do not disturb is on"
        : (notification.hasWaiting
            ? notification.waitingCount + " notification(s) waiting"
            : "No notifications waiting")

    activate: function (widget) {
        Services.NotificationService.toggleDoNotDisturb()
    }

    content: Component {
        Text {
            text: notification.indicatorIcon
            color: notification.doNotDisturb || notification.hasWaiting
                ? UI.Colors.accent
                : UI.Colors.foreground
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSize
            }
        }
    }
}
