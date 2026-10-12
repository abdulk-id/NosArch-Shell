# AGENTS.md

## What This Is

Quickshell desktop shell configuration (`nosarch-shell`) written in QML.

## File Layout

- `shell.qml`: Quickshell entrypoint. Imports and composes all shell components.
- `smoke.qml`: Smoke-test entrypoint. Instantiates every widget, service and shared component (once per screen) and reports each by name. It draws nothing — run it through `scripts/verify-smoke.sh`, never as a live shell. `Bar.qml` is the one planned type it only *loads* rather than instantiates, because it owns layer-shell surfaces; `BarSurface` (the layout, with no window) is instantiated and its geometry measured.
- `shell/`: Contains all the shell components to be used in the shell entrypoint.
- `shell/widgets/`: The widget extension point. Every bar widget lives here, extending `BarWidget` (or `SimpleBarWidget` for a trivial label-plus-click widget). Adding one means copying a file into this directory, adding one line to `WidgetRegistry.qml`'s `entries` map, and adding one line to `qmldir` — nothing else.
- `shell/bar/`: The bar's own directory. `BarConfig` (a singleton) reads the user's configuration file, validates it and applies the failure policy; `BarZone` builds one zone's widgets from what `BarConfig` answered and sizes itself to them; `BarSurface` is the bar itself — three zones on one plate, filled from the palette; `Bar` is one `PanelWindow` per attached screen, holding a `BarSurface`. `BarSurface` is a plain `Item` that owns no window, which is what lets the smoke test build and measure the whole layout without drawing a surface.
- `services/`: Contains singletons for `SystemInfo`, `NotificationService`, `Media` etc.; register via `services/qmldir`
- `components/`: Contains shared components (`Separator`, `ProgressOSDItem`, `PopupState`)
- `testing/`: Development readout panels, not verification. `ServiceReadout.qml` renders live service values by eye; it asserts nothing and no script runs it.

## Conventions

