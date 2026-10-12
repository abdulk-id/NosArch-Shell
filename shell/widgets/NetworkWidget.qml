import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking

import "."
import "../ui" as UI
import "../../components" as Components
import "../../services" as Services

BarWidget {
    id: network

    widgetName: "network"

    readonly property var icon: Components.NetworkIcon {}

    tooltip: network.icon.statusLine

    activate: function (widget) {
        widget.togglePanel(widget.panelId)
    }

    readonly property color glyphColor: {
        if (network.icon.isCaptivePortal) {
            return UI.Colors.accent
        }
        if (network.icon.isOffline || network.icon.connectivity === NetworkConnectivity.Limited) {
            return UI.Colors.foregroundMuted
        }
        return UI.Colors.foreground
    }

    ListModel { id: knownNetworksModel }
    ListModel { id: unknownNetworksModel }

    Timer {
        id: scanRefreshTimer
        interval: 3000
        repeat: false
        onTriggered: {
            network.refreshNetworkLists()
            const device = Services.NetworkService.activeDevice
            if (device && device.type === DeviceType.Wifi) {
                device.scannerEnabled = false
            }
        }
    }

    function triggerScan() {
        const device = Services.NetworkService.activeDevice
        if (!device || device.type !== DeviceType.Wifi) {
            return
        }
        device.scannerEnabled = true
        refreshNetworkLists()
        scanRefreshTimer.restart()
    }

    function refreshNetworkLists() {
        knownNetworksModel.clear()
        unknownNetworksModel.clear()

        const device = Services.NetworkService.activeDevice
        if (!device || device.type !== DeviceType.Wifi) {
            return
        }

        for (let i = 0; i < device.networks.values.length; i++) {
            const net = device.networks.values[i]
            if (net.connected) {
                continue
            }

            const entry = {
                "name": net.name,
                "signalIcon": network.icon.signalIconFor(net.signalStrength),
                "securityText": network.getSecurityLabel(net.security),
                "isOpen": net.security === WifiSecurityType.Open
            }

            if (net.known) {
                knownNetworksModel.append(entry)
            } else {
                unknownNetworksModel.append(entry)
            }
        }
    }

    function getSecurityLabel(networkSecurity) {
        switch (networkSecurity) {
        case WifiSecurityType.StaticWep: return "Static WEP"
        case WifiSecurityType.Sae: return "SAE"
        case WifiSecurityType.Owe: return "OWE"
        case WifiSecurityType.WpaPsk: return "WPA-PSK"
        case WifiSecurityType.Wpa2Psk: return "WPA2-PSK"
        case WifiSecurityType.WpaEap: return "WPA-EAP"
        case WifiSecurityType.Wpa2Eap: return "WPA2-EAP"
        case WifiSecurityType.Wpa3SuiteB192: return "WPA3-192"
        case WifiSecurityType.DynamicWep: return "802.1X WEP"
        case WifiSecurityType.Leap: return "LEAP"
        case WifiSecurityType.Open: return "Open"
        default: return networkSecurity.toString()
        }
    }

    function connectToNetwork(name: string) {
        const device = Services.NetworkService.activeDevice
        if (!device) {
            return
        }
        for (let i = 0; i < device.networks.values.length; i++) {
            const net = device.networks.values[i]
            if (net.name === name) {
                net.connect()
                break
            }
        }
    }

    panelContent: Component {
        ColumnLayout {
            spacing: 10
            Layout.preferredWidth: 360

            onVisibleChanged: {
                if (visible) {
                    network.refreshNetworkLists()
                    network.triggerScan()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: network.icon.glyph
                    color: network.glyphColor
                    font {
                        family: UI.Fonts.fontFamily
                        pixelSize: UI.Fonts.fontSizeIcons
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: network.icon.statusLine
                    color: UI.Colors.foreground
                    font {
                        family: UI.Fonts.fontFamily
                        pixelSize: UI.Fonts.fontSizeSmall
                        bold: true
                    }
                    elide: Text.ElideRight
                }

                Button {
                    visible: network.icon.isWireless || network.icon.wifiEnabled
                    implicitWidth: 30
                    implicitHeight: 26
                    focus: false
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled

                    background: Rectangle {
                        radius: 6
                        color: parent.down ? UI.Colors.backgroundSurface : UI.Colors.backgroundHover
                    }
                    contentItem: Text {
                        text: Networking.wifiEnabled ? "󰤨" : "󰤮"
                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: "IP: " + (Services.NetworkService.ipAddress || "—")
                    color: UI.Colors.foregroundSecondary
                    font {
                        family: UI.Fonts.fontFamily
                        pixelSize: UI.Fonts.fontSizeSmall
                    }
                }

                RowLayout {
                    id: networkSpeedsTextRow
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: "Download: " + network.icon.rxSpeedText
                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }
                    Text {
                        text: "Upload: " + network.icon.txSpeedText
                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !Services.NetworkService.activeDevice
                text: "No network adapter detected"
                color: UI.Colors.foregroundMuted
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSizeSmall
                }
                wrapMode: Text.WordWrap
            }

            Text {
                text: "Saved networks"
                visible: knownNetworksModel.count > 0
                color: UI.Colors.foreground
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSizeSmall
                    bold: true
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 140)
                visible: count > 0
                model: knownNetworksModel
                clip: true
                spacing: 4

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 36
                    radius: 6
                    color: savedMouse.containsMouse ? UI.Colors.backgroundHover : UI.Colors.backgroundSurface

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Text {
                            text: model.signalIcon
                            color: UI.Colors.foreground
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeIcons
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: model.name
                            color: UI.Colors.foreground
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }
                            elide: Text.ElideRight
                        }
                        Text {
                            text: model.securityText
                            color: UI.Colors.foregroundMuted
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }
                        }
                    }

                    MouseArea {
                        id: savedMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: network.connectToNetwork(model.name)
                    }
                }
            }

            Text {
                text: "Available networks"
                visible: unknownNetworksModel.count > 0
                color: UI.Colors.foreground
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSizeSmall
                    bold: true
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 180)
                visible: count > 0
                model: unknownNetworksModel
                clip: true
                spacing: 4

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 36
                    radius: 6
                    color: unknownMouse.containsMouse ? UI.Colors.backgroundHover : UI.Colors.backgroundSurface

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Text {
                            text: model.signalIcon
                            color: UI.Colors.foreground
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeIcons
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: model.name
                            color: UI.Colors.foreground
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: !model.isOpen
                            text: "󰌾"
                            color: UI.Colors.foregroundMuted
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }
                        }
                    }

                    MouseArea {
                        id: unknownMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: network.connectToNetwork(model.name)
                    }
                }
            }

            Button {
                Layout.fillWidth: true
                focus: true
                visible: network.icon.isWireless
                text: "Refresh networks"
                onClicked: network.triggerScan()
            }
        }
    }

    content: Component {
        Text {
            text: network.icon.glyph
            color: network.glyphColor
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSizeIcons
            }
        }
    }
}
