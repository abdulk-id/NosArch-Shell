import Quickshell
import Quickshell.Bluetooth
import QtQuick

import "../../ui" as UI

Item {
    id: btModule

    implicitWidth: btText.implicitWidth
    implicitHeight: btText.implicitHeight

    readonly property BluetoothAdapter btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: Bluetooth.devices
    readonly property int connectedCount: btDevices.count
    readonly property bool isConnected: {
        for (let i = 0; i < btDevices.values.length; i++) {
            if (btDevices.values[i].connected) {
                return true;
            }
        }
        return false;
    }

    Text {
        id: btText

        text: {
            if (btModule.btAdapter) {
                if (btModule.btAdapter.enabled) {
                    if (btModule.isConnected) {
                        return "󰂱"; // connected
                    } else if (btModule.btAdapter.discoverable) {
                        return "󰂳"; // enabled & discoverable
                    } else {
                        return ""; // enabled
                    }
                } else {
                    return "󰂲"; // disabled
                }
            } else {
                return "󰂲"; // no controller
            }
        }
        color: UI.Colors.foreground
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }
    }

    MouseArea {
        id: btMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: Quickshell.execDetached(["nosarch-launch-tui", "bluetui"])
    }
}
