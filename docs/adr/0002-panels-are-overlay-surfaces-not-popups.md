# Panels are layer-shell overlay surfaces, not framework popups

Status: accepted. The decision is settled and **implemented** (ticket 11). The
pre-rewrite popup-based panels were deleted with the old bar in ticket 18; the
tree carries no `PopupWindow` panels any more.

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
- **The pre-rewrite popups are gone.** Ticket 18 deleted `components/TopIslandModule.qml`
  and `shell/topisland/` wholesale once every widget lived on the contract.
  `shell/panels/` and `shell/widgets/` carry none of it: no `PopupWindow`, no
  `grabFocus`, and no `makeChildrenUnfocusable` walk, which `scripts/verify-panels.sh`
  fails on.

## What was built, and what measurement changed

Three things in the design above turned out to matter for reasons the prose did
not anticipate, and each was measured on this machine rather than reasoned about:

- **`ExclusionMode.Ignore` is required, not tidy.** A full-screen panel window
  with the default `Auto` exclusion came back from Hyprland at
  `0 85 1920 995` — the compositor reserved the *bar's* exclusive zone and the
  panel did not cover the screen it was supposed to dismiss clicks on.
- **The prime does not tear the surface down.** Switching `keyboardFocus` from
  `Exclusive` to `OnDemand` left the layer-surface id identical
  (`55b1e0ac2d70` either side of the switch), confirming the plain-bindable-
  property claim above on this compositor.
- **A `PanelWindow` declared inside another `PanelWindow`'s data still maps as
  its own independent layer surface**, which is what lets the panel surface live
  in the same object scope as the bar window whose widgets it places itself
  under — no registry, no screen name, no lookup that could answer wrongly.

The one thing measurement could **not** cover is a physical mouse: this machine
has no pointer-injection tool, so every promise needing a click — a click opening
a panel, a click on the bar strip not dismissing, a click on another monitor
dismissing, a hand-held drag of the volume slider — is recorded in
`docs/known-gaps.md` rather than claimed. `scripts/verify-panels.sh` injects a
real **keystroke** through the compositor, so the keyboard half of the focus
model is genuinely verified; the pointer half is not.
