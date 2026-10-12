# AGENTS.md

## What This Is

Quickshell desktop shell configuration (`nosarch-shell`) written in QML.

## File Layout

- `shell.qml`: Quickshell entrypoint. Imports and composes all shell components.
- `smoke.qml`: Smoke-test entrypoint. Instantiates every widget, service and shared component (once per screen) and reports each by name. It draws nothing — run it through `scripts/verify-smoke.sh`, never as a live shell.
- `shell/`: Contains all the shell components to be used in the shell entrypoint.
- `shell/widgets/`: The widget extension point. Every bar widget lives here, extending `BarWidget` (or `SimpleBarWidget` for a trivial label-plus-click widget). Adding one means copying a file into this directory, adding one line to `WidgetRegistry.qml`'s `entries` map, and adding one line to `qmldir` — nothing else.
- `services/`: Contains singletons for `SystemInfo`, `NotificationService`, `Media` etc.; register via `services/qmldir`
- `components/`: Contains shared components (`Separator`, `ProgressOSDItem`)
- `testing/`: Development readout panels, not verification. `ServiceReadout.qml` renders live service values by eye; it asserts nothing and no script runs it.

## Conventions

- Singletons use `pragma Singleton` and are registered in `qmldir` files (services and shell/ui)
- All UI uses `UI.Colors.*` and `UI.Fonts.*` from colors and fonts singletons in `shell/ui` — never hardcode colors or font properties
- The palette is file-backed: `UI.Colors` reads `~/.local/share/nosarch/current-theme/palette.json` (resolved from `HOME`, not `Quickshell.statePath()` — it is the NosArch theme directory, not a Quickshell state dir), falls back to the built-in defaults, writes them out on first run, and never overwrites an existing file. The file is a flat JSON object with one hex colour per key: `accent`, `alertRed`, `background`, `backgroundHover`, `backgroundSurface`, `foreground`, `foregroundMuted`, `foregroundSecondary`. Keys the file omits keep their defaults; a malformed file is left untouched and the defaults are used.
- Import singletons as `import "path" as UI` then reference `UI.Colors`, `UI.Fonts`
- **Widgets extend the contract in `shell/widgets/`, never a bare `Item`.** A bar widget extends `BarWidget` and declares the same required interface: `content` (a `Component` for the bar), `activate` (a `var` click action, called as `activate(widget)`) and `tooltip` (a `string`). Panel content is genuinely optional: `panelContent` defaults to `null` and a widget with no panel declares nothing rather than an empty `Component` — read the distinction through `hasPanel`. The dim-when-idle/brighten-on-hover affordance and the tooltip live in `BarWidget`, so no widget re-implements them. The simplified `SimpleBarWidget` builds `content` and `tooltip` from a required `label` so trivial widgets declare only what they have.
- **A configuration widget name resolves through `WidgetRegistry`'s `entries` map, never a file path.** The map is a literal in shell code; values are file names resolved relative to `shell/widgets/`. Configuration is user-owned and shipped to every machine, so a name that could locate arbitrary code would turn a config file into a code-execution surface. An unknown name resolves to `null` and is skipped with a named log line, never fatal. There is no runtime plugin registry — the framework provides none on the installed version.
- **Layer-shell surfaces set BOTH a layer and a namespace.** Every `PanelWindow` overlay surface assigns `WlrLayershell.layer` (its place in the layer stack) and a distinct `WlrLayershell.namespace`. This is load-bearing under the panel architecture: panel surfaces need distinct namespaces so per-monitor surfaces and the cross-monitor dismissal twins can be told apart. Framework `PopupWindow`s and plain `Item`s are not layer-shell surfaces and are exempt.

## Running

No build step — Quickshell loads QML directly.

Two verification scripts live in `scripts/`. Both work by launching the shell
and reading its log, because the framework's only failure signal is the log:

- `scripts/verify-smoke.sh` launches `smoke.qml` under a private D-Bus session,
  instantiates every widget, service and shared component (per screen) and
  fails if any item fails to load or if any WARN/ERROR line names a file in
  this repo. It also checks that the smoke plan still covers everything in
  the tree, so a widget added without being listed there fails loudly.
- `scripts/verify-launch-reload.sh` launches the real `shell.qml` by path,
  checks the layer/namespace convention statically, forces a reload and reads
  the fresh-vs-reloaded verdict out of the log.
- `scripts/verify-widget-contract.sh` checks the widget contract statically (one
  base, optional panel content, every widget on the contract, a name→file map
  carrying no paths) and then launches `smoke.qml` to read the contract's
  promises off live instances: that every registered name resolves to a loadable
  component, that an unknown one resolves to nothing, that the clock declares no
  panel and updates every minute, and that the base dims and brightens.
  `scripts/verify-palette.sh` covers the palette's filesystem promises the same
  way.

What remains true from the old note: **the process itself still exits 0 even
when every binding throws**, so a QML syntax or type error only surfaces at
run time — that is precisely why both checks launch the shell instead of
linting it, and why the smoke script parses the log rather than trusting the
exit code.

Both scripts run the shell inside `dbus-run-session`, so the shell's
NotificationServer owns `org.freedesktop.Notifications` on a throwaway bus and
swaync keeps the real one. The smoke shell draws no surfaces at all; the
launch/reload shell briefly draws the real ones and is always killed
afterwards. Nothing is written to `~/.config`, `~/.local/share` or any
installed location.

## Documentation

Quickshell documentation can be found at (https://quickshell.org/docs/v0.3.0/types)

## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
