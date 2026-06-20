import Quickshell.Services.Mpris
import QtQuick

import "../../ui" as UI

Item {
    id: playerModule

    // UI ===
    implicitHeight: playerText.implicitHeight
    implicitWidth: playerText.implicitWidth

    Text {
        id: playerText

        text: {
            if (!playerModule.activePlayer) {
                return "No player";
            }

            if (playerModule.activePlayer.playbackState === MprisPlaybackState.Playing) {
                return playerModule.playerIconFor(playerModule.activePlayer);
            }

            return playerModule.statusIconFor(playerModule.activePlayer);
        }
        color: UI.Colors.foreground
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSizeIcons
        }

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        onClicked: {
            if (playerModule.activePlayer && playerModule.activePlayer.canTogglePlaying) {
                playerModule.activePlayer.togglePlaying();
            }
        }
    }
    // ===

    // Behavior ===
    property var activePlayer: null

    function updateActivePlayer() {
        const players = Mpris.players.values;

        // Remove dead player references
        if (activePlayer && players.includes(activePlayer)) {
            activePlayer = null;
        }

        // If another player starts playing, switch to it
        for (const p of players) {
            if (p !== activePlayer && p.playbackState === MprisPlaybackState.Playing) {
                activePlayer = p;
                return;
            }
        }

        // Keep current player even if paused/stopped
        if (activePlayer) {
            return;
        }

        // Fallback only if nothing selected yet
        activePlayer = players.length > 0 ? players[0] : null;
    }

    Connections {
        target: Mpris.players

        function onValuesChanged() {
            playerModule.updateActivePlayer();
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: playerModule.updateActivePlayer()
    }

    Component.onCompleted: updateActivePlayer()

    // Icon selecting logic
    property var playerIcons: ({
            default: "",
            spotify: ""
        })

    property var statusIcons: ({
            playing: "",
            paused: "",
            stopped: ""
        })

    function normalizedPlayerKey(player) {
        const raw = String(player?.desktopEntry || player?.identity || "default");
        return raw.toLowerCase().replace(/\.desktop$/, "");
    }
    function playerIconFor(player) {
        const key = normalizedPlayerKey(player);
        return playerIcons[key] ?? playerIcons.default;
    }
    function statusIconFor(player) {
        if (!player)
            return "";

        switch (player.playbackState) {
        case MprisPlaybackState.Playing:
            return statusIcons.playing;
        case MprisPlaybackState.Paused:
            return statusIcons.paused;
        case MprisPlaybackState.Stopped:
        default:
            return statusIcons.stopped;
        }
    }
    // ===
}
