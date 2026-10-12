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

        // NOTE: the glyph property this used to publish is GONE (ticket 11,
        // ADR 0001). Presentation belongs to the widget: this
        // service reports what is TRUE — the volume, whether it is muted, and
        // the device's form factor — and shell/widgets/VolumeWidget.qml decides
        // what that looks like. Every input the old glyph needed is still
        // published above, by name; only the drawing decision moved.
        //
        // A reader tempted to put it back should read docs/adr/0001 first: that
        // record exists precisely because removing it looks like a regression to
        // someone who has not read it.
        //
        // What is left here is state and the actions that change it, which is the
        // whole of the service/widget boundary.

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

        // The microphone glyph goes with the output one, for the same reason and
        // under the same decision (ADR 0001): this service reports the input's
        // volume and mute state, and a widget that draws them decides what they
        // look like. No input widget is on the contract yet — the pre-rewrite
        // microphone module reads no glyph from here either.

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
