# AGENTS.md

## What This Is

Quickshell desktop shell configuration (`nosarch-shell`) written in QML.

## File Layout

- `shell.qml`: Quickshell entrypoint. Imports and composes all shell components.
- `shell/`: Contains all the shell components to be used in the shell entrypoint.
- `services/`: Contains singletons for `SystemInfo`, `NotificationService`, `Media` etc.; register via `services/qmldir`
- `components/`: Contains shared components (`Separator`, `ProgressOSDItem`)
- `testing/`: Standalone test components (not automated tests)

## Conventions

- Singletons use `pragma Singleton` and are registered in `qmldir` files (services and shell/ui)
- All UI uses `UI.Colors.*` and `UI.Fonts.*` from colors and fonts singletons in `shell/ui` — never hardcode colors or font properties
- Import singletons as `import "path" as UI` then reference `UI.Colors`, `UI.Fonts`

## Running

No build step — Quickshell loads QML directly.
No verification step — Quickshell process throws syntax errors at runtime.

## Documentation

Quickshell documentation can be found at (https://quickshell.org/docs/v0.3.0/types)

## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
