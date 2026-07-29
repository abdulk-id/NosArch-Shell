import QtQuick
import Quickshell

import "../../ui" as UI
import "../../../services" as Services

Item {
    id: memUsageModule

    implicitHeight: memUsageText.implicitHeight
    implicitWidth: memUsageText.implicitWidth

    Text {
        id: memUsageText

        text: "  " + (Services.SystemInfo.memory.totalGib - Services.SystemInfo.memory.availableGib).toFixed(1) + "/" + Services.SystemInfo.memory.totalGib.toFixed(1) + " GiB"
        color: UI.Colors.foreground
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }

        opacity: 0.7
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }
    MouseArea {
        id: memUsageMouseArea

        anchors.fill: parent

        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: memUsageText.opacity = 1.0
        onExited: memUsageText.opacity = 0.7
        onClicked: Quickshell.execDetached(["nosarch-launch-tui", "btop"])
    }
}
