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
//   Hot-plug behaviour (a monitor arriving or leaving) is ticket 10's to
//   verify; this only follows the pattern the pre-rewrite bar established, so
//   the two tickets do not have to be reconciled afterwards.
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

Scope {
    id: bar

    property int barHeight: 35

    // Empty until the reader has a verdict — see the header.
    readonly property var screens: Bar.BarConfig.configured ? Quickshell.screens : []

    Variants {
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
}
