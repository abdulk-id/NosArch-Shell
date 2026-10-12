# 06: Widget contract, widget registry, and the clock widget

**What to build:** Every bar widget satisfies one uniform contract by extending a single base class, declaring the same required interface: content for the bar, a click action, a tooltip, and optionally panel content. A widget that offers a panel supplies it; a widget that does not, does not pretend to with an empty one. A simplified base for trivial label-plus-click widgets exists so simple widgets are not forced to declare absent capabilities. A widget name in configuration resolves through a map from name to file held in the shell code — there is no runtime plugin registry, and configuration never carries file paths, because a user-owned config file that named arbitrary code locations would be a code-execution surface. The clock is the first widget on the contract, and every widget dims when hovered and brightens, so I can tell which ones are interactive. Adding a widget now means writing one file and adding one entry.

**Blocked by:** 03 (smoke-test entrypoint), 04 (theme-driven palette and fonts).

**Status:** resolved

- [ ] One base class declares a uniform required interface: bar content, click action, tooltip, and optional panel content.
- [ ] A widget offering a panel supplies panel content; a widget offering none supplies nothing rather than an empty one.
- [ ] A simplified base exists for trivial label-plus-click widgets so they are not forced to declare absent capabilities.
- [ ] A widget name resolves through a map from name to file held in the shell code; configuration never carries a file path.
- [ ] Widgets live in a single predictable directory, and adding one means copying a file and adding one entry.
- [ ] The clock widget is migrated onto the contract, showing time and date and updating every minute so it never shows a stale time.
- [ ] Widgets dim when not hovered and brighten on hover, so interactive widgets are distinguishable.
- [ ] Hovering shows a tooltip where the widget has one.
- [ ] The base contract carries the hover affordance rather than each widget reimplementing it.
Implemented on branch `06-widget-contract-registry-and-clock`, merged to `feat/shell-foundation-and-bar`.

The contract, `shell/widgets/BarWidget.qml`, requires three members — `content` (a `Component` for the bar), `activate` (a `var` click action, called as `activate(widget)`) and `tooltip` (a `string`) — and exposes `panelContent` (`property Component`, default **null**) with a derived `hasPanel`.

**`required` is enforced by Qt, not by convention.** Qt refuses to construct an object missing a required member, so a widget that forgets one is a load error the smoke test catches — the abstraction cannot be silently unapplied, which is exactly how the old module base failed. Verified on the installed 0.3.2 that **a derived class may satisfy a base's `required` by assigning it in its own body**, which is precisely what makes the simplified base possible rather than a workaround.

Optionality is strong: the clock **declares nothing** for panel content, so `hasPanel` reads `false` from an absence rather than an empty value the shell had to learn to ignore. The verification script fails if any widget declares `panelContent` as `required` — the spec's "a widget that does not offer a panel does not pretend to" is therefore enforced, not merely intended.

`SimpleBarWidget.qml` extends `BarWidget` — on the contract, not beside it — and builds `content` and `tooltip` from a required `label`, so trivial widgets declare only `label` and `activate`.

Hover dim (0.55 → 1.0), brighten and tooltips live in the base; no widget re-implements a `MouseArea`.

**Location: `shell/widgets/`**, one predictable directory. `WidgetRegistry.qml` is a `pragma Singleton` holding a literal name→file map, with `names()`, `fileFor()`, `isKnown()`, `pathFor()`, `componentFor()`. Values are **file names, not paths**, resolved against the registry's own directory; an unknown name resolves to `null` so it can be skipped with a named log line. Adding a widget = copy a file + one map entry + one `qmldir` line.

**The old `ClockModule.qml` was left in place, deliberately.** A new file at a new path rather than an in-place migration, because the contract and widget directory are new while `ClockModule.qml` belongs to the directory ticket 18 deletes wholesale. Deleting it now would break two things the old bar still needs — `TopIsland.qml` instantiates it and the smoke plan plans it — neither of which is this ticket's to change. It stays covered until 18.

**Smoke-plan coordination (this was the live constraint).** `smoke.qml` gained a `contractWidgetPlan` with one entry per type, per screen, **supplying the required members** — which is what proves the interface is enforced rather than merely present. `WidgetRegistry` is planned as a singleton and constructed by *reference*, because `createObject()` on a `pragma Singleton` returns `null` and would have reported a false failure. `verify-smoke.sh`'s static check was extended to cover `shell/widgets/qmldir`, keeping its both-directions assertion (a file not in the plan fails; a plan entry with no file fails).

**Verification, mutation-tested.** `scripts/verify-widget-contract.sh` (executable, mode 100755) checks statically, then reads the contract's promises off **live instances** rather than comments. Five deliberate mutations each fail with a specific message: dropping `required` → "does not declare `required property ... content`"; a name pointing at a missing file → "not a file in shell/widgets/"; a registry value turned into a path → "the map resolves relative to its own directory, never from configuration"; the clock changed to `Seconds` → "expected Minutes, clock reports 'Seconds'"; the clock given an empty panel → "hasPanel=true panelContent=SUPPLIED". The clock's cadence is derived from the live `SystemClock.precision`, so a hardcoded "Minutes" string cannot pass regardless of behaviour.

Actual results on the merged branch: `verify-smoke.sh` PASS (planned=26, passed=26, failed=0), `verify-widget-contract.sh` PASS (all seven contract probes), `verify-launch-reload.sh` PASS (reload loop 148 ms). All six verifiers green.

**Merge coordination.** Ticket 05 ran in parallel and conflicted in AGENTS.md's Running section; resolved by union so all six verifiers are documented, with the count corrected five → six. Had it merged naively, `verify-docs.sh` check (F) would have failed on the undocumented script.

**Two API traps recorded, now added to `quickshell-api-notes.md`:** `Qt.TimeFormat` does not exist on 0.3.2 — it fails at *run* time with `Cannot read property 'ShortFormat' of undefined`, the same silent shape as the `WlrKeyboardFocus.Exact` trap; the correct spelling is `Locale.ShortFormat` from `import QtQml`. And a `qmldir` in a directory is what makes sibling imports resolve — without `shell/widgets/qmldir`, `SimpleBase is not a type`.

**For ticket 05 and the glossary.** "Module" is retired and the base types deliberately carry no `Module` suffix. Terms the code now commits to: widget, contract, registry, name. Note that **"registry" here means a literal map, not a runtime plugin registry** — the word implies the latter, so that distinction is worth stating explicitly. Type naming is `BarWidget` / `SimpleBarWidget` / `ClockWidget` / `WidgetRegistry`, config names lowercase kebab.

**For ticket 07/08:** `verify-launch-reload.sh` copies `shell/`, `services/` and `components/` into its scratch config but **not** the repo root, so it will need `shell/widgets/` included once the bar composes contract widgets.

Live desktop verified intact: waybar 1333, hyprpaper 1335, swayosd 1347, swaync 1487 unchanged; no stray `quickshell`/`dbus-daemon`; `~/.local/share/nosarch/` untouched; `.qmlls.ini` reverted and not committed; `smoke.qml` still at the repo root.

