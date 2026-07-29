import QtQuick
import Quickshell

import "../services" as Services

PanelWindow {
    id: root

    anchors {
        right: true
        top: true
        bottom: true
    }

    implicitWidth: 280
    color: "#cc1e1e1e"

    Rectangle {
        anchors.fill: parent
        color: "#202020"

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            function row(label, value) {
                return `${label}: ${value}`;
            }

            Text {
                color: "white"
                font.bold: true
                text: "System Info"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("CPU Usage", Services.SystemInfo.cpu.usagePercent + "%")
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("Memory Usage", Services.SystemInfo.memory.usagePercent + "%")
            }

            Text {
                color: "white"
                text: parent.row("Memory Total", Services.SystemInfo.memory.totalGib.toFixed(2) + " GiB")
            }

            Text {
                color: "white"
                text: parent.row("Memory Available", Services.SystemInfo.memory.availableGib.toFixed(2) + " GiB")
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("Battery Present", Services.SystemInfo.battery.present)
            }

            Text {
                color: "white"
                text: parent.row("Battery %", Services.SystemInfo.battery.percentage + "%")
            }

            Text {
                color: "white"
                text: parent.row("Charging", Services.SystemInfo.battery.charging)
            }

            Text {
                color: "white"
                text: parent.row("Fully Charged", Services.SystemInfo.battery.fullyCharged)
            }

            Text {
                color: "white"
                text: parent.row("Pending Charge", Services.SystemInfo.battery.pendingCharge)
            }

            Text {
                color: "white"
                font.family: "JetbrainsMono Nerd Font"
                text: parent.row("Icon", Services.SystemInfo.battery.textIcon)
            }
        }
    }
}
