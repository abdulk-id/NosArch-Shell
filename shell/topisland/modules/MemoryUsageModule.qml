import Quickshell
import Quickshell.Io
import QtQuick

import "../../ui" as UI

Item {
    id: memUsageModule

    // UI ===
    implicitHeight: memUsageText.implicitHeight
    implicitWidth: memUsageText.implicitWidth

    Text {
        id: memUsageText

        text: "󰾆 " + memUsageModule.memUsage + "%"
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
    // ===

    // Behavior ===
    property string memUsage: ""

    Process {
        id: memProc
        command: ["sh", "-c", "free | grep Mem | awk '{printf \"%.0f\", ($3/$2) * 100.0}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                memUsageModule.memUsage = text.trim();
            }
        }
        Component.onCompleted: running = true
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: memProc.running = true
    }
    // ===
}
