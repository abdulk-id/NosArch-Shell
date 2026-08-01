pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    id: networkService

    readonly property NetworkDevice activeDevice: {
        for (let i = 0; i < Networking.devices.values.length; i++) {
            let device = Networking.devices.values[i];

            if (device.connected && device.state === ConnectionState.Connected) {
                return device;
            }
        }
        return null;
    }

    readonly property bool isActiveDeviceWired: {
        let device = networkService.activeDevice;
        return device !== null && device.type === DeviceType.Wired;
    }
    readonly property bool isActiveDeviceWireless: {
        let device = networkService.activeDevice;
        return device !== null && device.type === DeviceType.Wifi;
    }

    readonly property Network activeNetwork: {
        let device = networkService.activeDevice;
        if (!device) {
            return null;
        }

        for (let j = 0; j < device.networks.values.length; j++) {
            let network = device.networks.values[j];
            if (network.connected) {
                return network;
            }
        }
    }

    // Text icon
    readonly property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    readonly property string ethernetIcon: "󰀂"
    readonly property string portalIcon: "󰖟"
    readonly property string limitedIcon: "󰤬"
    readonly property string unknownIcon: "󰤫"
    readonly property string disconnectedIcon: "󰤮"

    readonly property string textIcon: {
        let device = networkService.activeDevice;
        if (device === null) {
            if (Networking.connectivity === NetworkConnectivity.None) {
                return networkService.disconnectedIcon;
            } else {
                return networkService.unknownIcon;
            }
        }

        let connectivity = Networking.connectivity;
        if (connectivity === NetworkConnectivity.Full) {
            if (device.type === DeviceType.Wifi) {
                let network = networkService.activeNetwork;
                if (network) {
                    let iconIndex = Math.min(Math.floor(network.signalStrength * 4), 4);
                    return networkService.wifiIcons[iconIndex];
                }
            } else if (device.type === DeviceType.Wired) {
                return networkService.ethernetIcon;
            }
        } else if (connectivity === NetworkConnectivity.Limited) {
            return networkService.limitedIcon;
        } else if (connectivity === NetworkConnectivity.Portal) {
            return networkService.portalIcon;
        } else if (connectivity === NetworkConnectivity.None) {
            return networkService.disconnectedIcon;
        }
        return networkService.unknownIcon;
    }
}
