import QtQuick

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
        let widget = null
        try {
            widget = component.createObject(parent !== null ? parent : row, {})
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
                built.push(entry.type)
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