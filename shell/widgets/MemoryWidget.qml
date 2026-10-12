import Quickshell

import "."
import "../../services" as Services

// MemoryWidget — memory usage indicator (ticket 13).
SimpleBarWidget {
    id: memory

    readonly property string monitorTarget: "btop"

    readonly property real usedGib: Services.SystemInfo.memory.totalGib
        - Services.SystemInfo.memory.availableGib

    readonly property string barLabel: "  " + memory.usedGib.toFixed(1) + "/"
        + Services.SystemInfo.memory.totalGib.toFixed(1) + " GiB"
    label: memory.barLabel

    tooltip: memory.barLabel

    activate: function (widget) {
        Quickshell.execDetached(["nosarch-launch-tui", "btop"])
    }
}
