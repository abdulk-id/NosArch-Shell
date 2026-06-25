import Quickshell
import Quickshell.Networking
import QtQuick

import "../../ui" as UI

Item {
    id: networkModule

    implicitWidth: networkText.implicitWidth
    implicitHeight: networkText.implicitHeight

    readonly property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    readonly property string ethernetIcon: "󰀂"
    readonly property string disconnectedIcon: "󰤮"
    readonly property string portalIcon: "󰖟"
    readonly property string limitedIcon: "󰤬"
    readonly property string unknownIcon: "󰤫"

    readonly property var activeNetworkInfo: {
        for (let i = 0; i < Networking.devices.values.length; i++) {
            let device = Networking.devices.values[i];
            if (device.connected && device.state === ConnectionState.Connected) {
                if (device.type === DeviceType.Wifi) {
                    for (let j = 0; j < device.networks.values.length; j++) {
                        let network = device.networks.values[j];
                        if (network.state === ConnectionState.Connected) {
                            return {
                                device: device,
                                network: network,
                                strength: network.signalStrength
                            };
                        }
                    }
                }
                return {
                    device: device,
                    network: null,
                    strength: null
                };
            }
        }
        return null;
    }

    Text {
        id: networkText

        text: {
            let info = networkModule.activeNetworkInfo;
            let connectivity = Networking.connectivity;

            if (!info) {
                if (connectivity === NetworkConnectivity.Portal) {
                    return networkModule.portalIcon;
                } else if (connectivity === NetworkConnectivity.Limited) {
                    return networkModule.limitedIcon;
                } else if (connectivity === NetworkConnectivity.None) {
                    return networkModule.disconnectedIcon;
                } else {
                    return networkModule.unknownIcon;
                }
            }

            let device = info.device;
            let strength = info.strength;

            if (device.type === DeviceType.Wifi && strength !== null) {
                let iconIndex = Math.min(Math.floor(strength * 4), 4);
                return networkModule.wifiIcons[iconIndex];
            } else if (device.type === DeviceType.Wired) {
                return networkModule.ethernetIcon;
            }

            return networkModule.unknownIcon;
        }
        color: {
            let connectivity = Networking.connectivity;
            if (connectivity === NetworkConnectivity.None || connectivity === NetworkConnectivity.Unknown) {
                return UI.Colors.foregroundMuted;
            } else if (connectivity === NetworkConnectivity.Limited || connectivity === NetworkConnectivity.Portal) {
                return "#ffb86c";
            }
            return UI.Colors.foreground;
        }
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }
    }

    MouseArea {
        id: networkMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: Quickshell.execDetached(["nosarch-launch-tui", "nmtui"])
    }

    Connections {
        target: Networking
        function onConnectivityChanged() {
        }
    }
}
