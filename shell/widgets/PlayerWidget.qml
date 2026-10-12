import QtQuick

import "."
import "../ui" as UI
import "../../services" as Services

// PlayerWidget — media indicator (ticket 14).
//
// Shows what is currently playing (title, or artist when title is empty) with
// a playback-state glyph. Click toggles play/pause through MediaService.
BarWidget {
    id: player

    readonly property bool playerAvailable: Services.MediaService.isAvailable

    readonly property string nowPlayingText: {
        if (!player.playerAvailable) {
            return "";
        }
        const title = Services.MediaService.title.trim();
        if (title !== "") {
            return title;
        }
        const artist = Services.MediaService.artist.trim();
        if (artist !== "") {
            return artist;
        }
        return "Unknown track";
    }

    readonly property string stateGlyph: {
        if (!player.playerAvailable) {
            return "";
        }
        if (Services.MediaService.isPlaying) {
            return Services.MediaService.getPlayerIcon();
        }
        if (Services.MediaService.isPaused) {
            return "";
        }
        if (Services.MediaService.isStopped) {
            return "";
        }
        return "";
    }

    readonly property string barDisplayText: {
        if (!player.playerAvailable) {
            return "";
        }
        const parts = [];
        if (player.stateGlyph !== "") {
            parts.push(player.stateGlyph);
        }
        if (player.nowPlayingText !== "") {
            parts.push(player.nowPlayingText);
        }
        return parts.join(" ");
    }

    tooltip: {
        if (!player.playerAvailable) {
            return "";
        }
        const title = Services.MediaService.title.trim();
        const artist = Services.MediaService.artist.trim();
        if (title !== "" && artist !== "") {
            return title + " — " + artist;
        }
        if (title !== "") {
            return title;
        }
        if (artist !== "") {
            return artist;
        }
        return player.nowPlayingText;
    }

    activate: function (widget) {
        Services.MediaService.togglePlayPause();
    }

    content: Component {
        Row {
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: player.barDisplayText !== ""
                text: player.barDisplayText
                color: UI.Colors.foreground
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSize
                }
            }
        }
    }
}
