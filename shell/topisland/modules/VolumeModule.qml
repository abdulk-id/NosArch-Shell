import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

import "../../ui" as UI

Item {
    id: volume

    // UI ===
    implicitWidth: volumeText.implicitWidth
    implicitHeight: volumeText.implicitHeight

    Text {
        id: volumeText

        text: {
            let node = Pipewire.defaultAudioSink;
            if (!node || !node.audio || !node.ready) {
                return "󰸈"; // Fallback icon
            }

            let audio = node.audio;
            let props = node.properties;
            let vol = Math.round(audio.volume * 100);

            if (audio.muted) {
                return "";
            }

            let icon = "";
            let isBluetooth = props["device.api"] === "bluez5";
            let formFactor = props["device.form-factor"] || "";

            if (formFactor === "headphone" || formFactor === "headset") {
                icon = "";
                // TODO: Doesn't work
            } else if (formFactor === "phone" || formFactor === "portable") {
                icon = "";
            } else if (formFactor === "car") {
                icon = "";
            } else {
                if (vol === 0) {
                    icon = "󰖁";
                } else if (vol <= 25) {
                    return "󰕿";
                } else if (vol <= 50) {
                    icon = "󰖀";
                } else {
                    icon = "󰕾";
                }
            }

            // Append Bluetooth suffix if needed
            let bluetoothSuffix = isBluetooth ? " 󰂰" : "";

            return `${icon}${bluetoothSuffix}`;
        }
        color: UI.Colors.foreground
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }
    }
    MouseArea {
        id: volumeMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: Quickshell.execDetached(["nosarch-launch-tui", "wiremix"])
    }
    // ===

    // Behavior ===
    PwObjectTracker { // Pipewire monitor
        objects: [Pipewire.defaultAudioSink]
    }

    Connections { // React to changes
        target: Pipewire.defaultAudioSink?.audio
        /*
        function onVolumeChanged() {
            console.log("Volume changed");
        }
        function onMutedChanged() {
            console.log("Mute toggled");
        }
        */
    }
    // ===
}
