# Known gaps

Things this shell is **structured for but has not verified**, and which a reader
must not mistake for verified. Each entry says what is unverified, why it is
unverified rather than untried, what *is* checked in its place, and what would
close it.

A gap here is not a failing check. Every gap below has a check that holds
today; what the gap says is that the check covers a smaller claim than a reader
might assume from its name. `scripts/verify-bar-per-monitor.sh` prints the
relevant one on every run rather than leaving it only here.

---

## Panel input behaviour is verified where it can be, and no further

**Status:** open. Recorded by ticket 11, against spec stories 42 and 53–66 and
the spec's "Not tested: pixel geometry" note.

Panel architecture is the part of this shell with the most user-facing promises
and the least that can be asserted headlessly. The framework has no unit test
runner, nothing can assert pixel geometry, and **this machine has no
pointer-injection tool** — `wtype` is keyboard-only and Hyprland 0.56 has no
click dispatcher — so every promise that needs a physical mouse cannot be
exercised by any script. That is not a reason to skip the work; it is the reason
the work stopped where it would start needing a hand on the mouse.

### What IS verified, and by what

`scripts/verify-panels.sh`, which prints the following list on every run so a
green one cannot be read as covering more than it did.

- **Architecture shape, statically.** Panels are layer-shell surfaces with the
  card inside rather than `PopupWindow`s; every surface sets a layer and its own
  namespace; the dismissal mask is a `Region` with `Intersection.Xor`; the
  exclusive-focus prime exists and drops to on-demand; the focus target is a real
  in-surface item; a twin exists per other output; ownership is bound to the
  logical open state rather than to `visible`.
- **Coordinator behaviour, on live instances** (`smoke.qml`): one panel at a
  time; switching panels in one call; ownership released on the logical close;
  re-opening after a close; `toggle` being both directions; an empty id closing
  rather than opening nothing.
- **In-panel keyboard focus, headlessly**: active focus really arrives on an item
  inside the card, and the content's own `focusTarget` is preferred over the card.
- **The real surface, live**: it maps full-screen (`1920x1080`, measured), under
  its own namespace, with a region mask present; it was seen holding
  **exclusive** focus at open and **on-demand** afterwards; an in-surface item
  really takes active focus in a real window.
- **A real Escape keystroke**, injected with `wtype` through the compositor into
  whatever surface holds keyboard focus — which walks the entire path (prime →
  surface focus → in-surface item focus → `Keys` handler → coordinator close)
  and closes the panel.
- **Containment**: the card's reported rect lies wholly inside the framework's
  own screen size, and below the bar strip. This is the **only** geometry
  assertion in the script.
- **The presentation boundary**: `AudioService` declares no glyph property, the
  icon decision and the muted colour both exist outside it, and the glyph differs
  for headphones, handsets and speakers at one fixed volume, differs again by
  volume band, and is distinct when muted.

### What is NOT verified

| Promise | Why not, and what would close it |
| --- | --- |
| A panel appears **under the widget that was clicked** | Pixel geometry; the spec calls it a manual visual check. Only containment is asserted. Closes by a person looking at the screen. |
| A **physical click** on a widget opens its panel | No pointer-injection tool exists here. The widget's activation *action* is driven instead (`NOSARCH_PANEL_DRIVER`, which calls the same `activate(widget)` a `MouseArea` calls), so everything from the click onwards is exercised; Qt's own hit-testing is not. Closes with a pointer-injection tool, or a person. |
| The mask really lets a click **through** on the bar strip | Its shape is checked statically and its presence at run time; no run clicks through it. Closes with pointer injection. |
| A click on **another monitor** dismisses the panel, and the twin exists | One monitor is attached, so the twin list is empty on every run and no twin is ever instantiated. Part of the multi-monitor gap below. |
| A hand-held **drag of the volume slider** | That no `grabFocus` exists, that the slider is the focus target, and that the panel's state cannot be disturbed by a pointer are all checked; the physical gesture is not. Closes with pointer injection — and is worth doing, since it is the interaction the popup architecture could not support. |
| The slider **changes the machine's volume** | Deliberately not driven: it would move the user's audio. Closes with a person, or with a fake sink. |
| The twins are really **instantiated** per other output | Structurally checked; never instantiated for want of a second screen. |
| The mask's cut-out is **exactly the bar strip in pixels** | The region is built from an item bound to the bar's own geometry, but no run measures where the compositor put the bar. |
| **Left, right and bottom** bar positions | Not implemented. Top-bar-only is SCOPE, recorded in ADR 0002, not a defect. |

