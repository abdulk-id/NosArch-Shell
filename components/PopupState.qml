import QtQml

// PopupState — which panel is open ON ONE SURFACE (ticket 10).
//
// WHAT THIS REPLACES, AND WHY IT HAD TO BE REPLACED RATHER THAN FIXED
//
//   The pre-rewrite bar held popup state in ONE object shared by every monitor:
//   `popupStateManager`, with `set(id, screen)` and `isActive(id, screen)` —
//   and `isActive` silently answered "active on any screen" when the caller
//   omitted its screen argument. That optional argument is the whole bug.
//
//   The base widget passed two arguments (`set(id, screen.name)`); the network
//   widget passed one (`set(id)`). Both calls succeeded, both read back
//   correctly against a single monitor, and on a second monitor the one-arg
//   caller would have been answered "yes, active" on EVERY output — the network
//   panel appearing on the monitor it was not opened from. Two widgets calling
//   the same function with different arities cannot disagree loudly, so they
//   disagree quietly, and the disagreement is invisible until a second monitor
//   exists.
//
//   The fix is not to make the argument required and hope every caller
//   supplies it. That leaves the same fragility one space over: the monitor
//   would still be a per-widget string each widget has to get right, and
//   getting it wrong is again silent.
//
// WHAT REPLACES IT
//
//   This object has no monitor notion AT ALL. One instance lives inside each
//   layer-shell surface, so "which monitor" is answered by which instance a
//   widget holds — and a widget cannot name the wrong one, because there is no
//   name to name and no argument that could be omitted. Every call takes the
//   panel's id and nothing else, so the arity question cannot arise.
//
//   It is also what makes one-panel-at-a-time per monitor the natural reading:
//   one slot, so opening the network panel on a monitor closes the volume panel
//   on THAT monitor, and cannot touch the volume panel on another one.
//
// THE BAR-LEVEL COORDINATOR IS NOT HERE
//
//   Ticket 11 owns panels as layer-shell overlay surfaces, and this is not
//   that: it draws nothing, maps nothing, and knows nothing about focus or
//   dismissal. It is the state half, made per-surface, because the state is
//   what cannot be allowed to disagree between widgets.
QtObject {
    id: state

    // The id of the panel open on this surface, or "" for none. Plain and
    // writable: nothing derives it, so a binding loop is not possible.
    property string activeId: ""

    readonly property bool isEmpty: state.activeId === ""

    // Open this panel, or close it if it is already the open one. One call for
    // both directions, so a widget cannot open its panel and then immediately
    // be told it is somehow not open.
    function toggle(id: string): void {
        state.activeId = state.activeId === id ? "" : id;
    }

    // Whether THIS surface's panel `id` is the open one. A widget asking this
    // is asking about its own surface by construction.
    function isActive(id: string): bool {
        return state.activeId === id;
    }

    // Dismiss, from anywhere: Escape, an outside click, another widget taking
    // over. Takes no arguments, because it does not mean "close mine".
    function close(): void {
        state.activeId = "";
    }
}