import QtQuick

import "."
import "../ui" as UI

// SimpleBarWidget — the simplified base (ticket 06).
//
// For the trivial label-plus-click widgets (CPU, memory, battery, bluetooth,
// notification, idle-lock): a widget that is a piece of text and a click.
//
// It exists so those widgets are NOT forced to declare capabilities they do not
// have. A trivial widget has no panel, so under BarWidget alone it would have to
// write out an empty panelContent Component and a hand-built content Component —
// precisely the "pretending to have a panel with an empty one" the contract is
// written to forbid. Here such a widget declares two things:
//
//     SimpleBarWidget {
//         required property string label
//         activate: function (widget) { ... }
//     }
//
// and inherits `content` (a styled label) and `tooltip` from this file.
//
// It is still ON the contract, not beside it: it extends BarWidget, so it has
// the same required members, the same hover affordance, and the same optional
// panel content. Anything that needs a panel extends BarWidget directly.
BarWidget {
    id: simple

    // The one thing a trivial widget says: what it says.
    required property string label

    // The label IS the content. It sizes itself from the text, which is what
    // feeds the base's implicitWidth/implicitHeight.
    content: Component {
        Text {
            text: simple.label
            color: UI.Colors.foreground
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSize
            }
        }
    }

    // A trivial widget's tooltip is its label. A widget whose tooltip says
    // something more assigns its own.
    tooltip: simple.label
}