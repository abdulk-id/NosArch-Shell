import QtQuick
import Quickshell.Io

Item {
    id: brightnessOsd

    property int maxBrightness: 1

    property int currentBrightness: 0
    property string text: brightnessOsd.currentBrightness + "%"
    property bool osdVisible: false
    readonly property string fontIcon: "󰃠"
    readonly property string accessibleName: "Brightness: " + brightnessOsd.currentBrightness + "%"

    FileView {
        id: brightnessFile
        path: ""
        watchChanges: true
        onFileChanged: brightnessReadProc.running = true
    }
    Process {
        id: brightnessReadProc
        command: ["brightnessctl", "get"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim());
                if (!isNaN(val)) {
                    brightnessOsd.currentBrightness = (val / brightnessOsd.maxBrightness) * 100;
                    brightnessOsd.osdVisible = true;
                    hideTimer.restart();
                }
            }
        }
    }
    Process {
        id: backlightDiscovery
        command: ["sh", "-c", "p=$(ls -d /sys/class/backlight/*/brightness 2>/dev/null | head -1); [ -n \"$p\" ] && echo \"$p\" && cat \"${p%brightness}max_brightness\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 2) {
                    const max = parseInt(lines[1]);
                    if (!isNaN(max) && max > 0)
                        brightnessOsd.maxBrightness = max;
                    brightnessFile.path = lines[0];
                    brightnessReadProc.running = true;
                }
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 1000
        onTriggered: brightnessOsd.osdVisible = false
    }
}
