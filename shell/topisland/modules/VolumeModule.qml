import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../../../services" as Services
import "../../ui" as UI
import "../../../components" as Components

// PRESENTATION NOTE (ticket 11, ADR 0001)
//
//   This pre-rewrite module reads its glyph from Components.VolumeIcon, which is
//   where the decision moved to when AudioService stopped publishing one.
//   The file itself is deleted by ticket 18; this is the minimum edit needed for
//   it to keep loading in the meantime, and it points at the real presentation
//   rather than duplicating the glyph table — which is what would otherwise be
//   the fourth copy of a display decision, and would drift.
Components.TopIslandModule {
    id: volumeModule

    // The glyph, from the shared PRESENTATION component. The note above explains
    // why this is Components.VolumeIcon rather than a glyph off the audio
    // service — the service publishes state, this file draws.
    readonly property var volumeIcon: Components.VolumeIcon {}

    content: Component {
        Text {
            id: volumeText

            text: volumeModule.volumeIcon.glyph

            color: UI.Colors.foreground
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSizeIcons - 4
                // -4 because the volume icons are larger compared to other icons
            }
        }
    }

    hasPopup: true
    popupId: "audio"

    popupContent: Component {
        ColumnLayout {
            spacing: 0

            // Audio Toggle Button and Status section
            RowLayout {
                id: currentStatusSection

                property int statusSectionHeight: 40

                Layout.alignment: Qt.AlignCenter
                Layout.margins: volumeModule.popupSectionMargin

                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.minimumHeight: statusSectionHeight
                Layout.preferredHeight: statusSectionHeight
                Layout.maximumHeight: statusSectionHeight

                spacing: 15

                // Audio Toggle Button
                Rectangle {
                    id: audioToggleButton

                    Layout.alignment: Qt.AlignVCenter

                    Layout.preferredHeight: currentStatusSection.statusSectionHeight
                    Layout.preferredWidth: currentStatusSection.statusSectionHeight // width = height for square button

                    color: audioToggleButtonMouseArea.containsMouse ? UI.Colors.backgroundHover : UI.Colors.backgroundSurface
                    radius: 6

                    Text {
                        id: audioToggleButtonIcon

                        anchors.centerIn: parent

                        text: volumeModule.volumeIcon.glyph
                        color: UI.Colors.foreground
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeIcons
                        }
                    }

                    MouseArea {
                        id: audioToggleButtonMouseArea

                        anchors.fill: parent

                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: Services.AudioService.output.toggleMute()
                    }
                }

                // Audio Status Texts
                ColumnLayout {
                    id: audioStatusTextColumn

                    Layout.alignment: Qt.AlignCenter

                    Layout.minimumHeight: currentStatusSection.statusSectionHeight
                    Layout.preferredHeight: currentStatusSection.statusSectionHeight
                    Layout.maximumHeight: currentStatusSection.statusSectionHeight

                    // Audio Status Text
                    Text {
                        id: audioStatusText

                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                        Layout.fillHeight: true

                        text: "Audio"

                        color: UI.Colors.foreground
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSize
                            bold: true
                        }

                        elide: Text.ElideRight
                    }

                    // Audio Volume Status Text
                    Text {
                        id: audioVolumeStatusText

                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                        Layout.fillHeight: true

                        text: {
                            if (Services.AudioService.output.isMuted) {
                                return "Muted";
                            }

                            let volume = Services.AudioService.output.volume;
                            if (volume === 0) {
                                return "Silenced";
                            } else if (volume > 0 & volume < 15) {
                                return "Whisper";
                            } else if (volume >= 15 & volume < 30) {
                                return "Murmur";
                            } else if (volume >= 30 & volume < 50) {
                                return "Easy Listening";
                            } else if (volume >= 50 & volume < 70) {
                                return "Steady Groove";
                            } else if (volume >= 70 & volume < 85) {
                                return "Cranked Up";
                            } else if (volume >= 85 & volume < 100) {
                                return "Party Mode";
                            } else if (volume === 100) {
                                return "Concert Hall";
                            } else if (volume > 100) {
                                return "Overdrive";
                            }
                        }

                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                            bold: true
                        }

                        elide: Text.ElideRight
                    }
                }

                // Gap element
                Item {
                    Layout.fillWidth: true
                }
            }

            // Separator
            Rectangle {
                Layout.leftMargin: volumeModule.popupSectionMargin
                Layout.rightMargin: volumeModule.popupSectionMargin

                Layout.fillWidth: true
                Layout.minimumHeight: 1
                Layout.preferredHeight: 1
                Layout.maximumHeight: 1

                color: UI.Colors.backgroundSurface
                opacity: 1
            }

            // Output settings section
            ColumnLayout {
                id: outputSettingsSection

                Layout.alignment: Qt.AlignCenter
                Layout.margins: volumeModule.popupSectionMargin

                Layout.fillHeight: false
                Layout.fillWidth: true

                spacing: 0

                // Output section header row
                RowLayout {
                    id: outputSectionHeaderRow

                    Layout.fillWidth: true
                    Layout.minimumHeight: 20
                    Layout.preferredHeight: 20
                    Layout.maximumHeight: 20

                    spacing: 0

                    // Output header text
                    Text {
                        id: outputHeaderText

                        text: "Output"

                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }

                    // Gap element
                    Item {
                        Layout.fillWidth: true
                    }

                    // Output volume text
                    Text {
                        id: outputVolumeText

                        text: Services.AudioService.output.volume + "%"

                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }
                }

                // Output volume slider
                Slider {
                    id: outputVolumeSlider

                    focus: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: 30
                    Layout.preferredHeight: 30
                    Layout.maximumHeight: 30

                    from: 0
                    to: 100
                    stepSize: 1
                    value: Services.AudioService.output.volume

                    onMoved: Services.AudioService.output.setVolume(value / 100)

                    background: Rectangle {
                        x: outputVolumeSlider.leftPadding
                        y: outputVolumeSlider.topPadding + outputVolumeSlider.availableHeight / 2 - height / 2

                        width: outputVolumeSlider.availableWidth
                        height: 4
                        radius: 2
                        color: UI.Colors.backgroundSurface

                        Rectangle {
                            width: outputVolumeSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: UI.Colors.accent
                        }
                    }

                    handle: Rectangle {
                        x: outputVolumeSlider.leftPadding + outputVolumeSlider.visualPosition * (outputVolumeSlider.availableWidth - width)
                        y: outputVolumeSlider.topPadding + outputVolumeSlider.availableHeight / 2 - height / 2

                        width: 14
                        height: 14
                        radius: 7
                        color: outputVolumeSlider.pressed ? UI.Colors.backgroundHover : UI.Colors.foreground
                    }
                }

                // Output device name
                Rectangle {
                    id: activeOutputDeviceName

                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: 35
                    Layout.preferredHeight: 35
                    Layout.maximumHeight: 35

                    color: UI.Colors.backgroundSurface

                    Text {
                        anchors.centerIn: parent

                        text: "󰓃  " + Services.AudioService.output.defaultSink.description

                        color: UI.Colors.foreground
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.leftMargin: volumeModule.popupSectionMargin
                Layout.rightMargin: volumeModule.popupSectionMargin

                Layout.fillWidth: true
                Layout.minimumHeight: 1
                Layout.preferredHeight: 1
                Layout.maximumHeight: 1

                color: UI.Colors.backgroundSurface
                opacity: 1
            }

            // Input settings section
            ColumnLayout {
                id: inputSettingsSection

                Layout.alignment: Qt.AlignCenter
                Layout.margins: volumeModule.popupSectionMargin

                Layout.fillHeight: false
                Layout.fillWidth: true

                spacing: 0

                // Input section header row
                RowLayout {
                    id: inputSectionHeaderRow

                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: 20
                    Layout.preferredHeight: 20
                    Layout.maximumHeight: 20

                    spacing: 0

                    // Input header text
                    Text {
                        id: inputHeaderText

                        text: "Input"

                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }

                    // Gap element
                    Item {
                        Layout.fillWidth: true
                    }

                    // Input volume text
                    Text {
                        id: inputVolumeText

                        text: Services.AudioService.input.volume + "%"

                        color: UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }
                }

                // Input volume slider
                Slider {
                    id: inputVolumeSlider

                    focus: false
                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: 30
                    Layout.preferredHeight: 30
                    Layout.maximumHeight: 30

                    from: 0
                    to: 100
                    stepSize: 1
                    value: Services.AudioService.input.volume

                    onMoved: Services.AudioService.input.setVolume(value / 100)

                    background: Rectangle {
                        x: inputVolumeSlider.leftPadding
                        y: inputVolumeSlider.topPadding + inputVolumeSlider.availableHeight / 2 - height / 2

                        width: inputVolumeSlider.availableWidth
                        height: 4
                        radius: 2
                        color: UI.Colors.backgroundSurface

                        Rectangle {
                            width: inputVolumeSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: UI.Colors.accent
                        }
                    }

                    handle: Rectangle {
                        x: inputVolumeSlider.leftPadding + inputVolumeSlider.visualPosition * (inputVolumeSlider.availableWidth - width)
                        y: inputVolumeSlider.topPadding + inputVolumeSlider.availableHeight / 2 - height / 2

                        width: 14
                        height: 14
                        radius: 7
                        color: inputVolumeSlider.pressed ? UI.Colors.backgroundHover : UI.Colors.foreground
                    }
                }

                // Input device name
                Rectangle {
                    id: activeInputDeviceName

                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.minimumHeight: 35
                    Layout.preferredHeight: 35
                    Layout.maximumHeight: 35

                    color: UI.Colors.backgroundSurface

                    Text {
                        anchors.centerIn: parent

                        text: "  " + Services.AudioService.input.defaultSource.description

                        color: UI.Colors.foreground
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }
                }
            }
        }
    }
}
