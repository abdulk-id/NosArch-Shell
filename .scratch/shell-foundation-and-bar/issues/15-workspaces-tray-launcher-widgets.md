# 15: Workspaces, tray, and launcher widgets

**What to build:** Workspace indicators showing which workspaces exist and which is focused, so I can see my window layout at a glance; clicking one switches to it, so I can navigate without a keybind; and workspaces with no windows appear dimmed, so empty ones are distinguishable.

A system tray showing my running applications' icons, with all three mouse buttons working: left-click activates, right-click shows the context menu, middle-click triggers the secondary action. The tray is carried forward substantially unchanged — its menu anchoring and three-button handling are already right.

A launcher icon that opens my existing application launcher. The launcher itself is out of scope and deferred pending my own evaluation of it; only the icon that opens it is in scope here.

**Blocked by:** 09 (per-widget options in configuration).

**Status:** ready-for-agent

- [ ] Workspace indicators show which workspaces exist and which is focused.
- [ ] Clicking a workspace indicator switches to it.
- [ ] Workspaces with no windows appear dimmed.
- [ ] The tray shows my running applications' icons.
- [ ] Left-clicking a tray icon activates it.
- [ ] Right-clicking a tray icon shows its context menu, so tray-only actions are reachable.
- [ ] Middle-clicking a tray icon triggers its secondary action.
- [ ] The tray's existing menu anchoring and three-button handling survive the migration.
- [ ] The launcher icon opens my existing application launcher. The launcher itself is not built here.