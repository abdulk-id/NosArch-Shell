pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
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

    property string activeInterface: {
        let device = networkService.activeDevice;
        if (device) {
            return device.name;
        }
        return "";
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

    // IP Address
    property string ipAddress: ""
    Process {
        id: ipProcess

        command: ["sh", "-c", "nmcli --terse --fields IP4.ADDRESS device show " + networkService.activeInterface]

        stdout: SplitParser {
            onRead: data => {
                if (!data) {
                    return;
                }

                if (data.startsWith("IP4.ADDRESS[1]:")) {
                    let addr = data.substring("IP4.ADDRESS[1]:".length).trim();
                    let slashIndex = addr.indexOf("/");
                    if (slashIndex !== -1) {
                        networkService.ipAddress = addr.substring(0, slashIndex);
                    } else {
                        networkService.ipAddress = addr;
                    }
                }
            }
        }
    }

    // Traffic stats
    property real bytesReceived: 0
    property real bytesSent: 0
    property real rxSpeed: 0
    property real txSpeed: 0

    property string rxSpeedText: formatSpeed(rxSpeed)
    property string txSpeedText: formatSpeed(txSpeed)
    property string totalReceivedText: formatBytes(bytesReceived)
    property string totalSentText: formatBytes(bytesSent)

    onActiveInterfaceChanged: {
        _previousRx = 0;
        _previousTx = 0;
        _previousTimestamp = 0;
        rxSpeed = 0;
        txSpeed = 0;
    }

    function formatBytes(bytes) {
        if (bytes < 1024) {
            return bytes.toFixed(0) + " B";
        } else if (bytes < 1024 * 1024) {
            return (bytes / 1024).toFixed(1) + " KB";
        } else if (bytes < 1024 * 1024 * 1024) {
            return (bytes / 1024 / 1024).toFixed(1) + " MB";
        } else {
            return (bytes / 1024 / 1024 / 1024).toFixed(2) + " GB";
        }
    }

    function formatSpeed(bytesPerSec) {
        if (bytesPerSec < 1024) {
            return bytesPerSec.toFixed(0) + " B/s";
        } else if (bytesPerSec < 1024 * 1024) {
            return (bytesPerSec / 1024).toFixed(1) + " KB/s";
        } else {
            return (bytesPerSec / 1024 / 1024).toFixed(1) + " MB/s";
        }
    }

    // Traffic stats process
    property real _previousRx: 0
    property real _previousTx: 0
    property real _previousTimestamp: 0

    Process {
        id: trafficProcess

        command: ["sh", "-c", "cat /proc/net/dev"]

        stdout: SplitParser {
            onRead: data => {
                if (!data) {
                    return;
                }

                let iface = networkService.activeInterface;
                if (!iface) {
                    return;
                }

                // Lines look like: "  wlan0: 12345 678 0 ... 98765 432 0 ..."
                if (data.trim().startsWith(iface + ":")) {
                    let parts = data.trim().split(/\s+/);
                    // parts[0] is "iface:", parts[1] is RX bytes, parts[9] is TX bytes
                    if (parts.length >= 10) {
                        let currentRx = parseFloat(parts[1]);
                        let currentTx = parseFloat(parts[9]);
                        let now = Date.now() / 1000;

                        if (networkService._previousTimestamp > 0) {
                            let dt = now - networkService._previousTimestamp;
                            if (dt > 0) {
                                networkService.rxSpeed = (currentRx - networkService._previousRx) / dt;
                                networkService.txSpeed = (currentTx - networkService._previousTx) / dt;
                            }
                        }

                        networkService._previousRx = currentRx;
                        networkService._previousTx = currentTx;
                        networkService._previousTimestamp = now;
                        networkService.bytesReceived = currentRx;
                        networkService.bytesSent = currentTx;
                    }
                }
            }
        }
    }

    // Update Timer
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (networkService.activeInterface) {
                ipProcess.running = true;
                trafficProcess.running = true;
            }
        }
    }
}
