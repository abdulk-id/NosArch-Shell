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

## Multi-monitor behaviour is structured for, unverified

**Status:** open. Recorded by ticket 10, against spec story 18 and 19 and the
spec's "Known gap" note.

### What is unverified

Everything that only happens with **more than one monitor attached**:

- a second bar surface appearing when an output is attached;
- that surface disappearing when the output is removed;
- every monitor showing the same layout;
- a panel on one monitor leaving a panel on another monitor alone;
- the cross-monitor dismissal twin, which ticket 11 has not built.

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