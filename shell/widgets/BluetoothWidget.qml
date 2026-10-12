import Quickshell

import "."
import "../../services" as Services

// BluetoothWidget — adapter on/off and device connected (ticket 13).
// Icon choice lives here, not in BluetoothService (ADR 0001).
SimpleBarWidget {
    id: bluetooth

    readonly property var adapter: Services.BluetoothService.defaultAdapter
    readonly property bool hasDeviceConnected: Services.BluetoothService.hasDeviceConnected

    readonly property string adapterState: adapter ? "present" : "absent"

    readonly property string glyphIcon: {
        if (!bluetooth.adapter) {
            return "󰂲"
        }
        if (!bluetooth.adapter.enabled) {
            return "󰂲"
        }
        if (bluetooth.hasDeviceConnected) {
            return "󰂱"
        }
        if (bluetooth.adapter.discoverable) {
            return "󰂳"
        }
        return ""
    }

    readonly property string barLabel: bluetooth.glyphIcon
    label: bluetooth.barLabel

    tooltip: {
        if (!bluetooth.adapter) {
            return "Bluetooth unavailable"
        }
        if (!bluetooth.adapter.enabled) {
            return "Bluetooth off"
        }
        if (bluetooth.hasDeviceConnected) {
            return "Bluetooth on — device connected"
        }
        return "Bluetooth on"
    }

    activate: function (widget) {
        Quickshell.execDetached(["nosarch-launch-tui", "bluetui"])
    }
}