### A note on what was measured along the way

Two facts about the compositor were measured rather than assumed, and both are
load-bearing for the implementation:

- A full-screen panel window with the **default** exclusion mode came back from
  Hyprland at `0 85 1920 995`, not `0 0 1920 1080` — the compositor reserved the
  bar's exclusive zone. `ExclusionMode.Ignore` is required, not tidy.
- Switching `keyboardFocus` from `Exclusive` to `OnDemand` leaves the
  **layer-surface id identical** (`55b1e0ac2d70` either side), so the prime is a
  live reconfiguration and the surface is not torn down and remapped.

---

## Multi-monitor behaviour is structured for, unverified

**Status:** open. Recorded by ticket 10, against spec story 18 and 19 and the
spec's "Known gap" note.

### What is unverified

Everything that only happens with **more than one monitor attached**:

- a second bar surface appearing when an output is attached;
- that surface disappearing when the output is removed;
- every monitor showing the same layout;
- a panel on one monitor leaving a panel on another monitor alone;
- the cross-monitor dismissal twin — **built** by ticket 11
  (`shell/panels/PanelSurface.qml`, one transparent surface per other output
  under its own `nosarch-shell-panel-dismiss` namespace), and still never
  instantiated, because with one output attached the twin list is empty on every
  run. Its existence is checked statically; nothing else about it is checked at
  all.

### Why it is unverified

**Only one monitor is attached to the machine this was developed on** (`eDP-1`,
1920x1080). Exercising it would mean reconfiguring the live desktop's outputs
— `hyprctl keyword monitor`, or a wlr-output configuration change — which would
disturb the running session. That is not a reason to skip the work; it is the
reason the work stopped at the point where it would start disturbing things.

There is also no way to fake it from inside the shell: `Quickshell.screens` is
the framework's own list of real outputs, and nothing can add an entry to it.

### What *is* checked, and by what

`scripts/verify-bar-per-monitor.sh`, in four parts:

1. **The model is the live list, not a snapshot of it** (static). The bar's
   `Variants` model is bound to `Quickshell.screens`. The forbidden forms are
   named explicitly — `.slice()`, a spread, `Array.from`, `Object.keys` —
   because each produces a bar that looks completely correct on a one-monitor
   machine and never follows a hot-plug. This is the claim most worth checking
   statically precisely because no single-monitor run could ever detect it.
2. **Each window follows its own screen** (static, and again at run time). The
   delegate binds `screen: modelData`, and at run time each live window reports
   the name and geometry of the screen it is actually bound to.
3. **The shell is connected to the signal hot-plug arrives on** (static). The
   bar handles `Quickshell.screensChanged`; the model does the creating, the
   handler makes the shell re-report rather than leaving its first line as the
   only record.
4. **Surface count tracks screen count** (run time, one monitor). The shell
   reports `attached` (from the framework) beside `windows` (from its own
   `Variants` instances) and the verifier requires them equal, each surface
   paired against *its* screen's width less the floating insets.

Point 4 is a real invariant and not a tautology — a `Variants` model that was
bound to something stale, or a delegate that failed to construct, would break
it — but it is checked with one element, and one element cannot fail the way
two can.

Additionally, the **pre-rewrite widgets are already instantiated once per
screen** by `smoke.qml`, over its own `Variants` on `Quickshell.screens`. So a
widget that breaks only on a second monitor has somewhere to fail — it just has
not, because there has never been a second monitor.

### The popup-state arity split

The latent bug this gap refers to — popup state keyed on monitor-name strings,
with `isActive(id, screen)` silently answering "active on any screen" to a
caller that omitted the screen, and the network widget being that caller — is
**fixed**, not merely recorded. See `components/PopupState.qml` and the
"Popup state is per-surface, and carries no monitor" convention in `AGENTS.md`.
The general class of bug it belonged to is still unverified, because only one
monitor has ever exercised it.

### What would close it

Running `scripts/verify-bar-per-monitor.sh` on a machine with two monitors
attached, and seeing case (C) report `attached=2 windows=2` with two distinct
screen names and two paired surfaces. The script needs no change: it asserts
the invariant for whatever count it finds, and case (D) says explicitly when it
did and did not see more than one.

Adding a second monitor is not enough on its own. Attaching one and detaching
it while the shell keeps running is what exercises hot-plug; a machine that
boots with two monitors only ever exercises the startup path.