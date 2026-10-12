import QtQuick

import "../ui" as UI
import "."

// PanelCard — the visible panel: its background, its content, and its keyboard
// focus target (ticket 11).
//
// WHAT THIS IS
//
//   The card a widget's `panelContent` is drawn into, and nothing else. It is a
//   plain Item, NOT a window: the surface is PanelSurface.qml's job, and
//   splitting the two is what lets this file be instantiated and driven with no
//   compositor involved at all (smoke.qml does exactly that, and can therefore
//   assert that a panel takes keyboard focus and that Escape dismisses it
//   headlessly). The card owns the answers to "where does the key go" and
//   "what does Escape do"; the surface owns "is there a surface".
//
// WHY IT IS A FOCUS SCOPE, AND WHY THAT MATTERS
//
//   The root is a `FocusScope` rather than a Rectangle for one specific reason.
//   The ticket's promise is that INTERACTIVE ELEMENTS INSIDE A PANEL TAKE
//   KEYBOARD FOCUS — the volume slider, not the panel frame. Qt implements
//   exactly that: when a FocusScope takes active focus, it hands it to the
//   first item inside it that declared `focus: true`. So focusing the card is
//   the same as focusing the slider, without the card knowing what a slider is.
//
//   That is the inverse of the pre-rewrite arrangement, and the inversion is
//   the whole point of this file's existence. The popup base set grabFocus,
//   using a control inside it therefore dismissed the popup, and the fix was a
//   recursive walk over the entire item tree clearing `focus` and
//   `activeFocusOnTab` on every descendant. That walk disabled precisely the
//   in-panel keyboard focus a panel exists to provide, and it did it by
//   disabling focus everywhere. It is deleted rather than ported (ADR 0002).
//
// WHERE FOCUS ACTUALLY GOES
//
//   Two rules, in order:
//     1. if the loaded content names a `focusTarget`, that item is focused;
//     2. otherwise the card is focused, and the FocusScope forwards into the
//        content (rule 1's fallback for a panel whose content has no particular
//        control to point at).
//   Both paths are exercised by smoke.qml, so neither is speculative.

FocusScope {
    id: card

    // Which panel this card is showing. "" when there is none — a card with no
    // panel draws nothing, and the surface does not show it at all.
    required property string panelId

    // The widget's own panel content, handed over by the surface. A widget with
    // no panel declares no panelContent (BarWidget's contract), so this can be
    // null and the card renders as an empty frame rather than inventing content.
    property Component content: null

    // The coordinator to dismiss through. TYPED, so a card handed something
    // else fails to construct instead of quietly never dismissing — the lesson
    // from ticket 09, where an untyped property held a state object and two
    // callers disagreed about its shape without either of them noticing.
    property PanelCoordinator panelCoordinator: null

    // The item that holds active focus, after focusContent() has run. Reported
    // so "the panel took keyboard focus" is a value the shell can log rather
    // than something a reader has to take on trust.
    property Item focusTarget: null

    // ---- appearance --------------------------------------------------------
    //
    // The palette, never a literal: the card is themed exactly like the bar it
    // hangs from. (verify-bar-surface.sh applies the same rule to the bar.)
    property int padding: 12
    property int cornerRadius: 12
    property int preferredWidth: 320

    implicitWidth: card.preferredWidth
    implicitHeight: Math.max(card.minimumHeight, body.implicitHeight + 2 * card.padding)

    // A panel is never a sliver: a card with content that measures zero still
    // has to be clickable and dismissable, and a zero-height item is neither.
    property int minimumHeight: 96

    Rectangle {
        id: frame

        anchors.fill: parent
        radius: card.cornerRadius
        color: UI.Colors.background

        border {
            width: 1
            color: UI.Colors.accent
        }
    }

    Loader {
        id: body

        anchors.fill: parent
        anchors.margins: card.padding
        sourceComponent: card.content
    }

    // ---- keyboard ----------------------------------------------------------
    //
    // Escape closes the panel, from anywhere inside it: a key event from the
    // focused slider propagates up through this card, so the handler does not
    // have to know which control inside it holds focus. That is the difference
    // between a panel you can tab around in and one you have to click your way
    // out of.
    Keys.onEscapePressed: {
        if (card.panelCoordinator !== null) {
            card.panelCoordinator.close()
            card.escapeAccepted = true
        }
    }

    property bool escapeAccepted: false

    // Force active focus onto the panel's focus target, and report whether it
    // ARRIVED. Returning the answer rather than assuming it is what makes this
    // observable: `forceActiveFocus()` returns nothing and a panel that silently
    // failed to take focus would look identical to one that did not, which is
    // the failure the spec's "accepts keyboard input the instant it opens"
    // promise is about.
    //
    // Called by the surface once the surface has mapped — not at construction.
    // An item in a surface that has not been given to the compositor yet cannot
    // hold focus, so doing it earlier would report a false failure and, worse,
    // would leave the panel unfocused for good.
    function focusContent(): bool {
        let target = card
        const loaded = body.item
        // `in` rather than a bare read: a property that does not exist reads as
        // undefined quietly, but a content item that HAS one is the common case
        // and must be preferred, so both halves are spelled out.
        if (loaded !== null && loaded !== undefined && "focusTarget" in loaded
                && loaded.focusTarget !== null && loaded.focusTarget !== undefined) {
            target = loaded.focusTarget
        }
        target.forceActiveFocus()
        card.focusTarget = target
        // Read back off the card, not off `target`: a FocusScope forwards focus
        // into its content, so `target.activeFocus` is false on the card path
        // even when the card does hold focus on its child's behalf.
        return card.activeFocus === true
    }

    // One comparable line for the log, carrying every value a reader needs to
    // tell "the panel has keyboard focus" from "it asked for focus and nothing
    // came back".
    function describe(): string {
        return "panel=" + (card.panelId === "" ? "none" : card.panelId)
            + " content=" + (card.content === null ? "none" : "loaded")
            + " focusTarget=" + (card.focusTarget === null ? "none" : "item")
            + " activeFocus=" + (card.activeFocus ? "yes" : "no")
            + " size=" + Math.round(card.width) + "x" + Math.round(card.height)
    }
}