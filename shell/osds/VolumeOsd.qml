import QtQuick

import "../../services" as Services
import "../../components" as Components

Item {
    id: volumeOsd

    property int currentVolume: Services.AudioService.output.volume
    property bool isVolumeMuted: Services.AudioService.output.isMuted
    property bool osdVisible: false

    readonly property string text: isVolumeMuted ? "Mute" : currentVolume + "%"
    // The glyph comes from the shared PRESENTATION component, not from the
    // service (ADR 0001, ticket 11). AudioService used to publish this glyph
    // itself; it no longer does, and this is where the decision moved to.
    readonly property var icon: Components.VolumeIcon {}
    readonly property string fontIcon: volumeOsd.icon.glyph
    readonly property string accessibleName: isVolumeMuted ? "Volume: muted" : "Volume: " + currentVolume + "%"

    Connections {
        target: Services.AudioService.output

        function onVolumeChanged() {
            volumeOsd.osdVisible = true;
            hideTimer.restart();
        }

        function onIsMutedChanged() {
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
