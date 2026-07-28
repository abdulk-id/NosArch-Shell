import QtQuick
import Quickshell.Io

Item {
    id: keyboardBrightnessOsd

    property bool osdVisible: false
    property bool available: false
    property string deviceName: ""
    property int maxBrightness: 1
    property int currentBrightness: 0

    readonly property string text: currentBrightness + "%"
    readonly property string fontIcon: "󰌌"
    readonly property string accessibleName: "Keyboard Brightness: " + currentBrightness + "%"

    Process {
        id: discoveryProc
        command: ["brightnessctl", "-l"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                const devices = output.split("Device '").slice(1);
                for (const d of devices) {
                    const parts = d.split("' of class '");
                    if (parts.length === 2) {
                        const name = parts[0];
                        const cls = parts[1].split("':")[0];
                        if (cls === "leds" && (name.includes("kbd") || name.includes("keyboard"))) {
                            keyboardBrightnessOsd.deviceName = name;
                            keyboardBrightnessOsd.available = true;
                            maxProc.running = true;
                            break;
                        }
                    }
                }
            }
        }
    }

    Process {
        id: maxProc
        command: ["brightnessctl", "-d", keyboardBrightnessOsd.deviceName, "max"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const max = parseInt(text.trim());
                if (!isNaN(max) && max > 0)
                    keyboardBrightnessOsd.maxBrightness = max;
                brightnessFile.path = "/sys/class/leds/" + keyboardBrightnessOsd.deviceName + "/brightness";
            }
        }
    }

    FileView {
        id: brightnessFile
        path: ""
        watchChanges: true
        onFileChanged: readProc.running = true
    }
    Process {
        id: readProc
        command: ["brightnessctl", "-d", keyboardBrightnessOsd.deviceName, "get"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim());
                if (!isNaN(val)) {
                    keyboardBrightnessOsd.currentBrightness = (val / keyboardBrightnessOsd.maxBrightness) * 100;
                    keyboardBrightnessOsd.osdVisible = true;
                    hideTimer.restart();
                }
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 1000
        onTriggered: keyboardBrightnessOsd.osdVisible = false
    }
}
