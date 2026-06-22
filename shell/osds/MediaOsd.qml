import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland

import "../ui" as UI

Scope {
    id: mediaOsd

    // UI ===
    property bool osdVisible: false

    function showOsd() {
        mediaOsd.osdVisible = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: mediaOsd.osdVisible = false
    }

    LazyLoader {
        active: (mediaOsd.activePlayer && mediaOsd.osdVisible)

        PanelWindow {
            anchors {
                bottom: true
            }

            margins.bottom: 10

            implicitWidth: 350
            implicitHeight: 100

            color: "transparent"

            WlrLayershell.namespace: "nosarch-media-osd"
            focusable: false
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: UI.Colors.background

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10

                    Image {
                        id: trackImage

                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64

                        Layout.rightMargin: 10

                        source: mediaOsd.activePlayer?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop

                        visible: (mediaOsd.activePlayer?.trackArtUrl != "")
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignLeft
                        Layout.fillWidth: true

                        Text {
                            id: statusText

                            function getStatusText() {
                                if (mediaOsd.activePlayer?.isPlaying) {
                                    if (mediaOsd.getPlayingAppName() == "spotify") {
                                        return "  Playing";
                                    }

                                    return "  Playing";
                                } else if (mediaOsd.activePlayer?.playbackState == MprisPlaybackState.Paused) {
                                    return "  Paused";
                                } else if (mediaOsd.activePlayer?.playbackState == MprisPlaybackState.Stopped) {
                                    return "  Stopped";
                                } else {
                                    return "";
                                }
                            }

                            text: getStatusText()
                            color: UI.Colors.accent

                            font {
                                family: UI.Fonts.fontFamily
                                pointSize: UI.Fonts.fontSizeSmall
                            }

                            visible: (statusText.text != "")
                        }

                        Text {
                            id: titleText

                            text: mediaOsd.activePlayer?.trackTitle ?? "Unknown title"
                            color: UI.Colors.foreground
                            elide: Text.ElideRight

                            font {
                                family: UI.Fonts.fontFamily
                                pointSize: UI.Fonts.fontSizeSmall
                            }
                        }

                        Text {
                            id: artistText

                            text: mediaOsd.activePlayer?.trackArtist ?? ""
                            color: UI.Colors.foregroundSecondary
                            elide: Text.ElideRight

                            font {
                                family: UI.Fonts.fontFamily
                                pointSize: UI.Fonts.fontSizeSmall
                            }
                        }
                    }
                }
            }
        }
    }
    // ===

    // Logic ===
    property MprisPlayer activePlayer: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    property string status: activePlayer.isPlaying ? "Playing" : "Paused"

    Connections {
        id: allPlayersConnection

        target: Mpris.players

        function onValuesChanged() {
            mediaOsd.activePlayer = Mpris.players.values.length > 0 ? Mpris.players.values[0] : null;
        }
    }

    Connections {
        id: activePlayerConnection
        target: mediaOsd.activePlayer

        function onTrackTitleChanged() {
            if (mediaOsd.activePlayer?.playbackState !== MprisPlaybackState.Stopped) {
                mediaOsd.showOsd();
            }
        }

        function onPlaybackStateChanged() {
            switch (mediaOsd.activePlayer?.playbackState) {
            case MprisPlaybackState.Playing:
            case MprisPlaybackState.Paused:
                mediaOsd.showOsd();
                break;
            }
        }
    }

    function getPlayingAppName() {
        const playingApp = String(mediaOsd.activePlayer?.desktopEntry || mediaOsd.activePlayer?.identity || "default");
        return playingApp.toLowerCase().replace(/\.desktop$/, "");
    }
}
