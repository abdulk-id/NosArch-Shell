import QtQuick
import Quickshell

import "../../ui" as UI
import "../../../services" as Services

Item {
    id: battery

    implicitWidth: batteryText.implicitWidth
    implicitHeight: batteryText.implicitHeight

    Text {
        id: batteryText

        text: Services.SystemInfo.battery.textIcon + " " + Services.SystemInfo.battery.percentage + "%"
        color: {
            if (Services.SystemInfo.battery.percentage <= 10) {
                return "#ff5555"; // critical
            } else if (Services.SystemInfo.battery.percentage <= 20) {
                return "#ffb86c"; // warning
            }
            return UI.Colors.foreground; // default/good
        }
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }
    }

    MouseArea {
        id: batteryMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: Quickshell.execDetached(["sh", "-c", "vicinae vicinae://launch/@botkooper/store.vicinae.power-profile/power-profile"])
    }
}
