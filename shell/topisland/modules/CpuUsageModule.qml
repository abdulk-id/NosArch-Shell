import Quickshell
import Quickshell.Io
import QtQuick

import "../../ui" as UI

Item {
    id: cpuUsageModule

    // UI ===
    implicitHeight: cpuUsageText.implicitHeight
    implicitWidth: cpuUsageText.implicitWidth

    Text {
        id: cpuUsageText

        text: "󰍛 " + cpuUsageModule.cpuUsage + "%"
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
    // ===

    // Behavior ===
    property int cpuUsage: 0
    property var lastCpuIdle: 0
    property var lastCpuTotal: 0

    Process {
        id: cpuProc
        command: ["sh", "-c", "head -1 /proc/stat"]
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                var p = data.trim().split(/\s+/);
                var idle = parseInt(p[4]) + parseInt(p[5]);
                var total = p.slice(1, 8).reduce((a, b) => a + parseInt(b), 0);
                if (cpuUsageModule.lastCpuTotal > 0) {
                    cpuUsageModule.cpuUsage = Math.round(100 * (1 - (idle - cpuUsageModule.lastCpuIdle) / (total - cpuUsageModule.lastCpuTotal)));
                }
                cpuUsageModule.lastCpuTotal = total;
                cpuUsageModule.lastCpuIdle = idle;
            }
        }
        Component.onCompleted: running = true
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: cpuProc.running = true
    }
    // ===
}
