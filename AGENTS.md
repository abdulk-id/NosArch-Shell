# AGENTS.md

## What This Is

Quickshell desktop shell configuration (`nosarch-shell`) written in QML.

Currently implements:

- A top bar like waybar (TopIsland)
- OSDs,
- Notifications,
- Wallpaper (on Wayland)

## Architecture

- System info (CPU, memory, battery) comes from `services/SystemInfo.qml`, updated every 2s
- Notifications handled by `services/NotificationService.qml` using `Quickshell.Services.Notifications`

### File Layout

- `shell.qml`: Quickshell entrypoint. Imports and composes all shell components.
- `shell/`: Contains all the shell components to be used in the shell entrypoint.
    - `shell/topisland/`: Waybar-like top bar with modules in `./modules` (such as clock, workspaces, system tray, etc.)
    - `shell/notifications/`: Contains notification popups
    - `shell/osds/`: Contains volume, brightness, media, progress OSDs
        - `./ProgressOSDPanel.qml`: Contains all OSDs that show progress data
            - Volume defined by `VolumeOSD`,
            - Brightness defined by `BrightnessOSD`,
            - Keyboard brightness defined by `KeyboardBrightnessOSD`,
        - `./MediaOSD.qml`: Separate OSD for showing playback info
    - `shell/ui/`: Contains singletons for UI properties (such as colors in `Colors` and fonts in `Fonts`)
- `services/`: Contains singletons for `SystemInfo`, `NotificationService`, `Media`; register via `services/qmldir`
- `components/`: Contains shared components (`Separator`, `ProgressOSDItem`)
- `testing/`: Standalone test components (not automated tests)

## Conventions

- Singletons use `pragma Singleton` and are registered in `qmldir` files (services and shell/ui)
- All UI uses `UI.Colors.*` and `UI.Fonts.*` — never hardcode colors or font properties
- Import singletons as `import "path" as UI` then reference `UI.Colors`, `UI.Fonts`
- Wayland layer shell: use `WlrLayershell.layer` and `WlrLayershell.namespace`

## Running

No build step — Quickshell loads QML directly.

## Documentation

Quickshell documentation can be found at (https://quickshell.org/docs/v0.3.0/types)
