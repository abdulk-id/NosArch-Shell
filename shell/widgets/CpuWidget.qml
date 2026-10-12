import Quickshell

import "."
import "../../services" as Services

// CpuWidget — CPU usage indicator (ticket 13).
SimpleBarWidget {
    id: cpu

    readonly property string monitorTarget: "btop"

    readonly property string barLabel: "󰍛 " + Services.SystemInfo.cpu.usagePercent + "%"
    label: cpu.barLabel

    tooltip: cpu.barLabel

    activate: function (widget) {
        Quickshell.execDetached(["nosarch-launch-tui", "btop"])
    }
}
