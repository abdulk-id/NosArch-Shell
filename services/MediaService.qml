pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: mediaService

    // Active Player logic
    property var activePlayer: null

    function updateActivePlayer() {
        const players = Mpris.players.values;

        // Remove dead player references
        if (mediaService.activePlayer && !players.includes(mediaService.activePlayer)) {
            activePlayer = null;
        }

        // If another player starts playing, switch to it
        for (const p of players) {
            if (p !== mediaService.activePlayer && p.playbackState === MprisPlaybackState.Playing) {
                mediaService.activePlayer = p;
                return;
            }
        }

        // Keep current player even if paused/stopped
        if (mediaService.activePlayer) {
            return;
        }

        // Fallback only if nothing selected yet
        mediaService.activePlayer = players.length > 0 ? players[0] : null;
    }

    Connections {
        target: Mpris.players

        function onValuesChanged() {
            mediaService.updateActivePlayer();
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: mediaService.updateActivePlayer()
    }

    Component.onCompleted: updateActivePlayer()

    // Player data
    readonly property bool isAvailable: mediaService.activePlayer !== null

    readonly property string title: mediaService.activePlayer?.trackTitle ?? ""
    readonly property string artist: mediaService.activePlayer?.trackArtist ?? ""
    readonly property string album: mediaService.activePlayer?.trackAlbum ?? ""
    readonly property string trackArtUrl: mediaService.activePlayer?.trackArtUrl ?? ""

    readonly property bool isPlaying: mediaService.activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property bool isPaused: mediaService.activePlayer?.playbackState === MprisPlaybackState.Paused
    readonly property bool isStopped: mediaService.activePlayer?.playbackState === MprisPlaybackState.Stopped

    // Signals
    signal trackChanged
    signal playbackStarted
    signal playbackPaused
    signal playbackStopped

    Connections {
        target: mediaService.activePlayer
        ignoreUnknownSignals: true

        function onTrackTitleChanged() {
            mediaService.trackChanged();
        }

        function onPlaybackStateChanged() {
            switch (mediaService.activePlayer?.playbackState) {
            case MprisPlaybackState.Playing:
                mediaService.playbackStarted();
                break;
            case MprisPlaybackState.Paused:
                mediaService.playbackPaused();
                break;
            case MprisPlaybackState.Stopped:
                mediaService.playbackStopped();
                break;
            }
        }
    }

    // Player control
    function togglePlayPause() {
        if (mediaService.activePlayer && mediaService.activePlayer.canTogglePlaying) {
            mediaService.activePlayer.togglePlaying();
        }
    }

    // Utilities
    readonly property var _playerIcons: ({
            "default": "",
            "io.github.celluloid_player.celluloid": "",
            "spotify": "",
            "vlc": "󰕼"
        })

    function getPlayerIcon(): string {
        const playingApp = String(mediaService.activePlayer?.desktopEntry || mediaService.activePlayer?.identity || "default");
        return _playerIcons[playingApp.toLowerCase().replace(/\.desktop$/, "")] ?? _playerIcons.default;
    }
}
