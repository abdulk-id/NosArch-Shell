import Quickshell
import Quickshell.Wayland
import QtQuick

import "." as Bar

// Bar — one window per screen, each holding a BarSurface (ticket 08).
//
// WHAT THIS IS, AND WHY IT IS NOT THE BAR
//
//   The window and nothing else: one PanelWindow per attached screen, the
//   layer-shell settings that make it a bar rather than an arbitrary surface,
//   and one BarSurface inside it. The zones, the centring and the
//   floating/full-width geometry all belong to BarSurface, which is a plain
//   Item — so the layout can be built, measured and verified without a window
//   anywhere near it, which is what lets the smoke shell stay surface-free.
//
// WHY THE WINDOWS ARE NOT CREATED UNTIL THE CONFIGURATION IS READ
//
//   This is the one thing here that is not obvious, and it was found by
//   measuring the real bar rather than by reading it.
//
//   A layer-shell surface has its size negotiated ONCE, when it maps. Referencing
//   the reader settles its verdict a moment later than it is first touched (the
//   file load completes on a later pass of Quickshell's instantiation, however
//   blockLoading is arranged), so a bar created immediately would map with the
//   BUILT-IN DEFAULTS and correct itself afterwards — and the compositor does
//   not hand a mapped surface a second size. With `floating` set to false in
//   the user's file, that produced a bar 16px narrower than the screen for as
//   long as the shell ran: a toggle that silently did nothing.
//
//   So the windows wait for `configured`, which is true once the reader has
//   reached a verdict by any route — file, no file, unreadable, malformed. The
//   failure policy is untouched: waiting on a verdict is not failing on one, and
//   every path that can set a verdict does.
//
//   The upside beyond the width: the bar appears already holding what the user
//   configured, rather than appearing empty and filling in a frame later.
//
// PER SCREEN, AND HOW
//
//   Variants over Quickshell.screens, the framework's own idiom (verified on
//   0.3.2 — quickshell-api-notes.md §5). The property is `model:`; the
//   v0.3.0 documentation's `variants:` is a typo that fails to compile, and it
//   is the first thing anyone copying that page will hit.
//
//   The delegate's `required property var modelData` goes on a real type, not
//   on the Component — `delegate: Component { required property … }` is
//   rejected outright ("Component objects cannot declare new properties").
//
// THE MODEL IS THE LIVE LIST, NEVER A SNAPSHOT OF IT
//
//   `screens` below is a `readonly property var` bound straight to
//   Quickshell.screens, gated only on the reader having reached a verdict. The
//   one thing it must never be is a copy: `Quickshell.screens.slice()`, a
//   spread, `Array.from` or `Object.keys` would produce exactly the same bar on
//   every machine and on every hot-plug, because the copy is taken once and
//   never follows an output arriving. Nothing at run time can tell the
//   difference with one monitor attached — which is precisely why
//   scripts/verify-bar-per-monitor.sh forbids those forms statically rather
//   than looking for the symptom in the log.
//
//   That the `var` hop itself does not swallow the change notification was
//   measured rather than assumed: a binding through `readonly property var`
//   over a list, watched by a Variants model, does create and destroy delegates
//   as the underlying list grows and shrinks.
//
// HOT-PLUG: WHAT IS BUILT, AND WHAT IS NOT VERIFIED (ticket 10)
//
//   Built: the model follows the attached-screen list, so a monitor arriving
//   adds an entry and a monitor leaving removes one, and the report below says
//   so from the framework's own count rather than from a hardcoded number.
//   The bar is also connected to screensChanged — the exact signal a hot-plug
//   arrives on — so the shell notices and re-reports rather than sitting on a
//   stale line.
//
//   NOT verified, and recorded as a known gap rather than papered over: only
//   ONE monitor is attached to the development machine, so nothing has ever
//   run with a second output. Attaching one means reconfiguring the live
//   desktop, which the work that would do it is forbidden to do. The verifier
//   therefore checks the leading half (live model, live signal, surface count
//   tracks screen count) and PRINTS that the trailing half — a bar actually
//   appearing and disappearing as an output is attached and detached — was not
//   exercised. It refuses to pass if it cannot determine how many screens it
//   saw. See AGENTS.md ("Multi-monitor is structured for, unverified") and
//   docs/known-gaps.md.
//
// THE LAYER-SHELL CONVENTION
//
//   Layer AND namespace, both, always. Under the panel architecture this is
//   load-bearing rather than decorative: panel surfaces, per-monitor surfaces
//   and the cross-monitor dismissal twins all have to be tellable apart, and a
//   surface with no namespace cannot be told from anything. The namespace is
//   distinct from the pre-rewrite bar's, so the two can coexist during the
//   cutover window — which is the whole point of running the new shell
//   alongside waybar.
//
//   Every monitor publishes the SAME namespace on purpose. The namespace names
//   the surface's ROLE, not its instance: one "the bar" role, present once per
//   monitor. What ticket 11 adds — panels, and a transparent dismissal twin on
//   every other output — must take namespaces of its own, which is what lets
//   the three be told apart at runtime. verify-bar-per-monitor.sh collects
//   every namespace in the tree and fails if one is claimed by two roles.

