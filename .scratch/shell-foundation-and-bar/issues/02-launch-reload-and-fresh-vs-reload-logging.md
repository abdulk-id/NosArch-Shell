# 02: Launch, reload, and tell a fresh start from a reload

**What to build:** As a maintainer I can launch the shell by pointing it at an explicit path in my repository, without installing it, and save a file to see the change within about a second. When I read the log I can tell whether the shell started fresh or reloaded, so a state reset is never confused with a clean start. This also establishes the layer-shell convention — every overlay surface sets a layer and a namespace — which the panel architecture later depends on for distinguishing per-monitor surfaces.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [ ] The shell launches from an explicit path passed on the command line, from the repository, with nothing installed and no autostart entry required.
- [ ] Saving a file reloads the shell and the reload is visibly fast — the edit loop is under a second in normal operation.
- [ ] The log states plainly whether this process started fresh or reloaded, so the two are distinguishable at a glance.
- [ ] Every overlay surface sets both a layer and a namespace, following the restored layer-shell convention.
- [ ] The convention is recorded in the project instructions, since it is load-bearing for the panel architecture rather than incidental.

Implemented on branch `02-launch-reload-and-fresh-vs-reload-logging`, merged to `feat/shell-foundation-and-bar`.

`scripts/launch.sh` runs `quickshell -p <repo>/shell.qml`, resolving the repo root itself so it works from any invocation directory. It passes extra args through (`-n` refuses to run if an instance already exists).

Fresh-vs-reload dispatch in `shell.qml` relies on `Quickshell.reloadCompleted`, and the reasoning is documented in a comment block at the top of that file. The short version: on 0.3.2 a reload re-evaluates the config in the *same* OS process, so `processId` / `instanceId` / `shellId` / `launchTime` are all identical across a fresh start and every reload, and persistent properties do not survive either — none of those can distinguish the two. `reloadCompleted` fires once per reload and never on a fresh start, and is delivered synchronously before a timer armed in `Component.onCompleted` can run, so the verdict is deterministic rather than a timing race.

`reloadFailed` is handled too: a failed reload keeps the previous config running, and that generation has already printed its verdict, so making the failure visible stops a half-applied state reset from looking clean.

Layer + namespace restored on all six overlay surfaces. `testing/ServiceTest.qml` (since renamed `testing/ServiceReadout.qml`) was the only one missing both. The convention is recorded in AGENTS.md as a single Conventions bullet, with the note that it is load-bearing for the panel architecture. The "No verification step" Running lines were deliberately left for ticket 03.

Measured rather than estimated: reload compute 368 ms (Reloading → Configuration Loaded), end-to-end save → live 458 ms. Both comfortably under a second.

Two traps that cost time to find, recorded here because they will bite the next implementer:

- Reload fires on **content** change, not mtime alone. A bare `touch` does not trigger it, so the verifier edits the file's content.
- `.qmlls.ini` is a checked-in symlink that quickshell rewrites on every launch, pointing at a per-config-path VFS build dir. Any agent that launches the shell from its own worktree path will see it change. Do not commit that.

Verification ran under `dbus-run-session` so the shell's NotificationServer could not compete with swaync for `org.freedesktop.Notifications` on the live bus. Layer surfaces flash briefly (Wayland is bus-independent) but are always killed within seconds. waybar 1333, hyprpaper 1335, swayosd 1347 and swaync 1487 held their original PIDs throughout, and no stray quickshell / dbus-daemon / portal processes survived.

