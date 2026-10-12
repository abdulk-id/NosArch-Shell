import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "."
import "../ui" as UI
import "../../components" as Components

// VolumeWidget — output volume, on the panel architecture (ticket 11).
//
// WHAT THIS IS
//
//   The first widget whose point is a PANEL rather than a label: the bar shows
//   an icon, the click opens a card with a slider, and that slider is the
//   interaction the popup architecture could not support. Dragging a control
//   inside a popup with `grabFocus` dismissed the popup under the pointer,
//   because grabbing focus on a click IS the outside-click dismissal — and the
//   fix the old code reached for was a recursive walk over the popup's entire
//   item tree clearing `focus` on every descendant.
//
//   That walk is deleted rather than ported (docs/adr/0002). Nothing here
//   watches the pointer to decide whether to dismiss: dismissal is a click on
//   the panel surface's own background, which sits BEHIND the card, so a press
//   that lands on the slider is the slider's press and nothing else. The slider
//   is also focused the moment the panel opens (see PanelCard.qml), so the panel
//   is usable with no mouse at all — which the old walk prevented by disabling
//   focus everywhere.
//
// PRESENTATION IS NOT IN THE SERVICE (ADR 0001)
//
//   AudioService reports what is true. It no longer publishes a glyph at all:
//   the icon decision lives in components/VolumeIcon.qml, and the COLOUR
//   — which is a palette question — is made here, where UI.Colors is reachable.
//   See VolumeIcon.qml for why the glyph is a shared component and not simply
//   a property on this file.

