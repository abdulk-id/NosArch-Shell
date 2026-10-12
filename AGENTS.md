# AGENTS.md

## What This Is

Quickshell desktop shell configuration (`nosarch-shell`) written in QML.

## File Layout

- `shell.qml`: Quickshell entrypoint. Imports and composes all shell components.
- `smoke.qml`: Smoke-test entrypoint. Instantiates every widget, service and shared component (once per screen) and reports each by name. It draws nothing — run it through `scripts/verify-smoke.sh`, never as a live shell.
- `shell/`: Contains all the shell components to be used in the shell entrypoint.
- `services/`: Contains singletons for `SystemInfo`, `NotificationService`, `Media` etc.; register via `services/qmldir`
- `components/`: Contains shared components (`Separator`, `ProgressOSDItem`)
- `testing/`: Development readout panels, not verification. `ServiceReadout.qml` renders live service values by eye; it asserts nothing and no script runs it.

## Conventions

- Singletons use `pragma Singleton` and are registered in `qmldir` files (services and shell/ui)
- All UI uses `UI.Colors.*` and `UI.Fonts.*` from colors and fonts singletons in `shell/ui` — never hardcode colors or font properties
- The palette is file-backed: `UI.Colors` reads `~/.local/share/nosarch/current-theme/palette.json` (resolved from `HOME`, not `Quickshell.statePath()` — it is the NosArch theme directory, not a Quickshell state dir), falls back to the built-in defaults, writes them out on first run, and never overwrites an existing file. The file is a flat JSON object with one hex colour per key: `accent`, `alertRed`, `background`, `backgroundHover`, `backgroundSurface`, `foreground`, `foregroundMuted`, `foregroundSecondary`. Keys the file omits keep their defaults; a malformed file is left untouched and the defaults are used.
- Import singletons as `import "path" as UI` then reference `UI.Colors`, `UI.Fonts`
- **Layer-shell surfaces set BOTH a layer and a namespace.** Every `PanelWindow` overlay surface assigns `WlrLayershell.layer` (its place in the layer stack) and a distinct `WlrLayershell.namespace`. This is load-bearing under the panel architecture: panel surfaces need distinct namespaces so per-monitor surfaces and the cross-monitor dismissal twins can be told apart. Framework `PopupWindow`s and plain `Item`s are not layer-shell surfaces and are exempt.
- **Never call anything a "module".** The word is retired: it has meant three different things here and that is why the base class it names reached one widget out of twelve. Say *widget*, *service* or *component*. See the retired entry in `GLOSSARY.md`.
- **Widget naming: the config `type` is kebab-case, the file is UpperCamelCase, and the QML type is that same name.** So `{"type": "system-tray"}` → `SystemTray.qml` → type `SystemTray`; one-word names stay one word (`tray` → `Tray.qml` → `Tray`). Words in a multi-word name are separated by `-` in configuration and nothing at all in the filename — no underscores, no `Module`/`Widget` suffix. Widgets all live in one flat directory, one file per widget, and a widget is added by writing that file and adding one entry to the **widget registry**: the name→file map held in the shell code, which is data rather than runtime discovery. Configuration never carries a file path. Read `GLOSSARY.md` for what a widget is before naming one. Existing pre-rewrite widget files do not follow this rule yet; they move onto it as their own tickets land.
- **The idle-lock helper's words name the inhibit, not the locking.** Read and write idle-lock state through `/usr/local/bin/nosarch/nosarch-session`, never through a second source. Its `idle-lock status` prints `true`, and `enable`/`toggle` "enable", when the inhibit unit is *running* — which means the machine will **not** lock when idle. Any code reading them must translate; taking "enabled" at face value inverts the indicator. That helper's `enable` and `disable` also carry a `pkill … waybar` aimed at the old bar: it becomes inert once waybar is retired, and it is recorded here rather than edited, because the file is NosArch-managed.

## Running

No build step — Quickshell loads QML directly.

Five verification scripts live in `scripts/`. `verify-docs.sh` is the odd one
out: the other four work by launching the shell and reading its log, because for
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

Two decisions are settled and must not be quietly reversed while tidying up code:
services expose state and never presentation
(`docs/adr/0001-services-expose-state-never-presentation.md`), and panels are
layer-shell overlay surfaces rather than framework popups
(`docs/adr/0002-panels-are-overlay-surfaces-not-popups.md`). Both ADRs record
why a reasonable reader would undo them, which is the only reason either needs
writing down.

## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the repo root and decision records in `docs/adr/`. See `docs/agents/domain.md`.
