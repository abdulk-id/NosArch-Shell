import QtQuick

import "."
import "../panels" as Panels
import "." as Bar

// BarZone — one zone's worth of the bar, built from configuration (ticket 07).
//
// WHAT THIS IS
//
//   The instantiation step, and nothing more. Given a zone name it asks
//   BarConfig which entries belong to that zone and builds one widget per
//   entry, in the file's own order. It is the seam between "what the user
//   wrote" and "what is on the bar".
//
// WHAT THIS IS DELIBERATELY NOT
//
//   The bar itself, and — since ticket 08 — the bar's layout. The
//   three-zone arrangement, the true centring of the centre zone, the floating
//   rounded island, the full-width background and the surfaces themselves are
//   BarSurface and Bar. This type hands it three populated zones and stays out
//   of the way.
//
//   It sizes itself to those zones' contents and NOTHING more. It does not
//   decide where it goes, and that division is load-bearing rather than tidy:
//   a zone that placed itself would either be positioned relative to the bar's
//   centre (and so move when its neighbours changed width) or relative to its
//   neighbours (which is the accidental-symmetry layout this ticket replaces).
//   Placement belongs to the one thing that knows the bar's full width, and
//   scripts/verify-bar-surface.sh measures the result.
//
//   The Row below is therefore a pure CONTENTS row — a zone whose widgets were
//   built but piled at one position could not show that a reorder took effect.
//
// WHY CONSTRUCTION IS IMPERATIVE AND NOT A LOADER
//
//   A Loader given a component that cannot be built logs its own failure,
//   naming a file in this repository — which is exactly the signal the other
//   verifiers treat as a defect. The failure policy here is not a defect: it is
//   the designed behaviour, and it has to be quiet in QML's own log and loud in
//   ours. So the object is created directly, the null return is handled, and
//   the skip is reported through BarConfig under the same format as every other
//   skipped entry. BarZone cannot load anything itself: it is handed a
//   Component and never resolves a name, so configuration cannot become code
//   even here.
Item {
    id: zone

    // "left", "center" or "right". Required rather than defaulted, because a
    // zone that silently drew nothing is the kind of bug that only shows up as
    // an empty stretch of bar.
    required property string zoneName

    // The panel coordinator for the surface this zone is on (ticket 11).
    // Optional, defaulting to null, because a zone is built and measured on its
    // own in the smoke test — where there is no window and so no panel layer to
    // own a coordinator. Null there means "widgets get no coordinator", which is
    // exactly right for a headless run.
    property Panels.PanelCoordinator panelCoordinator: null

    readonly property var entries: Bar.BarConfig.entriesFor(zone.zoneName)

    property int spacing: 20

    // Sized by what it holds, so whoever places the zone can place it without
    // asking. An Item's width and height are bound to these by default, so
    // anchoring this to an edge is enough — nothing has to be told the size.
    // An empty zone measures zero and simply occupies no space, which is what
    // makes "remove a widget by deleting one configuration line" work without
    // leaving a hole behind.
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    readonly property bool isEmpty: zone.builtCount === 0

    // The widgets actually built, in order. Tracked here rather than counted
    // off row.children, because destroy() is deferred and the count would
    // briefly disagree with what is on screen after a configuration edit.
    // The built widgets, in order. `builtCount` is derived from this rather than
    // counted separately, so the two can never disagree.
    property var _built: []
    readonly property var built: zone._built
    readonly property int builtCount: zone._built.length
    Row {
        id: row
        spacing: zone.spacing
    }

    // Build one widget from one validated entry. Returns the widget, or null
    // having said why in the log — never throws, because a widget that cannot
    // be built must cost one missing icon and not the bar.
    //
    // `component` is a parameter rather than something looked up here: this
    // function resolves nothing, so there is no path by which anything this
    // shell reads could decide what code to run.
    function construct(entry: var, parent: Item, component: Component): Item {
        const where = "bar.zones." + (entry.zone === undefined ? zone.zoneName : entry.zone)
        const index = entry.index === undefined ? -1 : entry.index
        if (component === null || component === undefined) {
            return Bar.BarConfig.skipAt(where, index, {
                type: entry.type, reason: "widget-failed-to-load"
            })
        }
        // The entry's settings, verbatim, become the widget's `options` at
        // construction (ticket 09). This is the ONLY place options cross from
        // configuration into a widget, and it is one property on the contract,
        // so no widget needs to know it was built from configuration at all.
        //
        // `entry.settings` is already the entry minus its `type`, deep-copied by
        // the reader, so nothing here re-parses or re-validates it. The
        // `undefined` case is not hypothetical: `construct` is public and the
        // smoke test calls it with a hand-built entry, so an entry that never
        // went through the reader must not crash the zone.
        const settings = (entry.settings === undefined || entry.settings === null)
            ? ({})
            : entry.settings

        // The panel coordinator, handed over only to a widget that DECLARES a
        // panel (ticket 11).
        //
        // Gated on `hasPanel` rather than always passed, for the reason
        // documented at length in BarWidget.qml: createObject() ignores a named
        // property the type does not have, so passing one to every widget would
        // be harmless — but a widget that is handed a coordinator it never asked
        // for could open a panel it has no `panelContent` for. The gate makes
        // "can this widget open a panel" one readable property, and it is the
        // same one the rest of the shell asks.
        //
        // Handed as an extra key on the same object as `options`, so there is
        // still exactly ONE place where anything crosses from configuration or
        // from the surface into a widget.
        let widget = null
        try {
            widget = component.createObject(parent !== null ? parent : row, {
                options: settings
            })
        } catch (e) {
            Bar.BarConfig.skipAt(where, index, {
                type: entry.type, reason: "widget-threw-while-building", detail: "" + e
            })
            return null
        }
        if (widget === null) {
            // The one failure validation cannot predict: the widget's file
            // loaded and the name resolved, but the object would not construct
            // (a required member it does not supply, for instance).
            Bar.BarConfig.skipAt(where, index, {
                type: entry.type, reason: "widget-failed-to-construct"
            })
            return null
        }
        // Options the widget does not declare are refused BY NAME, and the
        // widget is kept. The widget is the only thing that knows what it
        // declares, so it is the only place this question can be answered —
        // which is why the check lives here, immediately after construction,
        // rather than in the reader (which cannot know) or in each widget
        // (which would make twelve copies of one rule).
        //
        // Reported through BarConfig so it lands in the same CONFIG stream as
        // every other configuration complaint. See the decision and its
        // reasoning at reportUnrecognisedOption.
        if (widget.unrecognisedOptions !== undefined && widget.unrecognisedOptions !== null) {
            const unrecognised = widget.unrecognisedOptions
            for (let u = 0; u < unrecognised.length; u++) {
                Bar.BarConfig.reportUnrecognisedOption(where, index, entry.type,
                    unrecognised[u], Object.keys(widget.optionDefaults === undefined
                        ? ({}) : widget.optionDefaults))
            }
        }
        // The panel coordinator, handed to a widget that OFFERS a panel
        // (ticket 11) — and only after the widget exists, because `hasPanel` is
        // a property of the instance and a Component cannot report it.
        //
        // Assigned rather than passed at construction, and that is safe here
        // precisely because `panelCoordinator` is a property ON THE CONTRACT
        // (BarWidget) with a default of null: an assignment to a property that
        // does not exist would throw ("Cannot assign to non-existent property"),
        // so the gate is what keeps an ordinary widget — which does not declare
        // a panel and therefore need no coordinator — from being handed one it
        // has no use for. See the note in BarWidget.qml.
        if (zone.panelCoordinator !== null && widget.hasPanel === true) {
            widget.panelCoordinator = zone.panelCoordinator
        }
        return widget
    }

    // (Re)build the zone from the current configuration. Runs at startup and
    // again whenever the entries change, which is what makes editing the file
    // update the bar without restarting the shell.
    //
    // Two things here are not obvious and both were found by measuring the bar
    // rather than by reading it:
    //
    //   * destroy() is DEFERRED. A widget on its way out stays in row.children
    //     until the end of the frame, and a Row sizes itself off its children —
    //     so a rebuilt zone is briefly as wide as the old widgets AND the new
    //     ones, and the zone next to it visibly jumps. Taking each dying widget
    //     out of the row before destroying it removes it from the measurement
    //     immediately, which is the whole reason `parent` is assigned here.
    //   * the entries arrive, and then they change again. The reader settles its
    //     verdict after this object is constructed, so `entriesChanged` fires
    //     once after startup with the same list the completed handler already
    //     built. Rebuilding on that would construct every widget twice for
    //     nothing, so the signature is compared first.
    function rebuild(): void {
        const entries = zone.entries
        const signature = zone._signatureOf(entries)
        if (signature === zone._signature) {
            return                      // nothing changed; do not rebuild for it
        }
        zone._signature = signature
        const old = row.children
        for (let i = 0; i < old.length; i++) {
            // Out of the row first, then destroyed: see above.
            old[i].parent = null
            old[i].destroy()
        }
        const built = []
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i]
            const widget = zone.construct(entry, row, Bar.BarConfig.componentFor(entry.type))
            if (widget !== null) {
                // The INSTANCE, not the type name. `built` is read by the panel
                // layer to find the widget that declares a given panel id, which it
                // cannot do from a name alone — and a name would have to be looked
                // up again, which is the indirection the widget registry exists to
                // avoid. `builtCount` is unchanged by this, so every reader of the
                // count sees exactly what it saw before.
                built.push(widget)
            }
        }
        zone._built = built
    }

    // What is currently built, as one comparable string. Compared rather than
    // deep-compared because it only has to notice a change, not describe one:
    // the widget name, in the widget's own order, is the whole of it.
    property string _signature: "\u0000never-built"

    function _signatureOf(entries: var): string {
        const parts = []
        for (let i = 0; i < entries.length; i++) {
            parts.push(entries[i].type)
        }
        return zone.zoneName + ":" + parts.join(",")
    }

    Component.onCompleted: zone.rebuild()

    onEntriesChanged: zone.rebuild()
}