import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

import "../../ui" as UI
import "../../../services" as Services

Item {
    id: networkModule

    required property QtObject popupState
    property PanelWindow topIsland

    readonly property string popupId: "network"

    // Module UI ===
    implicitWidth: networkText.implicitWidth
    implicitHeight: networkText.implicitHeight

    Text {
        id: networkText

        text: Services.NetworkService.textIcon
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
    readonly property int popupTopIslandGap: 10
    readonly property int popupMargin: 5
    readonly property int popupSectionMargin: 10
    readonly property int popupWidth: 400
    readonly property int popupHeight: 600

    PopupWindow {
        id: popup
        grabFocus: true

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
                id: popupParentLayout

                anchors {
                    fill: parent

                    margins: networkModule.popupMargin
                }

                spacing: 0

                // WiFi Toggle Button, Status and Security Type Text
                RowLayout {
                    id: currentStatusSection

                    property int statusSectionHeight: 40

                    Layout.alignment: Qt.AlignCenter
                    Layout.margins: networkModule.popupSectionMargin

                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: statusSectionHeight
                    Layout.preferredHeight: statusSectionHeight
                    Layout.maximumHeight: statusSectionHeight

                    spacing: 15

                    // WiFi Toggle Button
                    Rectangle {
                        id: wifiToggleButton

                        Layout.alignment: Qt.AlignVCenter

                        Layout.preferredWidth: currentStatusSection.statusSectionHeight // width = height for square button
                        Layout.preferredHeight: currentStatusSection.statusSectionHeight

                        //color: UI.Colors.backgroundSurface
                        color: wifiToggleButtonMouseArea.containsMouse ? UI.Colors.backgroundHover : UI.Colors.backgroundSurface
                        radius: 6

                        Text {
                            id: wifiToggleButtonIcon

                            anchors.centerIn: parent

                            text: Services.NetworkService.textIcon
                            color: UI.Colors.foreground
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeIcons
                            }
                        }

                        MouseArea {
                            id: wifiToggleButtonMouseArea

                            anchors.fill: parent

                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                    }

                    // WiFi Status Text
                    Text {
                        id: wifiStatusText

                        Layout.alignment: Qt.AlignCenter

                        text: {
                            if (!Networking.wifiEnabled) {
                                return "WiFi turned off";
                            }

                            let network = Services.NetworkService.activeNetwork;
                            if (network) {
                                return network.name;
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

                    // WiFi Security Type text
                    Text {
                        id: wifiSecurityText

                        Layout.alignment: Qt.AlignCenter

                        text: {
                            if (Networking.wifiEnabled && Networking.connectivity !== NetworkConnectivity.None && Networking.connectivity !== NetworkConnectivity.Unknown) {
                                let wifiSecurityType = Services.NetworkService.activeNetwork.security;
                                return networkModule.getSecurityLabel(wifiSecurityType);
                            }
                        }
                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSize
                            bold: true
                        }
                        elide: Text.ElideRight

                        visible: Networking.wifiEnabled
                    }

                    /*
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        radius: 10
                        color: "#e74c3c"
                    }
                    */
                }

                // Separator
                Rectangle {
                    Layout.leftMargin: networkModule.popupSectionMargin
                    Layout.rightMargin: networkModule.popupSectionMargin

                    Layout.fillWidth: true
                    Layout.minimumHeight: 1
                    Layout.preferredHeight: 1
                    Layout.maximumHeight: 1

                    color: UI.Colors.backgroundSurface
                    opacity: 1
                }

                // Network Status Stepper
                ColumnLayout {
                    id: networkStepperSection

                    Layout.alignment: Qt.AlignCenter
                    Layout.margins: networkModule.popupSectionMargin

                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: 50
                    Layout.preferredHeight: 50
                    Layout.maximumHeight: 50

                    spacing: 4

                    // Stepper circles and connecting lines
                    Item {
                        id: stepperTrack

                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        Layout.minimumHeight: 20
                        Layout.maximumHeight: 20

                        readonly property int dotSize: 14
                        readonly property int dotRadius: 7
                        readonly property int lineHeight: 2

                        // Stage 1 dot
                        Rectangle {
                            id: stage1Dot

                            width: stepperTrack.dotSize
                            height: stepperTrack.dotSize
                            radius: stepperTrack.dotRadius

                            x: 0
                            y: (stepperTrack.height - height) / 2

                            color: networkModule.stage1Complete ? UI.Colors.accent : UI.Colors.backgroundSurface
                        }

                        // Line 1 (between stage 1 and 2)
                        Rectangle {
                            id: line1

                            height: stepperTrack.lineHeight
                            width: (stepperTrack.width - stepperTrack.dotSize * 3) / 2

                            x: stepperTrack.dotSize
                            y: (stepperTrack.height - height) / 2

                            color: networkModule.stage2Complete ? UI.Colors.accent : UI.Colors.backgroundSurface
                        }

                        // Stage 2 dot
                        Rectangle {
                            id: stage2Dot

                            width: stepperTrack.dotSize
                            height: stepperTrack.dotSize
                            radius: stepperTrack.dotRadius

                            x: (stepperTrack.width - width) / 2
                            y: (stepperTrack.height - height) / 2

                            color: networkModule.stage2Complete ? UI.Colors.accent : UI.Colors.backgroundSurface
                        }

                        // Line 2 (between stage 2 and 3)
                        Rectangle {
                            id: line2

                            height: stepperTrack.lineHeight
                            width: (stepperTrack.width - stepperTrack.dotSize * 3) / 2

                            x: (stepperTrack.width + stepperTrack.dotSize) / 2
                            y: (stepperTrack.height - height) / 2

                            color: networkModule.stage3Complete ? UI.Colors.accent : UI.Colors.backgroundSurface
                        }

                        // Stage 3 dot
                        Rectangle {
                            id: stage3Dot

                            width: stepperTrack.dotSize
                            height: stepperTrack.dotSize
                            radius: stepperTrack.dotRadius

                            x: stepperTrack.width - width
                            y: (stepperTrack.height - height) / 2

                            color: networkModule.stage3Complete ? UI.Colors.accent : UI.Colors.backgroundSurface
                        }
                    }

                    // Stepper labels
                    RowLayout {
                        id: stepperLabelsRow

                        Layout.fillWidth: true
                        Layout.minimumHeight: 15
                        Layout.preferredHeight: 15
                        Layout.maximumHeight: 15

                        spacing: 0

                        Text {
                            id: stage1Text

                            //Layout.preferredWidth: parent.width / 3

                            text: "WiFi Enabled"

                            color: UI.Colors.foregroundSecondary
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }

                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            id: stage2Text

                            //Layout.preferredWidth: parent.width / 3
                            Layout.fillWidth: true

                            text: "Connected"

                            color: UI.Colors.foregroundSecondary
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }

                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            id: stage3Text

                            //Layout.preferredWidth: parent.width / 3

                            text: "Internet"

                            color: UI.Colors.foregroundSecondary
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }

                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                // Network Stats Section
                ColumnLayout {
                    id: networkStatsSection

                    Layout.alignment: Qt.AlignCenter
                    Layout.margins: networkModule.popupSectionMargin

                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: ipAddrText.height + networkSpeedsTextRow.height + spacing
                    Layout.preferredHeight: ipAddrText.height + networkSpeedsTextRow.height + spacing
                    Layout.maximumHeight: ipAddrText.height + networkSpeedsTextRow.height + spacing

                    spacing: 5

                    // IP Address
                    Text {
                        id: ipAddrText

                        Layout.fillWidth: true
                        Layout.minimumHeight: 15
                        Layout.preferredHeight: 15
                        Layout.maximumHeight: 15

                        text: "IP: " + (Services.NetworkService.ipAddress || "--")
                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }

                    RowLayout {
                        id: networkSpeedsTextRow

                        Layout.fillWidth: true
                        Layout.maximumHeight: 15
                        Layout.preferredHeight: 15
                        Layout.minimumHeight: 15

                        spacing: 10

                        // Download speed
                        Text {
                            id: downloadSpeedText

                            text: "Download: " + (Services.NetworkService.rxSpeedText || "--")
                            color: UI.Colors.foregroundSecondary
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        // Upload speed
                        Text {
                            id: uploadSpeedText

                            text: "Upload: " + (Services.NetworkService.txSpeedText || "--")
                            color: UI.Colors.foregroundSecondary
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeSmall
                            }
                        }
                    }

                    /*
                    Layout.minimumHeight: 30
                    Layout.preferredHeight: 30
                    Layout.maximumHeight: 30

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        radius: 10
                        color: "#f39c12"
                    }
                    */

                    visible: Services.NetworkService.activeDevice !== null
                }

                // Separator
                Rectangle {
                    Layout.leftMargin: networkModule.popupSectionMargin
                    Layout.rightMargin: networkModule.popupSectionMargin
                    Layout.alignment: Qt.AlignCenter

                    Layout.fillWidth: true
                    Layout.minimumHeight: 1
                    Layout.preferredHeight: 1
                    Layout.maximumHeight: 1

                    color: UI.Colors.backgroundSurface
                    opacity: 1
                }

                // Saved Networks Section
                ColumnLayout {
                    id: savedNetworksSection

                    Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                    Layout.margins: networkModule.popupSectionMargin

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Header text
                    Text {
                        id: savedNetworksHeaderText

                        Layout.fillWidth: true
                        Layout.minimumHeight: 30
                        Layout.preferredHeight: 30
                        Layout.maximumHeight: 30

                        text: "Saved Networks"
                        color: UI.Colors.foreground
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }

                    ListView {
                        id: savedNetworksView

                        Layout.fillHeight: true
                        Layout.fillWidth: true

                        clip: true

                        model: knownNetworksModel
                        interactive: true

                        delegate: Rectangle {
                            id: savedNetworkItem

                            width: parent.width
                            height: 32

                            color: savedNetworkItemMouseArea.containsMouse ? UI.Colors.backgroundHover : UI.Colors.backgroundSurface
                            radius: 4

                            RowLayout {
                                id: savedNetworkItemLayout

                                anchors.fill: parent

                                spacing: 10

                                Text {
                                    id: savedNetworkSignalIcon

                                    text: model.signalIcon
                                    color: UI.Colors.foreground
                                    font {
                                        family: UI.Fonts.fontFamily
                                        pixelSize: UI.Fonts.fontSize
                                    }
                                }

                                Text {
                                    id: savedNetworkNameText

                                    Layout.fillWidth: true

                                    text: model.name
                                    color: UI.Colors.foreground
                                    font {
                                        family: UI.Fonts.fontFamily
                                        pixelSize: UI.Fonts.fontSize
                                    }
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: savedNetworkSecurityText

                                    text: model.securityText
                                    color: UI.Colors.foregroundSecondary
                                    font {
                                        family: UI.Fonts.fontFamily
                                        pixelSize: UI.Fonts.fontSizeSmall
                                    }
                                }
                            }

                            MouseArea {
                                id: savedNetworkItemMouseArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    let device = Services.NetworkService.activeDevice;
                                    if (!device) {
                                        return;
                                    }
                                    for (let i = 0; i < device.networks.values.length; i++) {
                                        let network = device.networks.values[i];
                                        if (network.name === savedNetworksView.model.name) {
                                            network.connect();
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Separator
                Rectangle {
                    Layout.leftMargin: networkModule.popupSectionMargin
                    Layout.rightMargin: networkModule.popupSectionMargin

                    Layout.fillWidth: true
                    Layout.minimumHeight: 1
                    Layout.preferredHeight: 1
                    Layout.maximumHeight: 1

                    color: UI.Colors.backgroundSurface
                    opacity: 1
                }

                // Unknown Networks Section
                ColumnLayout {
                    id: unknownNetworksSection

                    Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                    Layout.margins: networkModule.popupSectionMargin

                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    // Header text
                    Text {
                        id: unknownNetworksHeaderText

                        Layout.fillWidth: true
                        Layout.minimumHeight: 30
                        Layout.preferredHeight: 30
                        Layout.maximumHeight: 30

                        text: "Available Networks"
                        color: UI.Colors.foreground
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }

                    ListView {
                        id: unknownNetworksView

                        Layout.fillHeight: true
                        Layout.fillWidth: true

                        clip: true

                        model: unknownNetworksModel
                        interactive: true

                        delegate: Rectangle {
                            id: unknownNetworkItem

                            width: parent.width
                            height: 32

                            color: "transparent"
                            radius: 4

                            RowLayout {
                                id: unknownNetworkItemLayout

                                anchors.fill: parent

                                spacing: 8

                                Text {
                                    id: unknownNetworkSignalIcon

                                    text: model.signalIcon

                                    color: UI.Colors.foreground
                                    font {
                                        family: UI.Fonts.fontFamily
                                        pixelSize: UI.Fonts.fontSize
                                    }
                                }

                                Text {
                                    id: unknownNetworkNameText

                                    Layout.fillWidth: true

                                    text: model.name

                                    color: UI.Colors.foreground
                                    font {
                                        family: UI.Fonts.fontFamily
                                        pixelSize: UI.Fonts.fontSize
                                    }
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: unknownNetworkLockIcon

                                    text: model.isOpen ? "" : ""

                                    color: UI.Colors.foregroundSecondary
                                    font {
                                        family: UI.Fonts.fontFamily
                                        pixelSize: UI.Fonts.fontSize
                                    }
                                }
                            }
                        }
                    }
                }

                // Separator
                Rectangle {
                    Layout.leftMargin: networkModule.popupSectionMargin
                    Layout.rightMargin: networkModule.popupSectionMargin

                    Layout.fillWidth: true
                    Layout.minimumHeight: 1
                    Layout.preferredHeight: 1
                    Layout.maximumHeight: 1

                    color: UI.Colors.backgroundSurface
                    opacity: 1
                }

                // Refresh section
                RowLayout {
                    id: networkRefreshSection

                    Layout.alignment: Qt.AlignCenter
                    Layout.margins: networkModule.popupSectionMargin

                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: 30
                    Layout.preferredHeight: 30
                    Layout.maximumHeight: 30

                    spacing: 15

                    // Refresh button
                    Rectangle {
                        id: networkRefreshButton

                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30

                        color: networkRefreshButtonMouseArea.containsMouse ? UI.Colors.backgroundHover : UI.Colors.backgroundSurface
                        radius: 4

                        Text {
                            id: networkRefreshButtonIcon

                            anchors.centerIn: parent

                            text: "󰑐"
                            color: UI.Colors.foreground
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSize
                            }
                        }

                        MouseArea {
                            id: networkRefreshButtonMouseArea

                            anchors.fill: parent

                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: networkModule.triggerScan()
                        }
                    }

                    // Refresh label
                    Text {
                        id: networkRefreshLabel

                        Layout.alignment: Qt.AlignCenter

                        text: {
                            let device = Services.NetworkService.activeDevice;
                            if (!device || device.type !== DeviceType.Wifi) {
                                return "--";
                            }

                            if (device.scannerEnabled) {
                                return "Loading...";
                            } else {
                                return "Refresh networks";
                            }
                        }
                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                            bold: false
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
            if (visible) {
                networkModule.triggerScan();
            } else {
                scanRefreshTimer.stop();
                let device = Services.NetworkService.activeDevice;
                if (device && device.type === DeviceType.Wifi) {
                    device.scannerEnabled = false;
                }
                networkModule.popupState.close();
            }
        }

        visible: networkModule.popupState && networkModule.popupState.isActive(networkModule.popupId)
    }

    function updatePopupPosition() {
        var pos = networkModule.topIsland.mapFromItem(networkModule, 0, 0);
        popup.anchor.rect = Qt.rect(pos.x + networkModule.implicitWidth / 2 - popup.implicitWidth / 2, networkModule.topIsland.implicitHeight + networkModule.popupTopIslandGap, popup.implicitWidth, popup.implicitHeight);
    }
    // ===

    // Popup Functionality ===
    // Network list models
    ListModel {
        id: knownNetworksModel
    }

    ListModel {
        id: unknownNetworksModel
    }

    // One-shot timer for delayed refresh after scan completes
    Timer {
        id: scanRefreshTimer
        interval: 3000
        repeat: false
        onTriggered: {
            networkModule.refreshNetworkLists();
            let device = Services.NetworkService.activeDevice;
            if (device && device.type === DeviceType.Wifi) {
                device.scannerEnabled = false;
            }
        }
    }

    function triggerScan() {
        let device = Services.NetworkService.activeDevice;
        if (!device || device.type !== DeviceType.Wifi) {
            return;
        }
        device.scannerEnabled = true;
        refreshNetworkLists();
        scanRefreshTimer.restart();
    }

    function refreshNetworkLists() {
        knownNetworksModel.clear();
        unknownNetworksModel.clear();

        let device = Services.NetworkService.activeDevice;
        if (!device || device.type !== DeviceType.Wifi) {
            return;
        }

        for (let i = 0; i < device.networks.values.length; i++) {
            let network = device.networks.values[i];
            if (network.connected) {
                continue;
            }

            let signalIndex = Math.min(Math.floor(network.signalStrength * 4), 4);
            let icon = Services.NetworkService.wifiIcons[signalIndex];

            let entry = {
                "name": network.name,
                "signalIcon": icon,
                "securityText": networkModule.getSecurityLabel(network.security),
                "isOpen": network.security === WifiSecurityType.Open
            };

            if (network.known) {
                knownNetworksModel.append(entry);
            } else {
                unknownNetworksModel.append(entry);
            }
        }
    }

    function getSecurityLabel(networkSecurity) {
        switch (networkSecurity) {
        case WifiSecurityType.StaticWep:
            return "Static WEP";
        case WifiSecurityType.Sae:
            return "SAE";
        case WifiSecurityType.Owe:
            return "OWE";
        case WifiSecurityType.WpaPsk:
            return "WPA-PSK";
        case WifiSecurityType.Wpa2Psk:
            return "WPA2-PSK";
        case WifiSecurityType.WpaEap:
            return "WPA-EAP";
        case WifiSecurityType.Wpa2Eap:
            return "WPA2-EAP";
        case WifiSecurityType.Wpa3SuiteB192:
            return "WPA3-192";
        case WifiSecurityType.DynamicWep:
            return "802.1X WEP";
        case WifiSecurityType.Leap:
            return "LEAP";
        case WifiSecurityType.Open:
            return "Open";
        default:
            return networkSecurity.toString();
        }
    }

    // Stepper stage states
    readonly property bool stage1Complete: Networking.wifiEnabled
    readonly property bool stage2Complete: Services.NetworkService.activeDevice !== null
    readonly property bool stage3Complete: Networking.connectivity === NetworkConnectivity.Full
    // ===
}

/*
Popup UI Hierarchy (ignoring separators)

popup {PopupWindow}
└── popupContent {Rectangle}
    └── popupParentLayout {ColumnLayout}
        ├── currentStatusContents {RowLayout}
        │   ├── wifiToggleButton {Rectangle}
        │   │   ├── wifiToggleButtonIcon {Text}
        │   │   └── wifiToggleButtonMouseArea {MouseArea}
        │   ├── wifiStatusText {Text}
        │   └── wifiSecurityText {Text}
        ├── networkStepperSection {ColumnLayout}
        │   ├── stepperTrack {Item}
        │   │   ├── stage1Dot {Rectangle}
        │   │   ├── line1 {Rectangle}
        │   │   ├── stage2Dot {Rectangle}
        │   │   ├── line2 {Rectangle}
        │   │   └── stage3Dot {Rectangle}
        │   └── stepperLabelsRow {RowLayout}
        │       ├── stage1Text {Text}
        │       ├── stage2Text {Text}
        │       └── stage3Text {Text}
        ├── networkStatsSection {ColumnLayout}
        │   ├── ipAddrText {Text}
        │   └── networkSpeedsTextRow {RowLayout}
        │       ├── downloadSpeedText {Text}
        │       └── uploadSpeedText {Text}
        ├── savedNetworksSection {ColumnLayout}
        │   ├── savedNetworksHeaderText {Text}
        │   └── savedNetworksView {ListView}
        │       └── savedNetworkItem {Rectangle}
        │           └── savedNetworkItemLayout {RowLayout}
        │               ├── savedNetworkSignalIcon {Text}
        │               ├── savedNetworkNameText {Text}
        │               └── savedNetworkSecurityText {Text}
        ├── unknownNetworksSection {ColumnLayout}
        │   ├── unknownNetworksHeaderText {Text}
        │   └── unknownNetworksView {ListView}
        │       └── unknownNetworkItem {Rectangle}
        │           └── unknownNetworkItemLayout {RowLayout}
        │               ├── unknownNetworkSignalIcon {Text}
        │               ├── unknownNetworkNameText {Text}
        │               └── unknownNetworkLockIcon {Text}
        └── networkRefreshSection {RowLayout}
            ├── networkRefreshButton {Rectangle}
            │   ├── networkRefreshButtonIcon {Text}
            │   └── networkRefreshButtonMouseArea {MouseArea}
            └── networkRefreshLabel {Text}
*/
