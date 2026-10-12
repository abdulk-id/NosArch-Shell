# Panels are layer-shell overlay surfaces, not framework popups

Status: accepted. The decision is settled; nothing is implemented yet.

A panel is a full-screen `PanelWindow` on the overlay layer with the card drawn
inside it, not a Quickshell `PopupWindow`. Framework popups were abandoned
deliberately: an interactive popup does not take keyboard focus until it is
clicked or hovered, which makes a panel that should be summonable with a keybind
and typed into immediately impossible. Nothing about the popup approach is
accidental, and nothing about it is a limitation to be removed later.

## Why popups were abandoned

**Keyboard focus at open time.** `PopupWindow` does not receive keyboard focus
until the user clicks or hovers it. A panel summoned by a keybind would open,
sit there, and swallow every keypress. This is the whole reason.

**Focus grabbing is not used, and its workaround is deleted, not ported.** The
old popup base set `grabFocus: true`, which dismisses the popup on an outside
click — so using a control *inside* the popup also moved focus, and dragging the
volume slider closed the panel under the pointer. The fix was a recursive walk
over the popup's entire item tree clearing `focus` and `activeFocusOnTab` on
every descendant, so the grab would never fire. That workaround is deleted rather
than ported: it disabled precisely the in-panel keyboard focus the panel
architecture exists to provide, and it did it by disabling focus everywhere.

**The exclusive-focus prime.** `WlrLayershell.keyboardFocus` is a plain bindable
property that can be changed while the surface stays mapped — verified on
Quickshell 0.3.2, the layer-surface id is identical before and after the switch.
A panel requests `WlrKeyboardFocus.Exclusive` on open and drops to `OnDemand`
after a moment. Exclusive alone would make the compositor route every pointer
event on every output to the panel and break clicks on other monitors; the prime
is what buys keyboard input at open time without that side effect. Layer-shell
focus alone still does not give an in-surface item active focus for key handlers
to fire, so the panel also names an explicit focus target inside itself and
focuses it once the surface has mapped.

**One panel at a time is intrinsic, not a product choice.** Two full-screen
overlay surfaces would compete for input. Everything else in the design follows
from the same decision: a bar-level coordinator tracking the open panel, so
clicking a different widget switches panels in one click; a dismissal surface
covering the screen whose region mask excludes the bar strip, so bar widgets stay
clickable while a panel is open; a transparent dismissal twin on every other
output, because pointer input is hit-tested per output and the main surface
cannot see clicks elsewhere; and focus and click ownership bound to the panel's
*logical* open state rather than its visibility, so ownership is released the
moment it logically closes instead of after the close animation.

## The Hyprland-only trade

The focus model depends on compositor behaviour that was confirmed under
Hyprland and nowhere else — layer-shell exclusive focus specifically. Porting to
another compositor would require a **different panel base**, not a different
panel. The shell is Hyprland-only today and this is a deliberate trade, not an
oversight: the focus guarantees are worth more than compositor reach, because the
panels are the part users interact with most.

## Considered and not chosen

Two independent community shells converged on this same full-screen-overlay
approach; one of them additionally models panel state as independent per-panel
flags rather than through a single coordinator. This shell follows the
coordinator shape. The two shapes were not compared on their merits — the
coordinator was chosen because it makes the one-panel-at-a-time rule structural
rather than something each widget has to respect.

## Consequences

- The project instruction that every overlay surface sets both a layer and a
  distinct namespace is load-bearing, not style: cross-monitor dismissal tells
  the per-monitor surfaces and the other outputs' twins apart by namespace.
- Panel positioning is top-bar only. Left, right and bottom bar positions are
  not implemented; adding one is a contained change.
- The panel architecture is not yet implemented. There are two popup-based
  panels in the tree today, not one: `components/TopIslandModule.qml` declares a
  `PopupWindow` with `grabFocus: true` and the recursive `makeChildrenUnfocusable`
  walk, and `shell/topisland/modules/NetworkModule.qml` declares a second
  `PopupWindow` of its own. They also disagree about the shared popup state —
  `NetworkModule` calls `popupState.set(id)` with one argument while
  `TopIslandModule` calls `popupState.set(id, screen)` with two, so the network
  panel records no monitor and cannot be dismissed per output. Both go when the
  panel architecture lands, and `scripts/verify-docs.sh` fails if this record
  claims otherwise.
