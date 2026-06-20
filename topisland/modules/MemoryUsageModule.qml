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
    property int memUsage: 0

    Process {
        id: memProc
        command: ["sh", "-c", "free | grep Mem"]
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                var parts = data.trim().split(/\s+/);
                var total = parseInt(parts[1]) || 1;
                var used = parseInt(parts[2]) || 0;
                memUsageModule.memUsage = Math.round(100 * used / total);
            }
        }
        Component.onCompleted: running = true
    }
    Timer {
        interval: 5000 // Every 5 seconds
        running: true // Start immediately
        repeat: true // Keep going forever
        onTriggered: memProc.running = true
    }
    // ===
}
