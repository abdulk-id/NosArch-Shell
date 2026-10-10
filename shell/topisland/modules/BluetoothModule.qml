import Quickshell
import QtQuick

import "../../ui" as UI
import "../../../services" as Services

Item {
    id: btModule

    implicitWidth: btText.implicitWidth
    implicitHeight: btText.implicitHeight

    Text {
        id: btText

        text: Services.BluetoothService.textIcon
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
