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
//   The bar itself. The three-zone arrangement, the true centring of the
//   centre zone, the floating rounded island, the full-width background and the
//   surfaces themselves are ticket 08. This type hands it three populated zones
//   and stays out of the way.
//
//   The Row below is the least that makes "these entries, in this order" an
//   observable thing at all — a zone whose widgets are built but piled at one
//   position cannot show that a reorder took effect. It is not the bar's
//   layout, and ticket 08 is expected to replace it.
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
    function rebuild(): void {
        const old = row.children
        for (let i = 0; i < old.length; i++) {
            old[i].destroy()
        }
        const built = []
        const entries = zone.entries
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i]
            const widget = zone.construct(entry, row, Bar.BarConfig.componentFor(entry.type))
            if (widget !== null) {
                built.push(entry.type)
            }
        }
        zone._built = built
    }

    Component.onCompleted: zone.rebuild()

    onEntriesChanged: zone.rebuild()
}