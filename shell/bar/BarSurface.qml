import QtQuick

import "." as Bar
import "../ui" as UI

// BarSurface — the bar itself: three zones, one plate, one surface (ticket 08).
//
// WHAT THIS IS
//
//   The bar the user actually sees. It holds three BarZones, fills itself with
//   the palette, and rounds and insets itself when the configuration says the
//   bar is floating. It draws nothing but a surface is not part of it: Bar.qml
//   owns the window, this owns everything inside it, and BarSurface is a plain
//   Item — which is why smoke.qml can instantiate it, measure it, and still
//   draw nothing on the user's desktop.
//
// THE THREE ZONES, AND WHY THEY ARE ANCHORED RATHER THAN LAID OUT
//
//   This is the substance of the ticket, so it is worth being precise about
//   what was wrong before. The pre-rewrite bar put its centre in an overlay
//   Item that filled the plate, with a row pinned to the clock's left edge and
//   the clock centred in that overlay. That LOOKED centred — because the two
//   flanking rows happened to be about the same width — but it was not a
//   three-zone bar at all: there was no independent right-hand zone, and the
//   "zone to the left of the clock" was positioned relative to the clock rather
//   than being a zone. Reorder or resize a wing and the arrangement had no
//   defined behaviour.
//
//   Here each zone is anchored to its own edge of one container:
//
//     left    → parent.left              hug the left edge
//     center  → parent (centreIn)        placed against the CONTAINER alone
//     right   → parent.right             hug the right edge
//
//   and the container is a plain Item. Deliberately NOT a Row or a RowLayout:
//   those hand each child whatever width is left after the others, so the
//   centre's position would depend on the wings again — the same accidental
//   symmetry under a different name. scripts/verify-bar-surface.sh asserts the
//   absence of every layout type here, so this cannot quietly regress.
//
//   The consequence is the promise the ticket makes: the centre zone's x is
//   (barWidth - centreWidth) / 2 and nothing else. Change the left zone from
//   three widgets to none, or the right zone from none to five, and the centre
//   does not move by a pixel. The verifier measures exactly that, with
//   deliberately lopsided wings.
//
//   What this layout does NOT do is steal space: if the wings are together
//   wider than half the bar, they will overlap the centre rather than push it.
//   That is the honest behaviour for a bar whose width is the screen's, and the
//   answer to too many widgets is a configuration edit — which is the point of
//   having one.
//
// FLOATING AND FULL-WIDTH
//
//   One switch, `bar.floating`, read from BarConfig (the schema is owned
//   there). Floating means two things together, because either alone looks
//   wrong: the surface is inset from the screen edges by edgeMargin, and the
//   plate's corners are rounded. Full-width means both of those are zero. The
//   inset is applied by the WINDOW as margins rather than by insetting this
//   item, so the transparent gap is not clickable — a bar that swallowed clicks
//   in the space where it is not drawn would be a bug, not a style.
//
//   The fill is UI.Colors.background. There is no colour literal in this file,
//   and verify-bar-surface.sh fails if one appears.

