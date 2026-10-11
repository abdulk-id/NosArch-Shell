import QtQuick
import Quickshell

import "../../ui" as UI

Item {
    id: archIcon

    implicitHeight: archIconText.implicitHeight
    implicitWidth: archIconText.implicitWidth

    Text {
        id: archIconText

        text: ""
        color: UI.Colors.accent
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSizeIcons
        }
    }

    MouseArea {
        id: archIconMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: Quickshell.execDetached(["sh", "-c", "nosarch-launcher"])
    }
}
