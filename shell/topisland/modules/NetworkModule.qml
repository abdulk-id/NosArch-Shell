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

                // WiFi Toggle Button and Status Text
                RowLayout {
                    Layout.fillWidth: true

                    spacing: 5

                    // WiFi Toggle Button
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.margins: 10

                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40

                        color: UI.Colors.backgroundSurface
                        radius: 6

                        Text {
                            anchors.centerIn: parent
                            text: Services.NetworkService.textIcon
                            color: UI.Colors.foreground
                            font {
                                family: UI.Fonts.fontFamily
                                pixelSize: UI.Fonts.fontSizeIcons
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
                }

                // Separator
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1

                    color: UI.Colors.backgroundSurface
                    opacity: 0.5
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
}
