import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

import "../../ui" as UI

Item {
    id: networkModule

    required property QtObject popupState
    property PanelWindow topIsland

    readonly property string popupId: "network"

    // Module UI ===
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

        onClicked: {
            networkModule.popupState.set(networkModule.popupId);

            if (networkModule.popupState.activePopup === networkModule.popupId) {
                networkModule.updatePopupPosition();
            }

            popup.anchor.updateAnchor();
        }
    }
    // ===

    // Popup UI ===
    readonly property int popupGap: 10
    readonly property int popupMargin: 8
    readonly property int popupWidth: 360
    readonly property int popupHeight: 240

    PopupWindow {
        id: popup
        grabFocus: true

        // TODO: Currently hardcoding sizes. Should be size of `popupContents`
        implicitWidth: networkModule.popupWidth
        implicitHeight: networkModule.popupHeight

        anchor {
            window: networkModule.topIsland

            adjustment: PopupAdjustment.Slide
        }

        // Popup contents UI ===
        Rectangle {
            id: popupContents

            anchors.fill: parent

            color: UI.Colors.background
            border {
                color: UI.Colors.accent
                width: 1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.top: parent.top
                anchors.margins: networkModule.popupMargin

                RowLayout {
                    Layout.fillWidth: true

                    spacing: 5

                    // WiFi Toggle Button
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.margins: 10

                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30

                        color: UI.Colors.backgroundSurface
                        radius: 6

                        Text {
                            anchors.centerIn: parent
                            text: Networking.wifiEnabled ? "󰤨" : "󰤮"
                            color: Networking.wifiEnabled ? UI.Colors.foreground : UI.Colors.foregroundMuted
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSize
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                    }

                    // WiFi Status Text
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.margins: 10

                        text: {
                            if (!Networking.wifiEnabled) {
                                return "WiFi turned off";
                            }

                            let info = networkModule.activeNetworkInfo;
                            if (info && info.network) {
                                return info.network.name;
                            }
                            return "Not Connected";
                        }
                        color: UI.Colors.foreground
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSize
                            bold: true
                        }
                        elide: Text.ElideRight
                    }

                    // Gap element
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }
        // ===

        onVisibleChanged: {
            if (!visible) {
                networkModule.popupState.close();
            }
        }

        visible: networkModule.popupState && networkModule.popupState.isActive(networkModule.popupId)
    }

    function updatePopupPosition() {
        var pos = networkModule.topIsland.mapFromItem(networkModule, 0, 0);
        popup.anchor.rect = Qt.rect(pos.x + networkModule.implicitWidth / 2 - popup.implicitWidth / 2, networkModule.topIsland.implicitHeight + networkModule.popupGap, popup.implicitWidth, popup.implicitHeight);
    }
    // ===

    Connections {
        target: Networking
        function onConnectivityChanged() {
        }
    }
}