Scope {
    id: bar

    property int barHeight: 35

    // Empty until the reader has a verdict — see the header. A binding, never
    // a copy: see "THE MODEL IS THE LIVE LIST".
    readonly property var screens: Bar.BarConfig.configured ? Quickshell.screens : []

    // ---- the windows --------------------------------------------------------
    //
    // Declared BEFORE the reporting below, and that ordering is load-bearing
    // rather than cosmetic — but the reason is not the usual one.
    //
    // A child's ID is not a property of its parent: `bar.windows` is undefined
    // even though the bare name `windows` resolves fine, because an id is
    // visible lexically inside its component and is not installed as a
    // property on the component root. So the report below reads the bare
    // `windows`, and the object has to exist by the time those bindings are
    // first evaluated. Declared after them, the first evaluation would read
    // undefined and — having no notifyable property to change — would never be
    // re-evaluated. That was observed, as a TypeError naming this file on
    // every run, and is the only reason the block sits here rather than at the
    // bottom.

    Variants {
        id: windows
        model: bar.screens

        delegate: Component {
            PanelWindow {
                id: barWindow

                required property var modelData
                screen: modelData

                focusable: false
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "nosarch-shell-bar"

                anchors {
                    top: true
                    left: true
                    right: true
                }

                implicitHeight: bar.barHeight

                // The floating inset. Read from the reader rather than from the
                // surface inside, because a window's margins are settled when
                // it is created and a binding into a child that does not exist
                // yet would be read as no margin at all. The transparent gap
                // beside a floating bar must not be clickable, so it is taken
                // out of the WINDOW's area rather than merely painted around.
                margins {
                    top: Bar.BarConfig.edgeMargin
                    left: Bar.BarConfig.edgeMargin
                    right: Bar.BarConfig.edgeMargin
                }

                // The window is only the container; the plate inside it is what
                // is drawn, and in floating mode the corners must show the
                // desktop through them.
                color: "transparent"

                Bar.BarSurface {
                    anchors.fill: parent
                    surfaceId: barWindow.modelData.name
                }
            }
        }
    }

    // ---- reporting ----------------------------------------------------------
    //
    // One line, and every part of it is read from something real: `attached`
    // from Quickshell.screens, `windows` from this bar's own Variants
    // instances, and each entry from the screen the corresponding window is
    // actually bound to. The verifier reads these to assert one bar per
    // monitor, and to pair each surface with ITS screen.
    //
    // The windows settle a pass or two after the screen set does (a delegate is
    // created, then given its screen), so the report is coalesced on a short
    // timer rather than printed on the first change — otherwise the log would
    // carry a half-built bar as its last word, which is what the previous
    // "wait for a non-zero width" rule in the verifier is a workaround for.

    property string _reason: "startup"
    property string _reported: ""

    function scheduleReport(why: string): void {
        bar._reason = why;
        settle.restart();
    }

    Timer {
        id: settle
        interval: 150
        repeat: false
        onTriggered: bar.reportWindows()
    }

    function describeLiveWindows(): string {
        // The bare id, NOT `bar.windows` — see the note above the Variants.
        const live = windows.instances;
        const parts = [];
        for (let i = 0; i < live.length; i++) {
            const w = live[i];
            const s = w.screen;
            // A window whose screen is null is a real defect, so it is
            // reported as such rather than skipped: a "?/..." entry here is
            // what makes the verifier's pairing check fail loudly.
            if (s === undefined || s === null) {
                parts.push("UNBOUND/-/-/-/-@no-namespace");
                continue;
            }
            parts.push(s.name + "/" + s.width + "x" + s.height + "+" + s.x + "+" + s.y
                + "@" + (w.WlrLayershell === null ? "no-namespace" : w.WlrLayershell.namespace));
        }
        return parts.join(",");
    }

    function reportWindows(): void {
        const attached = Quickshell.screens.length;
        const alive = windows.instances.length;
        const names = bar.describeLiveWindows();
        const line = "nosarch-shell ▸ BAR screens attached=" + attached
            + " windows=" + alive
            + " agree=" + (attached === alive ? "yes" : "NO")
            + " reason=" + bar._reason
            + " names=" + names;
        if (line === bar._reported) {
            return;
        }
        bar._reported = line;
        console.info(line);
    }

    // Re-report whenever the screen set or the live window set moves. One
    // binding over both inputs rather than a handler per property, so a new
    // input cannot be added to one and forgotten in the other.
    //
    // The reason is derived rather than passed in by each handler. Two handlers
    // both firing before the coalescing timer expires meant the last one to run
    // won, so the same startup could be logged as "hotplug" depending on
    // evaluation order — a report that cannot be relied on to mean what it says
    // is worse than no reason at all. The first report is always "startup",
    // because nothing has been plugged in yet; after that any movement is a
    // change to the set of surfaces, which is what "changed" says.
    readonly property string windowKey: Quickshell.screens.length
        + "|" + windows.instances.length
        + "|" + bar.describeLiveWindows()

    onWindowKeyChanged: bar.scheduleReport(bar._reported === "" ? "startup" : "changed")

    // The signal itself, so a monitor arriving is reported as the hot-plug it
    // is rather than as anonymous movement. It does not create the windows —
    // the model does that; see the note above.
    Connections {
        target: Quickshell
        function onScreensChanged(): void { bar.scheduleReport("hotplug") }
    }
}
