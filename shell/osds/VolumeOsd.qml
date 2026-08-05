import QtQuick

import "../../services" as Services

Item {
    id: volumeOsd

    property int currentVolume: Services.AudioService.output.volume
    property bool isVolumeMuted: Services.AudioService.output.isMuted
    property bool osdVisible: false

    readonly property string text: isVolumeMuted ? "Mute" : currentVolume + "%"
    readonly property string fontIcon: Services.AudioService.output.textIcon
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
