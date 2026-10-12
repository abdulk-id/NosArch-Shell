import QtQuick
import Quickshell
import Quickshell.Services.UPower

import "."
import "../ui" as UI
import "../../services" as Services

// BatteryWidget — charge percentage with low-charge colouring (ticket 13).
// Icon choice lives here, not in SystemInfo (ADR 0001).
BarWidget {
    id: battery

    readonly property bool present: Services.SystemInfo.battery.present
    readonly property int percentage: Services.SystemInfo.battery.percentage
    readonly property bool charging: Services.SystemInfo.battery.charging
    readonly property bool fullyCharged: Services.SystemInfo.battery.fullyCharged
    readonly property bool pendingCharge: Services.SystemInfo.battery.pendingCharge

    readonly property var defaultIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    readonly property var chargingIcons: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]

    readonly property string glyphIcon: {
        if (!battery.present) {
            return ""
        }

        const iconIndex = Math.min(Math.floor(battery.percentage / 10), 9)

        if (battery.fullyCharged) {
            if (UPower.onBattery) {
                return battery.defaultIcons[iconIndex]
            }
            return battery.chargingIcons[iconIndex]
        }
        if (battery.charging) {
            return battery.chargingIcons[iconIndex]
        }
        if (battery.pendingCharge) {
            return ""
        }
        return battery.defaultIcons[iconIndex]
    }

    readonly property string barLabel: battery.present
        ? (battery.glyphIcon + " " + battery.percentage + "%")
        : ""

    // Reported for verification: which colour tier the widget chose.
    readonly property string colorRole: {
        if (!battery.present) {
            return "absent"
        }
        if (battery.percentage <= 10) {
            return "critical"
        }
        if (battery.percentage <= 20) {
            return "warning"
        }
        return "normal"
    }

    readonly property color labelColor: {
        if (battery.colorRole === "critical") {
            return UI.Colors.alertRed
        }
        if (battery.colorRole === "warning") {
            return "#ffb86c"
        }
        return UI.Colors.foreground
    }

    visible: battery.present

    tooltip: battery.present
        ? ("Battery " + battery.percentage + "%"
            + (battery.charging ? " (charging)" : ""))
        : ""

    activate: function (widget) {
        Quickshell.execDetached(["sh", "-c",
            "vicinae vicinae://launch/@botkooper/store.vicinae.power-profile/power-profile"])
    }

    content: Component {
        Text {
            text: battery.barLabel
            color: battery.labelColor
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSize
            }
        }
    }
}
