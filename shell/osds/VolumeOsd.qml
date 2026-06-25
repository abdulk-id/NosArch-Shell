import QtQuick
import Quickshell.Services.Pipewire

Item {
    id: volumeOsd

    property bool isVolumeMuted: false

    property int currentVolume: 0
    readonly property string text: isVolumeMuted ? "Mute" : currentVolume + "%"
    property bool osdVisible: false
    readonly property string fontIcon: {
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
    readonly property string accessibleName: volumeOsd.isVolumeMuted ? "Volume: muted" : "Volume: " + volumeOsd.currentVolume + "%"

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
