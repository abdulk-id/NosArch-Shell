pragma Singleton

import Quickshell
import Quickshell.Bluetooth

// Only works with the default bluetooth adapter
Singleton {
    id: bluetoothService

    readonly property BluetoothAdapter defaultAdapter: Bluetooth.defaultAdapter

    readonly property var allDevices: Bluetooth.devices
    readonly property var defaultAdapterDevices: {
        if (defaultAdapter) {
            return defaultAdapter.devices;
        }
        return null;
    }

    readonly property bool hasDeviceConnected: {
        for (let i = 0; i < allDevices.values.length; i++) {
            if (allDevices.values[i].connected) {
                return true;
            }
        }
        return false;
    }

    readonly property string textIcon: {
        if (defaultAdapter) {
            if (defaultAdapter.enabled) {
                if (hasDeviceConnected) {
                    return "󰂱";
                } else if (defaultAdapter.discoverable) {
                    return "󰂳";
                } else {
                    return "";
                }
            } else {
                return "󰂲";
            }
        } else {
            return "󰂲";
        }
    }
}
