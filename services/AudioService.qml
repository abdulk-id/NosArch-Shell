pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: audioService

    // Constants
    readonly property real stepVolume: 0.05
    readonly property real maxVolume: 1.0

    // API
    property alias output: outputObject
    property alias input: inputObject

    // Output object
    QtObject {
        id: outputObject

        readonly property var defaultSink: Pipewire.defaultAudioSink

        readonly property int volume: Math.round((defaultSink?.audio?.volume ?? 0) * 100)
        readonly property bool isMuted: defaultSink?.audio?.muted ?? false

        readonly property bool isBluetooth: (defaultSink?.properties["device.api"] ?? "") === "bluez5"
        readonly property string deviceFormFactor: defaultSink?.properties["device.form-factor"] ?? ""

        readonly property string textIcon: {
            if (!defaultSink || !defaultSink.audio || !defaultSink.ready) {
                return "󰸈";
            }

            if (isMuted) {
                return "󰖁";
            }

            let icon = "";

            if (deviceFormFactor === "headphone" || deviceFormFactor === "headset") {
                icon = "";
            } else if (deviceFormFactor === "phone" || deviceFormFactor === "portable") {
                icon = "";
            } else if (deviceFormFactor === "car") {
                icon = "";
            } else {
                if (volume === 0) {
                    icon = "";
                } else if (volume <= 25) {
                    icon = "";
                } else if (volume <= 50) {
                    icon = "";
                } else {
                    icon = "";
                }
            }

            return isBluetooth ? `${icon} 󰂰` : icon;
        }

        function setVolume(newVolume: real) {
            if (!defaultSink?.audio || !defaultSink?.ready) {
                return;
            }

            const clamped = Math.max(0, Math.min(audioService.maxVolume, newVolume));
            if (Math.abs(clamped - (defaultSink.audio.volume ?? 0)) < 0.005) {
                // TODO: What is this?
                return;
            }

            defaultSink.audio.muted = false;
            defaultSink.audio.volume = clamped;
        }

        function increaseVolume() {
            setVolume((defaultSink?.audio?.volume ?? 0) + audioService.stepVolume);
        }

        function decreaseVolume() {
            setVolume((defaultSink?.audio?.volume ?? 0) - audioService.stepVolume);
        }

        function toggleMute() {
            if (!defaultSink?.audio || !defaultSink?.ready) {
                return;
            }
            defaultSink.audio.muted = !defaultSink.audio.muted;
        }
    }

    // Input object
    QtObject {
        id: inputObject

        readonly property var defaultSource: Pipewire.defaultAudioSource

        readonly property int volume: Math.round((defaultSource?.audio?.volume ?? 0) * 100)
        readonly property bool isMuted: defaultSource?.audio?.muted ?? false

        readonly property string textIcon: {
            if (!defaultSource || !defaultSource.audio || !defaultSource.ready) {
                return "";
            }

            if (inputObject.isMuted) {
                return "";
            }

            return "";
        }

        function setVolume(newVolume: real) {
            if (!defaultSource?.audio || !defaultSource?.ready) {
                return;
            }

            const clamped = Math.max(0, Math.min(audioService.maxVolume, newVolume));
            if (Math.abs(clamped - (defaultSource.audio.volume ?? 0)) < 0.005) {
                return;
            }

            defaultSource.audio.muted = false;
            defaultSource.audio.volume = clamped;
        }

        function toggleMute() {
            if (!defaultSource?.audio || !defaultSource?.ready) {
                return;
            }
            defaultSource.audio.muted = !defaultSource.audio.muted;
        }
    }

    // Pipewire monitors
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }
}
