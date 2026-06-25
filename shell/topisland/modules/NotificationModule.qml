import Quickshell
import QtQuick

import "../../ui" as UI

Item {
    id: notificationModule

    implicitHeight: notificationText.implicitHeight
    implicitWidth: notificationText.implicitWidth

    Text {
        id: notificationText

        text: ""
        color: UI.Colors.foreground
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }
    }
    MouseArea {
        id: memUsageMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: {
            if (mouse.button == Qt.LeftButton) {
                Quickshell.execDetached(["sh", "-c", "swaync-client -t -sw"]);
            } else if (mouse.button == Qt.RightButton) {
                Quickshell.execDetached(["sh", "-c", "swaync-client -d -sw"]);
            }
        }
    }
}
