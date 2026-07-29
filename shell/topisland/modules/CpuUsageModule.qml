import QtQuick
import Quickshell

import "../../ui" as UI
import "../../../services" as Services

Item {
    id: cpuUsageModule

    implicitHeight: cpuUsageText.implicitHeight
    implicitWidth: cpuUsageText.implicitWidth

    Text {
        id: cpuUsageText

        text: "󰍛 " + Services.SystemInfo.cpu.usagePercent + "%"
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
        id: cpuUsageMouseArea

        anchors.fill: parent

        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: cpuUsageText.opacity = 1.0
        onExited: cpuUsageText.opacity = 0.7
        onClicked: Quickshell.execDetached(["nosarch-launch-tui", "btop"])
    }
}
