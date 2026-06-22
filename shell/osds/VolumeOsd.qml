import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

import "../../components"

Scope {
    id: volumeOsd

    property bool osdVisible: false

    ProgressBarOsd {
        value: Math.round((Pipewire.defaultAudioSink?.audio.volume ?? 0) * 100)
        icon: "audio-volume-high-symbolic"
        osdVisible: volumeOsd.osdVisible
    }

    // Bind the pipewire node so its volume will be tracked
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    Connections {
        target: Pipewire.defaultAudioSink?.audio

        function onVolumeChanged() {
            volumeOsd.osdVisible = true;
            hideTimer.restart();
        }
    }

    // Timer for hiding the osd
    Timer {
        id: hideTimer
        interval: 1000
        onTriggered: volumeOsd.osdVisible = false
    }
}
