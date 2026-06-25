import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

import "../../components"

Scope {
    id: volumeOsd

    property bool osdVisible: false
    property int currentVolume: 0
    property bool isVolumeMuted: false

    ProgressBarOsd {
        value: volumeOsd.currentVolume
        fontIcon: {
            if (volumeOsd.isVolumeMuted) {
                return "";
            }

            if (volumeOsd.currentVolume === 0) {
                return "󰖁";
            }
            if (volumeOsd.currentVolume <= 25) {
                return "󰕿";
            }
            if (volumeOsd.currentVolume <= 50) {
                return "󰖀";
            }

            return "󰕾";
        }
        osdVisible: volumeOsd.osdVisible
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null

        function onVolumeChanged() {
            volumeOsd.currentVolume = Math.round((Pipewire.defaultAudioSink?.audio.volume ?? 0) * 100);
            volumeOsd.osdVisible = true;
            hideTimer.restart();
        }

        function onMutedChanged() {
            volumeOsd.isVolumeMuted = Pipewire.defaultAudioSink?.audio.muted ?? false;
            volumeOsd.osdVisible = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 1000
        onTriggered: volumeOsd.osdVisible = false
    }
}