Item {
    id: surface

    // Which surface this is, for the log line that describes it — the screen's
    // name in the real shell, "smoke"/"probe" in the smoke test. Required
    // rather than defaulted so a surface that cannot say which one it is fails
    // to construct rather than reporting itself as every bar at once.
    required property string surfaceId

    // ---- appearance: one switch, read from configuration --------------------

    readonly property bool floating: Bar.BarConfig.floating

    // What `floating` means geometrically. Read from the reader, beside the flag
    // itself, because the window needs the same two numbers as its margins and
    // two copies of "8" is how a bar ends up with a rounded plate inside a
    // square-edged window. See BarConfig's "floating geometry" block.
    readonly property int edgeMargin: Bar.BarConfig.edgeMargin
    readonly property int cornerRadius: Bar.BarConfig.cornerRadius

    // The clear space between the plate's edge and the outermost widget. This
    // is padding, symmetric on both sides, so it cannot move the centre.
    property int contentPadding: 10

    Rectangle {
        id: plate

        anchors.fill: parent
        radius: surface.cornerRadius
        color: UI.Colors.background
    }

    // ---- the three zones ----------------------------------------------------
    //
    // A plain Item, not a layout. See the header: the whole point is that each
    // zone's position is decided by the container and by nothing else.

    Item {
        id: lanes

        anchors.fill: parent
        anchors.leftMargin: surface.contentPadding
        anchors.rightMargin: surface.contentPadding

        Bar.BarZone {
            id: leftZone
            zoneName: "left"
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
        }

        Bar.BarZone {
            id: centerZone
            zoneName: "center"
            // Against the container. No reference to leftZone or rightZone
            // appears here, and none may: a centre positioned relative to a
            // neighbour is exactly what this ticket exists to replace.
            anchors.centerIn: parent
        }

        Bar.BarZone {
            id: rightZone
            zoneName: "right"
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
        }
    }

    // ---- reporting ----------------------------------------------------------
    //
    // The bar reports its own geometry, and the verifier reads those numbers.
    // The alternative — asserting on a screenshot or on nothing — would not be
    // a check at all: Quickshell has no unit test runner, so every claim here
    // has to be falsifiable from a log line.
    //
    // Three lines, because three separate promises: what the surface LOOKS
    // like, where each zone ended up, and what each zone is holding.

    function descriptor(): string {
        return "surface=" + surface.surfaceId
            + " floating=" + surface.floating
            + " margin=" + surface.edgeMargin
            + " radius=" + surface.cornerRadius
            + " fill=" + String(plate.color)
            + " width=" + surface.width
            + " height=" + surface.height
    }

    // Positions are reported RELATIVE TO THE SURFACE, not to the container the
    // zones actually live in. The container is inset by contentPadding, so a
    // lane-relative number would be a smaller, less meaningful one: the claim
    // being checked is "the centre is at (barWidth - centreWidth) / 2", which
    // is a statement about the bar the user can see, and the padding is
    // symmetric so it cancels out exactly.
    function geometry(): string {
        return "surface=" + surface.surfaceId
            + " width=" + surface.width
            + " pad=" + surface.contentPadding
            + " left.x=" + (leftZone.x + lanes.x) + " left.w=" + leftZone.width
            + " center.x=" + (centerZone.x + lanes.x) + " center.w=" + centerZone.width
            + " right.x=" + (rightZone.x + lanes.x) + " right.w=" + rightZone.width
    }

    function population(): string {
        return "surface=" + surface.surfaceId
            + " left=" + leftZone.builtCount
            + " center=" + centerZone.builtCount
            + " right=" + rightZone.builtCount
    }

    // Logged once per distinct state rather than once per change: the geometry
    // settles in more than one pass (a zone's implicit width arrives after its
    // anchors are first resolved), and a log that reported the half-polished
    // numbers would be worse than no log at all.
    //
    // Three separate properties rather than an indexed collection: writing into
    // a `var` array property's indices from QML is not a plain JS array write
    // and throws on read-back, which would take the whole report down.
    property string _loggedSurface: ""
    property string _loggedLayout: ""
    property string _loggedZones: ""

    function report(): void {
        surface._say(0, "nosarch-shell ▸ BAR surface " + surface.descriptor())
        surface._say(1, "nosarch-shell ▸ BAR layout " + surface.geometry())
        surface._say(2, "nosarch-shell ▸ BAR zones " + surface.population())
    }

    // One of the three report lines, logged only when it has changed.
    function _say(which: int, line: string): void {
        const previous = which === 0 ? surface._loggedSurface
            : (which === 1 ? surface._loggedLayout : surface._loggedZones)
        if (previous === line) {
            return
        }
        if (which === 0) {
            surface._loggedSurface = line
        } else if (which === 1) {
            surface._loggedLayout = line
        } else {
            surface._loggedZones = line
        }
        console.info(line)
    }

    // Every input the report depends on, in ONE binding, so that a change in
    // any of them re-evaluates it. Declaring the dependency list here rather
    // than as a change handler per zone keeps the two from drifting apart — a
    // new field added to the report and forgotten in the handler would report
    // a stale line.
    readonly property string reportKey: surface.floating
        + "|" + surface.width + "|" + surface.height
        + "|" + surface.edgeMargin + "|" + surface.cornerRadius
        + "|" + leftZone.x + "|" + leftZone.width
        + "|" + centerZone.x + "|" + centerZone.width
        + "|" + rightZone.x + "|" + rightZone.width
        + "|" + leftZone.builtCount + "|" + centerZone.builtCount
        + "|" + rightZone.builtCount

    onReportKeyChanged: surface.report()

    Component.onCompleted: surface.report()
}
