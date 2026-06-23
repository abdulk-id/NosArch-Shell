import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import "../ui" as UI
import "../../services" as Services

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
        active: (Services.Media.isAvailable && mediaOsd.osdVisible)

        PanelWindow {
            anchors {
                bottom: true
            }

            margins.bottom: 10

            implicitWidth: 350
            implicitHeight: 100

            color: "transparent"

            WlrLayershell.namespace: "nosarch-media-osd"
            WlrLayershell.layer: WlrLayer.Overlay
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

                        source: Services.Media.trackArtUrl
                        fillMode: Image.PreserveAspectCrop

                        visible: (Services.Media.trackArtUrl !== "")
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignLeft
                        Layout.fillWidth: true

                        Text {
                            id: statusText

                            function getStatusText() {
                                if (Services.Media.isPlaying) {
                                    return Services.Media.getPlayerIcon() + "  Playing";
                                } else if (Services.Media.isPaused) {
                                    return "  Paused";
                                } else if (Services.Media.isStopped) {
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

                            text: Services.Media.title.trim() !== "" ? Services.Media.title : "Unknown title"
                            color: UI.Colors.foreground
                            elide: Text.ElideRight

                            font {
                                family: UI.Fonts.fontFamily
                                pointSize: UI.Fonts.fontSizeSmall
                            }
                        }

                        Text {
                            id: artistText

                            text: Services.Media.artist
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
    Connections {
        id: activePlayerConnection

        target: Services.Media
        ignoreUnknownSignals: true

        function onTrackChanged() {
            if (!Services.Media.isStopped) {
                mediaOsd.showOsd();
            }
        }

        function onPlaybackStarted() {
            mediaOsd.showOsd();
        }

        function onPlaybackPaused() {
            mediaOsd.showOsd();
        }
    }
}
