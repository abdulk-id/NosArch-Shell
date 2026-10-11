# Pre-rewrite baseline (`pre-rewrite` tag)

A restorable snapshot of `nosarch-shell` as it stood before the shell-foundation
rewrite, with the exact commands to launch it and to get back to it. This record
was verified, not assumed: every command below was executed successfully against
the live system on 2026-10-11 with Quickshell 0.3.2 (Arch Linux), and
`scripts/verify-pre-rewrite-baseline.sh` re-runs those checks on demand.

## What the tag points at

| | |
|---|---|
| Tag | `pre-rewrite` (annotated tag, object `ec90b7197f23fee784761e3237a5bb3020bc006a`) |
| Commit | `77629f346b65f74ff042cf78a9a3b74d187328a1` |
| Commit subject | `WIP: pre-rewrite state of nosarch-shell` |
| Tag message | `Pre-rewrite snapshot of nosarch-shell; reference point for the Quickshell rewrite` |
| Relationship | Genuine ancestor of `master` and of every branch in flight, so `git diff pre-rewrite <branch>` is the rewrite diff |

The tagged tree is the whole pre-rewrite shell: `shell.qml` (entrypoint),
`shell/` (topisland, osds, notifications, ui), `services/`, `components/`, and
`testing/ServiceTest.qml`.

To confirm the tag by hand (identity, not trust):

```sh
git rev-parse pre-rewrite^{commit}          # must print 77629f346b65f74ff042cf78a9a3b74d187328a1
git log -1 --format=%s pre-rewrite         # must print the pre-rewrite subject
git merge-base --is-ancestor pre-rewrite master && echo ancestor
```

Note: the tag is **annotated**, not lightweight (it carries the tagger and
message above). That is stronger than a lightweight tag; it is recorded here so
nobody is surprised by the extra tag object when scripting around it.

## How to launch it

From the **root of a checkout of the tag** (the working directory matters —
`shell.qml` imports are directory-relative, e.g. `import "shell/topisland"`, so
launching from anywhere else does not resolve):

```sh
cd /path/to/pre-rewrite-checkout   # a checkout of tag `pre-rewrite`, root
quickshell -p shell.qml
```

`-p` is Quickshell's explicit-path option; it exists precisely so a shell can be
run from a repository without being installed. Quickshell 0.3.2 confirmed.

To stop it: `Ctrl-C` in the launching terminal, or bound, e.g.
`timeout 10 quickshell -p shell.qml`. (`quickshell kill` kills the *default*
config instance; while developing against a path, prefer controlling the
terminal process directly.)

Success looks like this in the log (observed verbatim, INFO lines trimmed):

```
INFO: Launching config: "/…/pre-rewrite-checkout/shell.qml"
INFO: Configuration Loaded
```

The shell stays running and draws surfaces: a full-screen background wallpaper
surface and the top island bar. On this desktop the following WARN-level output
is **expected and non-fatal** — observed on every baseline run:

- `VolumeModule.qml: TypeError: Cannot read property 'description' of null`
  and `NetworkModule.qml: TypeError: Cannot read property 'security' of null`
  while services populate.
- `NetworkService.qml: Unable to assign [undefined] to qs::network::Network*`
  — no active network / default route is picked up in this environment.
- `Could not register notification server at org.freedesktop.Notifications` —
  swaync owns the notification name on this desktop; swaync keeps it, the
  baseline shell retries and carries on. Non-fatal, but note the baseline shell
  cannot own notifications while swaync runs.
- `Could not load icon "input-keyboard-symbolic"` — a missing icon-theme entry.

Fatal failure looks different, and is what the verification script greps for:
`failed to load component`, `Component is not ready`, `is not a type`.

The second entrypoint is the service test harness in the same tree:

```sh
cd /path/to/pre-rewrite-checkout
quickshell -p testing/ServiceTest.qml
```

It also reaches `Configuration Loaded`, but it prints a long chain of
WARN-level `TypeError: Cannot read property '…' of undefined` lines
(`SystemInfo.cpu.usagePercent`, `SystemInfo.battery.*`,
`NetworkService.activeNetwork.name`, …). The harness binds service
sub-objects before the singletons populate them (or, for
`NetworkService.activeNetwork`, that object stays null in this environment), so
the harness shows `undefined` rather than live values. It is a pre-existing
rough edge of the old harness, **not** a blocker and **not** a reason to disturb
the tag.

## How to restore / diff against it

**Restore this repository to the tag** (detached checkout; the rewrite branches
stay put):

```sh
git switch --detach pre-rewrite
# … look at the old shell …
git switch feat/shell-foundation-and-bar   # or whatever branch you came from
```

**Restore into an isolated worktree** (recommended while the rewrite is in
progress — leaves your checkout, branches, and the live desktop alone):

```sh
git worktree add --detach /tmp/opencode/pre-rewrite-checkout pre-rewrite
cd /tmp/opencode/pre-rewrite-checkout
quickshell -p shell.qml        # launch exactly as above, in isolation
# … done …
git worktree remove --force /tmp/opencode/pre-rewrite-checkout
```

The worktree path is disposable; anywhere on a real filesystem works
(`/tmp` is convenient precisely because it is not the repo).

**Diff the rewrite against the baseline:**

```sh
git diff pre-rewrite HEAD                  # everything
git diff pre-rewrite HEAD -- shell services components testing
```

## Safety while the rewrite is in flight

- This tag is a **read-only reference**. Nothing in the rewrite writes to it.
- Running the baseline shell writes **nothing** to the live desktop
  configuration: no `~/.config/hypr`, no `~/.config/quickshell` (it does not
  even exist on this system), no `~/.local/share/nosarch`. Its only filesystem
  reads are the wallpaper image and theme values under `~/.local/share/nosarch/`,
  read-only.
- The one live-desktop interaction: while it runs, the baseline shell **draws**
  (wallpaper background surface, top island). Quickshell's background layer
  covers hyprpaper's for those seconds, and swaync keeps the notification name.
  Everything on screen returns to normal the moment the process exits.
- End state of a verification run, verified: no quickshell process surviving the
  launch, no worktree left behind, live tools (waybar, hyprpaper, swaync,
  swayosd, hyprlock) untouched.

## Re-verifying this record

```sh
scripts/verify-pre-rewrite-baseline.sh
```

It re-checks the tag identity and ancestry, checks the tag out into a scratch
worktree (proving restore), launches both entrypoints with a timeout, greps for
fatal QML errors, and confirms nothing leaked. It briefly draws the baseline
surfaces on the live session (~8 s per launch) and cleans up after itself.
Set `BASELINE_SKIP_LAUNCH=1` to skip the live launches (tag and worktree checks
still run).
