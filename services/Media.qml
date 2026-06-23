pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: mediaSingleton

    // Active Player logic
    property var activePlayer: null

    function updateActivePlayer() {
        const players = Mpris.players.values;

        // Remove dead player references
        if (mediaSingleton.activePlayer && !players.includes(mediaSingleton.activePlayer)) {
            activePlayer = null;
        }

        // If another player starts playing, switch to it
        for (const p of players) {
            if (p !== mediaSingleton.activePlayer && p.playbackState === MprisPlaybackState.Playing) {
                mediaSingleton.activePlayer = p;
                return;
            }
        }

        // Keep current player even if paused/stopped
        if (mediaSingleton.activePlayer) {
            return;
        }

        // Fallback only if nothing selected yet
        mediaSingleton.activePlayer = players.length > 0 ? players[0] : null;
    }

    Connections {
        target: Mpris.players

        function onValuesChanged() {
            mediaSingleton.updateActivePlayer();
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: mediaSingleton.updateActivePlayer()
    }

    Component.onCompleted: updateActivePlayer()

    // Player data
    readonly property bool isAvailable: mediaSingleton.activePlayer !== null

    readonly property string title: mediaSingleton.activePlayer?.trackTitle ?? ""
    readonly property string artist: mediaSingleton.activePlayer?.trackArtist ?? ""
    readonly property string album: mediaSingleton.activePlayer?.trackAlbum ?? ""
    readonly property string trackArtUrl: mediaSingleton.activePlayer?.trackArtUrl ?? ""

    readonly property bool isPlaying: mediaSingleton.activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property bool isPaused: mediaSingleton.activePlayer?.playbackState === MprisPlaybackState.Paused
    readonly property bool isStopped: mediaSingleton.activePlayer?.playbackState === MprisPlaybackState.Stopped

    // Signals
    signal trackChanged
    signal playbackStarted
    signal playbackPaused
    signal playbackStopped

    Connections {
        target: mediaSingleton.activePlayer
        ignoreUnknownSignals: true

        function onTrackTitleChanged() {
            mediaSingleton.trackChanged();
        }

        function onPlaybackStateChanged() {
            switch (mediaSingleton.activePlayer?.playbackState) {
            case MprisPlaybackState.Playing:
                mediaSingleton.playbackStarted();
                break;
            case MprisPlaybackState.Paused:
                mediaSingleton.playbackPaused();
                break;
            case MprisPlaybackState.Stopped:
                mediaSingleton.playbackStopped();
                break;
            }
        }
    }

    // Player control
    function togglePlayPause() {
        if (mediaSingleton.activePlayer && mediaSingleton.activePlayer.canTogglePlaying) {
            mediaSingleton.activePlayer.togglePlaying();
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
        const playingApp = String(mediaSingleton.activePlayer?.desktopEntry || mediaSingleton.activePlayer?.identity || "default");
        return _playerIcons[playingApp.toLowerCase().replace(/\.desktop$/, "")] ?? _playerIcons.default;
    }
}
