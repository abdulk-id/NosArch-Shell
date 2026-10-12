import QtQml
import QtQuick

import "../../components" as Components

// PanelCoordinator — WHICH panel is open on this surface (ticket 11).
//
// WHAT THIS IS, AND WHAT IT IS NOT
//
//   This is the bar-level half of the panel architecture: the single place that
//   knows whether a panel is open, which one, and whether this surface owns
//   the user's input while it is. It owns NO window and draws nothing. The
//   surface half is PanelSurface.qml; the visible card is PanelCard.qml.
//
//   One of these lives inside each bar surface, beside the zones whose widgets
//   drive it, and it holds exactly one PopupState (ticket 10's per-surface
//   state half). That single slot is what makes "only one panel is open at a
//   time" STRUCTURAL rather than a rule each widget has to respect: there is
//   nowhere else for a second panel to go, so two panels cannot be open by
//   construction, and opening one necessarily displaces the incumbent.
//
// OWNERSHIP IS THE LOGICAL STATE, NEVER `visible`
//
//   ownsInput is the whole of the focus/click-ownership decision, and it is
//   derived from the state — whether a panel id is set — rather than from
//   whether the card happens to be drawn this frame. A close animation then
//   cannot keep the dismissal mask, the keyboard focus or the click ownership
//   alive for its own duration: the moment the id is cleared, the surface has
//   given everything back. That is the difference between a panel that lets go
//   of the desktop and one that keeps holding it for 150ms after the user asked
//   it to stop.
//
// WHY `anchorWidget` IS AN OBJECT AND NOT A POSITION
//
//   Which panel is open is state. Where it goes is derived, at the moment it is
//   placed, from the widget that opened it — so a panel that is repositioned
//   (the bar rebuilt, a widget moved) is placed from the widget's real geometry
//   rather than from a rectangle captured when it opened. A name or a stored
//   rect would both be a second thing to keep correct; an Item is the widget
//   itself, and it cannot be stale.
QtObject {
    id: coordinator

    // The per-surface panel state. One slot, no monitor anywhere in it: "which
    // monitor" is answered by which instance this object is, so there is no
    // string any widget could name wrongly. See components/PopupState.qml.
    property Components.PopupState popupState: Components.PopupState {}

    // The widget that opened the open panel — the anchor the card is placed
    // under. Null when no panel is open, and cleared on close so a closed panel
    // holds no reference to a widget the bar may have since rebuilt.
    property Item anchorWidget: null

    // ---- the state, read once so nothing downstream re-derives it ----------
    readonly property string openId: coordinator.popupState.activeId
    readonly property bool hasOpenPanel: coordinator.openId !== ""
    readonly property bool isEmpty: !coordinator.hasOpenPanel

    // OWNERSHIP. Focus and click ownership follow this and nothing else. The
    // name is deliberate: "ownsInput" says who has the user's clicks and keys,
    // which is the question every consumer is actually asking. Anything that
    // decides ownership from `visible` re-introduces the close-animation bug
    // this property exists to prevent.
    readonly property bool ownsInput: coordinator.hasOpenPanel

    // The panel id currently open, for reporting. "" is a value, not an absence:
    // a surface with nothing open is a state the shell describes all the time.
    function describe(): string {
        return "open=" + (coordinator.openId === "" ? "none" : coordinator.openId)
            + " owner=" + (coordinator.ownsInput ? "yes" : "no")
            + " anchored=" + (coordinator.anchorWidget === null ? "no" : "yes")
    }

    // Open a panel. Called when a widget is clicked. Re-opening the panel that
    // is already open is a no-op rather than a close, because a click means
    // "I want this one", and the way to close it is to click it again or click
    // away — a click on the SAME widget twice is therefore a toggle, which is
    // what `toggle` below is for.
    //
    // The incumbent is displaced by the same assignment, in the same pass,
    // with no intermediate state in which nothing is open: there is one slot,
    // so "switching panels in one click" is not a special case handled here,
    // it is the only thing a single slot can do.
    function open(panelId: string, widget: Item): void {
        if (panelId === "") {
            coordinator.close()
            return
        }
        if (coordinator.openId === panelId) {
            // Already open: keep the anchor pointing at the widget that is
            // actually there now, so a second click on a moved widget does not
            // leave the card where the old one was.
            if (widget !== null && widget !== undefined) {
                coordinator.anchorWidget = widget
            }
            return
        }
        coordinator.popupState.activeId = panelId
        coordinator.anchorWidget = (widget === undefined) ? null : widget
    }

    // One call for both directions, so a widget cannot open its panel and then
    // be told it is somehow not open — the failure the two-call version invites.
    function toggle(panelId: string, widget: Item): void {
        if (coordinator.openId === panelId) {
            coordinator.close()
            return
        }
        coordinator.open(panelId, widget)
    }

    // Dismiss, from anywhere: Escape, an outside click, another widget taking
    // over, a click on another output. Takes no arguments, because it does not
    // mean "close mine" — it means "no panel is open on this surface any more".
    function close(): void {
        coordinator.popupState.activeId = ""
        // Cleared here and not left to the surface: the anchor is the widget
        // that opened the panel, and a bar rebuild can destroy it. Holding a
        // reference to a destroyed widget would make the next placement read
        // geometry from nothing.
        coordinator.anchorWidget = null
    }
}