- Singletons use `pragma Singleton` and are registered in `qmldir` files (services and shell/ui)
- All UI uses `UI.Colors.*` and `UI.Fonts.*` from colors and fonts singletons in `shell/ui` — never hardcode colors or font properties
- The palette is file-backed: `UI.Colors` reads `~/.local/share/nosarch/current-theme/palette.json` (resolved from `HOME`, not `Quickshell.statePath()` — it is the NosArch theme directory, not a Quickshell state dir), falls back to the built-in defaults, writes them out on first run, and never overwrites an existing file. The file is a flat JSON object with one hex colour per key: `accent`, `alertRed`, `background`, `backgroundHover`, `backgroundSurface`, `foreground`, `foregroundMuted`, `foregroundSecondary`. Keys the file omits keep their defaults; a malformed file is left untouched and the defaults are used.
- Import singletons as `import "path" as UI` then reference `UI.Colors`, `UI.Fonts`
- **The bar's configuration is read from an absolute path outside the repository, never relative to the QML source.** `BarConfig` reads `$XDG_CONFIG_HOME/quickshell/nosarch/shell.json` (falling back to `~/.config/…`), overridable in full by `NOSARCH_SHELL_CONFIG`. It is user-owned and untracked because the NosArch installer deploys it. Resolving it relatively — to the shell's own directory, to the QML file, via `Qt.resolvedUrl` — would work during development and break silently once the shell is deployed, so the verifier fails if any of those appear. During development the shell runs from the repository while configuration is read from its final location; that asymmetry is deliberate.
- **The configuration schema is deliberately minimal and its entries are objects.** `{"bar": {"floating": bool, "zones": {"left"|"center"|"right": [ {"type": "…", …settings} ]}}}`. Every entry is an object carrying at least a `type`, never a bare name string, because the file ships to every target machine and per-widget options must not need a format break later. `BarConfig.defaultConfiguration` holds the built-in defaults and is the only place they are written.
- **A bad configuration never costs the user their desktop.** An unrecognised widget name, a malformed entry, or a widget that fails to construct is logged with the offending name and skipped; everything valid still renders. A file that is malformed as a whole falls back to the built-in defaults and is left byte-for-byte untouched — never rewritten, because the thing it is failing to parse is the thing the user is trying to fix. **No code may make any of these fatal.** Every skip is reported through `BarConfig`'s one logging path so the log reads the same way whatever went wrong. See `docs/adr/0003-*.md`.
- **Configuration may choose a widget name and nothing else.** An entry's `type` is the only thing it decides; resolution goes through `WidgetRegistry.componentFor()`. An entry carrying a `path` or `file` key is **refused with a named log line**, not silently stripped — a user who wrote one would otherwise believe it worked, and the file is installer-deployed to every machine, so honouring it would make a user-owned text file a code-execution surface. The shell never writes a configuration file: `NOSARCH_CONFIG_EMIT=1` prints the effective configuration as one JSON log line instead.
- **Widgets extend the contract in `shell/widgets/`, never a bare `Item`.** A bar widget extends `BarWidget` and declares the same required interface: `content` (a `Component` for the bar), `activate` (a `var` click action, called as `activate(widget)`) and `tooltip` (a `string`). Panel content is genuinely optional: `panelContent` defaults to `null` and a widget with no panel declares nothing rather than an empty `Component` — read the distinction through `hasPanel`. The dim-when-idle/brighten-on-hover affordance and the tooltip live in `BarWidget`, so no widget re-implements them. The simplified `SimpleBarWidget` builds `content` and `tooltip` from a required `label` so trivial widgets declare only what they have.
- **A widget declares its own options by ASSIGNING `optionDefaults`, and reads them only through `optionValue()`.** The whole option mechanism is on the contract, in `shell/widgets/BarWidget.qml`: `options` (the entry's settings, handed over by `BarZone` at construction as `options: entry.settings`), `optionDefaults` (what *this* widget takes, as name → default), `hasOptions`, `unrecognisedOptions` and `optionValue(name)`. A widget with nothing to tune declares nothing at all, exactly as one with no panel declares no `panelContent`. Two QML constraints make the shape what it is, both verified on the installed 0.3.2 and both easy to get wrong silently:
  - **`optionDefaults` is deliberately NOT `readonly`.** A derived QML type cannot re-declare *or* assign a property its base already has, and assigning to a base `readonly` one **fails to compile** (`Invalid property assignment: "optionDefaults" is a read-only property`). A readonly declaration here would make every widget's option list unreachable while still loading clean.
  - **One `var options` bag, not one property per option.** `BarZone` builds widgets through `Component.createObject()`, which ignores an unknown named property — but assigning one to a live object *throws* (`Cannot assign to non-existent property`). Per-option properties would turn every option the shell does not know about into a runtime error from a perfectly ordinary configuration file. Adding an option is therefore a change to one widget file, which is the point.
- **An option a widget does not declare is REFUSED BY NAME, and the widget is still built.** It is never silent — a user who wrote a misspelt key would otherwise believe it worked, which is the whole reason `path`/`file` is refused rather than stripped, and the refusal lists the widget's declared options so "which did I mean" is answerable from the log. But it does **not** cost the entry, because unlike `path`/`file` honouring it is not dangerous (the worst it can do is have no effect), and because refusing the entry would break the shipped file on every machine running a shell *older* than its own configuration — the exact format break the object-shaped entries exist to prevent, arriving through a different door. The reader therefore still **keeps** unknown keys verbatim; only the widget knows what it declares, so `BarZone` reports what `widget.unrecognisedOptions` returns, through `BarConfig`'s one logging path. **An unknown option key is never fatal** (ADR 0003). A declared option given an unusable *value* is a different failure and the widget's own business — the clock falls back to its default rather than passing nonsense to `Qt.formatTime()`.
- **A configuration widget name resolves through `WidgetRegistry`'s `entries` map, never a file path.** The map is a literal in shell code; values are file names resolved relative to `shell/widgets/`. Configuration is user-owned and shipped to every machine, so a name that could locate arbitrary code would turn a config file into a code-execution surface. An unknown name resolves to `null` and is skipped with a named log line, never fatal. There is no runtime plugin registry — the framework provides none on the installed version.
- **The centre zone is placed against the bar's container and against nothing else.** `BarSurface` anchors each zone to one plain `Item`: left to `parent.left`, right to `parent.right`, centre with `anchors.centerIn: parent`. There is **no** `Row`, `RowLayout`, `Flow` or other positioner arranging the *zones* — those hand each child whatever width the others leave, which is the accidental-symmetry layout the rewrite is replacing (the pre-rewrite bar "centred" its clock in an overlay and only looked right because the two flanking rows happened to be the same width). Consequently `center.x == (barWidth - center.w) / 2` and nothing else changes it; `scripts/verify-bar-surface.sh` measures exactly that under deliberately lopsided wings, at two bar widths, and fails if any layout type reappears. A zone **sizes itself to its contents and never places itself** (`BarZone` exposes `implicitWidth`/`implicitHeight` only) — a zone that positioned itself would either move with its neighbours or be positioned relative to one.
- **The bar's windows are not created until `BarConfig` has settled.** `Bar.qml` binds its `Variants` model to an empty list until `BarConfig.configured` is true. A layer-shell surface has its size negotiated once, when it maps, and the reader's verdict arrives after the first reference to it — so a bar created immediately maps with the built-in defaults and is never given a second size, which silently made `"floating": false` do nothing. `configured` is deliberately **not** derived from `BarConfig.note` (that is assigned before `floating` has been read, and QML delivers the change synchronously); it is `_settled`, set in `_report()` once the whole verdict is in hand. The failure policy is untouched — waiting on a verdict is not failing on one.
- **`bar.floating` is one switch with one meaning, declared in one place.** True: the window takes `BarConfig.edgeMargin` as its margins (so the transparent gap beside a floating island is not clickable) and the plate takes `BarConfig.cornerRadius`. False: both are zero. The inset and the radius live in `BarConfig` beside the flag because two consumers need the same numbers and two copies of "8" is how a bar ends up with a rounded plate in a square-edged window. They are shell constants, not configuration keys — the schema stays minimal. The fill is always `UI.Colors.background`.
- **Layer-shell surfaces set BOTH a layer and a namespace.** Every `PanelWindow` overlay surface assigns `WlrLayershell.layer` (its place in the layer stack) and a distinct `WlrLayershell.namespace`. This is load-bearing under the panel architecture: panel surfaces need distinct namespaces so per-monitor surfaces and the cross-monitor dismissal twins can be told apart. Framework `PopupWindow`s and plain `Item`s are not layer-shell surfaces and are exempt. **A namespace names the surface's ROLE, not its instance**: every monitor's bar publishes the same one (`nosarch-shell-bar`), because they are all "the bar"; what must not repeat is one namespace across two different roles. `scripts/verify-bar-per-monitor.sh` collects every namespace in the tree and fails if one is claimed by two.
- **The bar is one `PanelWindow` per attached screen, modeled on the LIVE screen list.** `Bar.qml` uses `Variants` with `model:` bound to `Quickshell.screens` (the property is `model:`, not the `variants:` the v0.3.0 docs show — that is a docs typo), and each delegate binds `screen: modelData`. The model must never be a **snapshot** of that list: `Quickshell.screens.slice()`, a spread, `Array.from` or `Object.keys` would all produce a bar that looks perfectly correct on a one-monitor machine and never follows a hot-plug, and no single-monitor run could ever tell. Windows wait on `BarConfig.configured` before being created (see the layer-shell sizing note above), so the model is `[]` until the reader has a verdict and the live list afterwards. The bar also handles `Quickshell.screensChanged` so a monitor arriving is noticed and re-reported rather than leaving its startup line as the only record. Per-monitor *differing* layouts are out of scope: every monitor gets the same layout, because the configuration is one file.
- **Multi-monitor is structured for but UNVERIFIED — only one monitor was ever attached.** See `docs/known-gaps.md` for the full entry. What is checked: the model is the live list (statically, against a named list of forbidden snapshot forms), each window follows its own screen, the shell is connected to `screensChanged`, and the surface count equals the attached-screen count with each surface paired against its own screen's width. What is NOT checked: a bar actually appearing and disappearing as an output is attached and detached, which needs reconfiguring the live desktop's monitors and was therefore not attempted. `scripts/verify-bar-per-monitor.sh` prints this on every run and **fails rather than passing** if it cannot determine how many screens it saw — a check that quietly succeeds because only one monitor exists is worse than no check.
- **Popup state is per-surface and carries no monitor.** One `PopupState` (`components/PopupState.qml`) lives inside each surface, and its whole API — `toggle(id)`, `isActive(id)`, `close()` — takes no screen. This replaces a single global object keyed on monitor-name strings whose `isActive(id, screen)` silently answered "active on any screen" to a caller that omitted the screen: the network widget called it with one argument and the volume widget with two, so on a second monitor the network panel would have appeared on the monitor it was *not* opened from. Two widgets calling one function with different arities cannot disagree loudly, so they disagreed quietly — invisible on one monitor, wrong on two. **Do not reintroduce a screen parameter**, in any position: a required-and-checked argument is the same fragility one space over, because the monitor would still be a per-widget string each widget has to get right. "Which monitor" is answered by which `PopupState` instance a widget holds, and there is no name to name wrongly. The property on a widget is **typed** (`property Components.PopupState popupState`) so a holder of something else fails to construct rather than answering questions about screens. This is the state half only; ticket 11 owns panels as overlay surfaces.
- **Never call anything a "module".** The word is retired: it has meant three different things here and that is why the base class it names reached one widget out of twelve. Say *widget*, *service* or *component*. See the retired entry in `GLOSSARY.md`.
- **Widget naming: the config `type` is kebab-case, the file is UpperCamelCase, and the QML type is that same name.** So `{"type": "system-tray"}` → `SystemTray.qml` → type `SystemTray`; one-word names stay one word (`tray` → `Tray.qml` → `Tray`). Words in a multi-word name are separated by `-` in configuration and nothing at all in the filename — no underscores, no `Module`/`Widget` suffix. Widgets all live in one flat directory, one file per widget, and a widget is added by writing that file and adding one entry to the **widget registry**: the name→file map held in the shell code, which is data rather than runtime discovery. Configuration never carries a file path. Read `GLOSSARY.md` for what a widget is before naming one. Existing pre-rewrite widget files do not follow this rule yet; they move onto it as their own tickets land.
- **The idle-lock helper's words name the inhibit, not the locking.** Read and write idle-lock state through `/usr/local/bin/nosarch/nosarch-session`, never through a second source. Its `idle-lock status` prints `true`, and `enable`/`toggle` "enable", when the inhibit unit is *running* — which means the machine will **not** lock when idle. Any code reading them must translate; taking "enabled" at face value inverts the indicator. That helper's `enable` and `disable` also carry a `pkill … waybar` aimed at the old bar: it becomes inert once waybar is retired, and it is recorded here rather than edited, because the file is NosArch-managed.

## Running

No build step — Quickshell loads QML directly.

`.qmlls.ini` is a checked-in symlink that Quickshell rewrites on every launch,
pointing at whatever runtime directory the current config path hashes to. It is
therefore **never** a real change: `git checkout -- .qmlls.ini` before every
commit, and never stage it.

Ten verification scripts live in `scripts/`. `verify-docs.sh` is the odd one
out: every other one works by launching the shell and reading its log, because
for QML the framework's only failure signal is the log.

- `scripts/verify-smoke.sh` launches `smoke.qml` under a private D-Bus session,
  instantiates every widget, service and shared component (per screen) and
  fails if any item fails to load or if any WARN/ERROR line names a file in
  this repo. It also checks that the smoke plan still covers everything in
  the tree, so a widget added without being listed there fails loudly.
- `scripts/verify-launch-reload.sh` launches the real `shell.qml` by path,
  checks the layer/namespace convention statically, forces a reload and reads
  the fresh-vs-reloaded verdict out of the log.
- `scripts/verify-palette.sh` launches `smoke.qml` six times with `HOME`
  pointed at a scratch directory, and asserts the palette's four promises
  against a real filesystem: absent file renders defaults, first run writes
  them out, an existing file is never overwritten, and a malformed file is
  left byte-for-byte untouched.
- `scripts/verify-pre-rewrite-baseline.sh` checks the `pre-rewrite` tag out
  into a scratch worktree, launches both pre-rewrite entrypoints with a
  timeout and confirms nothing leaked. See `docs/pre-rewrite-baseline.md`.
- `scripts/verify-docs.sh` launches nothing. It checks that `GLOSSARY.md` and
  the decision records exist in the house formats, and — mostly — that the
  claims they make about the tree are still true: which services still
  publish display glyphs, whether any framework popups remain, whether the
  retired word "module" still names what the glossary says it names, and
  whether the idle-lock inversion still matches the installed session
  helper. It also fails if this file stops documenting one of the verifiers.
  **Add your script to the list above in the same commit that adds it.**
- `scripts/verify-bar-per-monitor.sh` checks the per-monitor promises. It
  asserts the layout's *shape* statically — the `Variants` model is the live
  attached-screen list and never a named form of snapshot, each delegate binds
  `screen: modelData`, the bar handles `screensChanged`, and every
  `WlrLayershell.namespace` in the tree is claimed by exactly one surface role.
  It then asserts the popup-state arity split is gone: nothing in the tree
  stores a monitor name in popup state, nothing takes or passes a screen, no
  call site has a branch that widens a missing screen to "any monitor", no
  global `popupStateManager` survives, and a `PopupState` is created inside the
  per-screen delegate. Finally it launches the real shell under a private bus
  and **measures**: the framework's attached-screen count beside the bar's own
  live-window count, each live window's name/geometry/namespace read off the
  screen it is bound to, and each reported surface paired against its own
  screen's width less the two floating insets. Its last case reports the
  single-monitor **known gap** and fails if the screen count could not be
  determined — hot-plug itself is not exercised, because that needs a second
  output.
- `scripts/verify-widget-contract.sh` checks the widget contract statically (one
  base, optional panel content, every widget on the contract, a name→file map
  carrying no paths) and then launches `smoke.qml` to read the contract's
  promises off live instances: that every registered name resolves to a loadable
  component, that an unknown one resolves to nothing, that the clock declares no
  panel and updates every minute, and that the base dims and brightens.
- `scripts/verify-bar-config.sh` checks that the configuration path is absolute
  and user-overridable and that nothing an entry carries can locate code, then
  launches `smoke.qml` six times against real scratch directories (HOME *and*
  XDG_CONFIG_HOME both redirected, so the live `~/.config/quickshell/` is never
  created): no file at all yields defaults and a working bar; a file drives zone
  contents and order; an unknown name, a malformed entry and a `path`/`file`
  key are each skipped with a named line while everything valid still renders;
  a malformed file as a whole falls back to defaults and is left byte-for-byte
  untouched; reorder/remove/add are configuration edits alone; and a widget that
  cannot be constructed is skipped without taking its zone with it.
- `scripts/verify-bar-surface.sh` checks that the bar really is three zones with a
  truly centred centre, and that floating/full-width is a configuration edit. It
  asserts the layout's *shape* statically — the three zones are anchored to one
  plain container and never to a `Row`/`RowLayout`/`Flow`, the centre zone's
  placement never mentions either wing, the fill comes from `UI.Colors` and not a
  literal, the window sets a layer and a namespace distinct from the pre-rewrite
  bar's, and `shell.qml` composes the new bar rather than the old one. It then
  launches `smoke.qml` against scratch `HOME` *and* `XDG_CONFIG_HOME` and
  **measures** the centre zone: with deliberately lopsided wings it requires
  `center.x == (barWidth - center.w) / 2`, at two bar widths, and it compares
  two configurations against each other to require the centre not to move when
  only the wings change. Finally it launches the real `shell.qml` twice — once
  with no configuration file, once with `"floating": false` — and requires the
  surface the compositor actually hands the bar to be exactly the two floating
  insets wider in floating mode.
- `scripts/verify-widget-options.sh` checks that a widget's declared options
  actually reach it and actually change what it does. Statically, the option
  machinery lives on the **contract** (`BarWidget`), the zone hands
  `entry.settings` over at construction, the clock declares its own option and
  binds its rendering to it, and a widget with nothing to tune declares
  nothing. Then it drives real configuration files through the real reader and
  the real zone: a declared option must arrive with the value the file gave it;
  two runs of the *unmodified* tree against two different files must produce
  different rendered text (a mechanism that delivered a value but changed no
  behaviour would pass the first check and fail this one); an option no widget
  declares must be named in a refusal that lists what the widget *does*
  declare, cost only that key, and leave the widget built; and `{ "type":
  "clock" }` with no options at all — the format shipped by ticket 07 — must
  still work.
- `scripts/verify-notification-widget-and-state.sh` checks the notification
  indicator on the widget contract, persisted do-not-disturb through
  `Quickshell.statePath`, and a single source of truth shared by
  `NotificationService` and the widget. Statically it rejects
  `PersistentProperties` in services and a local `doNotDisturb` default on the
  service. At runtime it reads smoke contract probes, writes DND on a first
  run with no state file, and requires a second launch to read it back.

What remains true from the old note: **the process itself still exits 0 even
when every binding throws**, so a QML syntax or type error only surfaces at
run time — that is precisely why the shell-launching checks launch the shell
instead of linting it, and why the smoke script parses the log rather than
trusting the exit code.

The shell-launching scripts run the shell inside `dbus-run-session`, so the
shell's NotificationServer owns `org.freedesktop.Notifications` on a throwaway
bus and swaync keeps the real one. The smoke shell draws no surfaces at all; the
launch/reload shell briefly draws the real ones and is always killed
afterwards. Nothing is written to `~/.config`, `~/.local/share` or any
installed location.

## Documentation

Quickshell documentation can be found at (https://quickshell.org/docs/v0.3.0/types)

Three decisions are settled and must not be quietly reversed while tidying up
code: services expose state and never presentation
(`docs/adr/0001-services-expose-state-never-presentation.md`), panels are
layer-shell overlay surfaces rather than framework popups
(`docs/adr/0002-panels-are-overlay-surfaces-not-popups.md`), and a bad
configuration never stops the shell
(`docs/adr/0003-a-bad-configuration-never-stops-the-shell.md`). All three record
why a reasonable reader would undo them, which is the only reason any of them
needs writing down.

`docs/known-gaps.md` records the other thing that must not be mistaken for
done: behaviour this shell is **structured for but has not verified**, with the
reason, what is checked in its place, and what would close it. Its one entry
today is that multi-monitor correctness has never run with a second monitor
attached. Read it before claiming any of it works, and add an entry there
rather than letting a check quietly start passing for a smaller reason than its
name suggests.

## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the repo root and decision records in `docs/adr/`. See `docs/agents/domain.md`.