BarWidget {
    id: volume

    // Which panel this widget opens, on its own surface. ASSIGNED, not
    // re-declared: the base property is plain for the reason documented at it
    // (a derived `readonly` re-declaration compiles clean and does nothing).
    // The id that reaches the shell is `panel-volume`, derived by the contract.
    widgetName: "volume"

    // ---- the presentation, read once ----------------------------------------
    readonly property var icon: Components.VolumeIcon {
        // Parentless on purpose: this is a QtObject, and parenting it into the
        // widget's visual tree would put it in the content Loader. It dies with
        // this widget either way, because QML owns it as a property value.
    }

    tooltip: volume.readableState

    // One call, both directions. `togglePanel` is on the contract: it checks a
    // coordinator was handed over and passes THIS widget as the anchor, so the
    // card is placed under the icon the user actually clicked.
    activate: function (widget) {
        widget.togglePanel(widget.panelId)
    }

    // Muted is shown DISTINCTLY, not merely by a different glyph: the muted
    // glyph is also what a zero volume looks like, so colour is what actually
    // separates "deliberately silenced" from "already at nothing" — and the
    // palette's alert colour is what the user reads as wrong.
    readonly property color glyphColor: volume.icon.silent
        ? UI.Colors.alertRed
        : UI.Colors.foreground

    // The one-line description for the bar's tooltip: the device's own name and
    // its state, both read from the service. This is the thing the old widget
    // could not say — it showed the same glyph as the bar with no explanation.
    readonly property string readableState: {
        if (!volume.icon.ready) {
            return "Audio: waiting for a device"
        }
        return volume.icon.deviceName
            + (volume.icon.bluetooth ? " (Bluetooth)" : "")
            + (volume.icon.isMuted ? " — muted" : " — " + volume.icon.volume + "%")
    }

    // ---- the panel content --------------------------------------------------
    //
    // A Component, as the contract requires. NOT a PopupWindow: the shell draws
    // this inside the card, on the overlay surface, with the card placed under
    // this widget and the dismissal behind it.
    panelContent: Component {
        ColumnLayout {
            spacing: 8

            // ---- header: the device, and the mute toggle ------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: volume.icon.glyph
                    color: volume.glyphColor
                    font {
                        family: UI.Fonts.fontFamily
                        pixelSize: UI.Fonts.fontSizeIcons
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: volume.icon.ready ? volume.icon.deviceName : "Audio"
                    color: UI.Colors.foreground
                    font {
                        family: UI.Fonts.fontFamily
                        pixelSize: UI.Fonts.fontSizeSmall
                        bold: true
                    }
                    elide: Text.ElideRight
                }

                // The mute toggle. A real Button rather than a Rectangle with a
                // MouseArea on it, so it is REACHABLE BY TAB from the slider:
                // the panel is meant to be usable without a mouse, and a
                // hand-rolled rectangle is invisible to the focus ring and to
                // `activate` on Enter.
                Button {
                    id: muteButton

                    // Focusable, and deliberately NOT stealing focus on open —
                    // the slider is the focus target (see PanelCard.qml), and
                    // two controls both wanting focus on load would leave it to
                    // whichever was constructed last.
                    focus: false

                    implicitWidth: 30
                    implicitHeight: 26

                    onClicked: volume.icon.output.toggleMute()

                    background: Rectangle {
                        radius: 6
                        color: muteButton.down
                            ? UI.Colors.backgroundSurface
                            : UI.Colors.backgroundHover
                    }

                    contentItem: Text {
                        text: volume.icon.isMuted ? "󰔧" : "󰔣"
                        color: volume.icon.isMuted
                            ? UI.Colors.alertRed
                            : UI.Colors.foregroundSecondary
                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                    ToolTip.text: volume.icon.isMuted ? "Unmute" : "Mute"
                }
            }

            // ---- the slider ------------------------------------------------
            //
            // `from: 0, to: 100` because the service reports a percentage, and
            // the old code converted at BOTH ends of the same binding — which is
            // where a 0.05/100 mix-up hides. One conversion, here, at the edge.
            Slider {
                id: slider

                // FOCUS IS THE POINT. The pre-rewrite slider said `focus: false`,
                // and the popup base then walked the whole tree clearing focus
                // anyway; here the panel focuses this control the moment it
                // opens, so arrow keys change the volume with no mouse at all.
                focus: true

                Layout.fillWidth: true
                Layout.preferredHeight: 24

                from: 0
                to: 100
                stepSize: 1

                // One-way into the control (value ← service) so an external
                // change — a hardware key, another application — moves the
                // handle too, and one-way out (`onMoved`) so a drag is not
                // fighting the binding it is writing through.
                value: volume.icon.volume
                onMoved: volume.icon.output.setVolume(slider.value / 100)

                background: Rectangle {
                    x: slider.leftPadding
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth
                    height: 4
                    radius: 2
                    color: UI.Colors.backgroundSurface

                    Rectangle {
                        width: slider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: volume.icon.muted ? UI.Colors.alertRed : UI.Colors.accent
                    }
                }

                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition
                        * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: 14
                    height: 14
                    radius: 7
                    color: slider.pressed ? UI.Colors.backgroundHover : UI.Colors.foreground
                }
            }

            // ---- the status line -------------------------------------------
            //
            // Read from the shared presentation, so the word and the glyph can
            // never disagree about whether the output is muted.
            Text {
                Layout.fillWidth: true
                text: volume.icon.statusLine
                color: volume.icon.isMuted
                    ? UI.Colors.alertRed
                    : UI.Colors.foregroundSecondary
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSizeSmall
                    bold: true
                }
                elide: Text.ElideRight
            }
        }
    }

    // ---- the bar's own content ---------------------------------------------
    //
    // The icon, with a Bluetooth badge beside it when the output is one. Reads
    // the same properties the panel reads, so there is one answer to "what does
    // the volume look like now" and it is in one place.
    content: Component {
        Row {
            spacing: 3

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: volume.icon.glyph
                color: volume.glyphColor
                font {
                    family: UI.Fonts.fontFamily
                    // -2 because the volume glyphs are drawn larger than the
                    // other bar glyphs and the bar's height is fixed.
                    pixelSize: UI.Fonts.fontSizeIcons - 2
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // An EMPTY string rather than visible: false, so the Row's width
                // is the icon's alone when there is no badge. A gap in the bar
                // for a device that is not Bluetooth would be a phantom widget.
                text: volume.icon.isBluetooth ? volume.icon.bluetoothGlyph : ""
                color: UI.Colors.foregroundMuted
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSizeIcons - 4
                }
            }
        }
    }
}