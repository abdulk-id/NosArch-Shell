# AGENTS.md

## What This Is

Quickshell desktop shell configuration (`nosarch-shell`) written in QML.

## File Layout

- `shell.qml`: Quickshell entrypoint. Imports and composes all shell components.
- `smoke.qml`: Smoke-test entrypoint. Instantiates every widget, service and shared component (once per screen) and reports each by name. It draws nothing — run it through `scripts/verify-smoke.sh`, never as a live shell.
- `shell/`: Contains all the shell components to be used in the shell entrypoint.
- `shell/widgets/`: The widget extension point. Every bar widget lives here, extending `BarWidget` (or `SimpleBarWidget` for a trivial label-plus-click widget). Adding one means copying a file into this directory, adding one line to `WidgetRegistry.qml`'s `entries` map, and adding one line to `qmldir` — nothing else.
- `shell/bar/`: The bar's own directory. `BarConfig` (a singleton) reads the user's configuration file, validates it and applies the failure policy; `BarZone` builds one zone's widgets from what `BarConfig` answered. The bar *surface* — three zones arranged, centred, floating or full-width — is not here yet and is ticket 08.
- `services/`: Contains singletons for `SystemInfo`, `NotificationService`, `Media` etc.; register via `services/qmldir`
- `components/`: Contains shared components (`Separator`, `ProgressOSDItem`)
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
- **A configuration widget name resolves through `WidgetRegistry`'s `entries` map, never a file path.** The map is a literal in shell code; values are file names resolved relative to `shell/widgets/`. Configuration is user-owned and shipped to every machine, so a name that could locate arbitrary code would turn a config file into a code-execution surface. An unknown name resolves to `null` and is skipped with a named log line, never fatal. There is no runtime plugin registry — the framework provides none on the installed version.
- **Layer-shell surfaces set BOTH a layer and a namespace.** Every `PanelWindow` overlay surface assigns `WlrLayershell.layer` (its place in the layer stack) and a distinct `WlrLayershell.namespace`. This is load-bearing under the panel architecture: panel surfaces need distinct namespaces so per-monitor surfaces and the cross-monitor dismissal twins can be told apart. Framework `PopupWindow`s and plain `Item`s are not layer-shell surfaces and are exempt.
- **Never call anything a "module".** The word is retired: it has meant three different things here and that is why the base class it names reached one widget out of twelve. Say *widget*, *service* or *component*. See the retired entry in `GLOSSARY.md`.
- **Widget naming: the config `type` is kebab-case, the file is UpperCamelCase, and the QML type is that same name.** So `{"type": "system-tray"}` → `SystemTray.qml` → type `SystemTray`; one-word names stay one word (`tray` → `Tray.qml` → `Tray`). Words in a multi-word name are separated by `-` in configuration and nothing at all in the filename — no underscores, no `Module`/`Widget` suffix. Widgets all live in one flat directory, one file per widget, and a widget is added by writing that file and adding one entry to the **widget registry**: the name→file map held in the shell code, which is data rather than runtime discovery. Configuration never carries a file path. Read `GLOSSARY.md` for what a widget is before naming one. Existing pre-rewrite widget files do not follow this rule yet; they move onto it as their own tickets land.
- **The idle-lock helper's words name the inhibit, not the locking.** Read and write idle-lock state through `/usr/local/bin/nosarch/nosarch-session`, never through a second source. Its `idle-lock status` prints `true`, and `enable`/`toggle` "enable", when the inhibit unit is *running* — which means the machine will **not** lock when idle. Any code reading them must translate; taking "enabled" at face value inverts the indicator. That helper's `enable` and `disable` also carry a `pkill … waybar` aimed at the old bar: it becomes inert once waybar is retired, and it is recorded here rather than edited, because the file is NosArch-managed.

## Running

No build step — Quickshell loads QML directly.

`.qmlls.ini` is a checked-in symlink that Quickshell rewrites on every launch,
pointing at whatever runtime directory the current config path hashes to. It is
therefore **never** a real change: `git checkout -- .qmlls.ini` before every
commit, and never stage it.

Seven verification scripts live in `scripts/`. `verify-docs.sh` is the odd one
out: the other five work by launching the shell and reading its log, because for
QML the framework's only failure signal is the log.

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

## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the repo root and decision records in `docs/adr/`. See `docs/agents/domain.md`.
