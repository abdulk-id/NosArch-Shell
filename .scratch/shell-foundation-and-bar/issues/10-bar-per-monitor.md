# 10: Bar on every monitor, surviving monitor add/remove

**What to build:** My bar appears on every attached monitor, and appears or disappears as I plug monitors in and out at runtime, without restarting the shell. Every monitor gets the same layout — per-monitor differing layouts are out of scope.

This also fixes a class of bug that is currently invisible and wrong the moment a second monitor is attached: popup state is managed by a single global object keyed on monitor-name strings, and the network widget and the volume widget call it with different argument counts, so the network panel ignores which monitor it was opened on entirely.

**Known gap, recorded rather than closed:** only one monitor is attached, so multi-monitor correctness is structured for but unverified. The behaviour under a second monitor is not tested, and this ticket does not claim otherwise.

**Blocked by:** 08 (three zones, true centre, floating or full-width bar).

**Status:** resolved

- [ ] The bar appears on every attached monitor.
- [ ] Adding or removing a monitor at runtime makes the bar appear or disappear without restarting the shell.
- [ ] Every monitor shows the same layout; per-monitor differing layouts are not attempted.
- [ ] The different-arity popup-state calls that let the network panel ignore its monitor are gone, replaced by a mechanism whose monitor handling cannot disagree between widgets.
- [ ] The multi-monitor known gap is recorded where a future reader will find it, so unverified is not mistaken for overlooked.
Implemented on branch `10-bar-per-monitor`, merged to `feat/shell-foundation-and-bar`.

**Most of `Bar.qml` was already correct and is unchanged**: `Variants` over `Quickshell.screens` with `model:` (not the v0.3.0 docs' `variants:` typo), `required property var modelData` on a real instance rather than inside `delegate: Component {}`, `screen: modelData` so each window follows its own entry, and layer + namespace on each per-screen `PanelWindow`.

Added: a **static guard against a snapshot model** (`.slice`, spread, `Array.from`, `Object.keys` — each yields a bar indistinguishable from a correct one on a single monitor and never follows a hot-plug, and no single-monitor run could ever tell); connection to `Quickshell.screensChanged`; and a report line per change carrying the framework's attached count, the bar's own live-window count from `Variants.instances`, and each window's name/geometry/namespace read off the screen it is *actually* bound to.

**Two defects found by running rather than reading:** a child's `id` is not a property of its parent, so `bar.windows` is `undefined` while a bare `windows` resolves — this caused a `TypeError` naming `Bar.qml` on every run; and the report's `reason` was racy between two handlers both firing before the coalescing timer.

**The arity criterion was (c), not "already satisfied".** Confirmed exactly as suspected: `popupStateManager` in `TopIsland.qml` held `activePopup`/`activeScreen`; `TopIslandModule.qml` called `set(id, screen)`/`isActive(id, screen)` while `NetworkModule.qml` called `set(popupId)`/`isActive(popupId)`; and `isActive` treated a missing screen as "any screen", so on a second monitor the network panel would have appeared on the monitor it was **not** opened from.

But declaring it done would have been wrong. Ticket 08 took `TopIsland` out of `shell.qml`, so no *user* could hit it — yet the mechanism was fully intact in files `smoke.qml` compiles on every run, one line from being live again, and `popupStateStub` declared a **uniform** two-argument `set`/`isActive`, so no check in the suite could ever have noticed the split.

Replaced with `components/PopupState.qml`: one instance per surface, API `toggle(id)` / `isActive(id)` / `close()`, and **no screen anywhere**. Deliberately *not* a required-and-checked argument — that is the same fragility one space over, because the monitor would still be a per-widget string each widget has to get right. "Which monitor" is answered by which `PopupState` instance a widget holds, and there is no name to name wrongly. The widget property is **typed** (`property Components.PopupState popupState`) so a holder of anything else fails to construct rather than answering questions about screens. This is the state half only; ticket 11 owns panels as overlay surfaces.

**Known gap, recorded rather than papered over.** Only ONE monitor is attached to this machine, so nothing here exercised a second output. Verified: the model is the live attached-screen list (statically, against a named list of forbidden snapshot forms), each window follows its own screen, the shell is connected to `screensChanged`, the surface count equals the attached-screen count, and each surface measures against its own screen's width less the insets (1904px = 1920 − 2×8, at eDP-1/1920x1080+0+0). **Not verified: a bar actually appearing and disappearing as an output is attached and detached**, which would need reconfiguring the live desktop's monitors and was therefore not attempted.

The gap lives in `docs/known-gaps.md` (full entry), three `AGENTS.md` bullets, and — deliberately — the verifier's last case, which **prints the gap on every run and fails if it cannot determine the screen count**. A check that quietly succeeds because only one monitor exists is worse than no check.

**Namespace semantics, recorded:** a namespace names the surface's *role*, not its instance. Every monitor's bar publishes the same `nosarch-shell-bar` because they are all "the bar"; what must not repeat is one namespace across two different *roles*. `verify-bar-per-monitor.sh` collects every namespace in the tree and fails if one is claimed by two.

**Mutation-testing note:** a 1px-wrong screen initially PASSED, because the tolerance was 1.0px. Now 0.5px, and it fails.

**Shared-script change, flagged for the record:** `verify-launch-reload.sh`'s static check counted *reads* of `WlrLayershell.namespace` as sets, and failed on `Bar.qml` reading each window's namespace back to report it. Now counts assignments only. This is a deliberate loosening, justified because a read is not a set — but it is the kind of change that can mask a real regression, so it is recorded here rather than left silent.

**A cross-ticket observation, not a defect in this ticket:** `verify-bar-surface.sh` failed once on `BluetoothService.qml: Unable to assign [undefined] to BluetoothAdapter*` — a Bluetooth hardware transient under contention with the other tickets' concurrently running shells. Green 3/3 subsequently and 5/5 on a pristine baseline worktree.

Live desktop untouched: waybar 1333, hyprpaper 1335, swayosd 1347, swaync 1487 unchanged, no stray processes, no leftover scratch dirs, `~/.config/quickshell` still absent, no `palette.json` written to the live theme dir.

