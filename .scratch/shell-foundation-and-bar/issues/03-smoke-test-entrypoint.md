# 03: Smoke-test entrypoint for every widget and service

**What to build:** A single verification seam that instantiates every widget and service and fails on QML load errors — type errors, missing properties, unresolved bindings — without involving my live bar. Today nothing objects when a widget grows past a thousand lines or is left half-wired, because there is no verification step at all. This is the first verification artefact in this codebase.

**Blocked by:** 02 (launch, reload and fresh-vs-reload logging).

**Status:** resolved

- [ ] A smoke-test entrypoint instantiates every widget and every service in the shell.
- [ ] Type errors, missing properties and unresolved bindings surfaced by that instantiation cause a non-zero exit.
- [ ] The check runs without a live bar on screen, so a broken widget is caught before I rely on it.
- [ ] The project instructions no longer claim there is no verification step, and no longer claim syntax errors surface only at runtime — both statements are false once this lands.

Implemented on branch `03-smoke-test-entrypoint`, merged to `feat/shell-foundation-and-bar`.

`smoke.qml` sits at the repo root, which is forced rather than chosen: Quickshell 0.3.2 refuses to load anything above the config root (the `-p` file's directory — `../` hits a `qrc:/qs-blackhole`). It instantiates, by name, all 12 widgets in `shell/topisland/modules/`, all 7 services from `services/qmldir`, and all 3 shared components from `components/qmldir`, once per attached screen via `Variants` over `Quickshell.screens`, parented to in-memory `Item`s so it draws no surface at all.

`scripts/verify-smoke.sh` runs three checks: **(A)** the plan in `smoke.qml` must still match the tree in *both* directions, so a widget added but never listed fails loudly; **(B)** every planned item must print a PASS line; **(C)** any WARN/ERROR that *names a repo file* fails, while warnings with no repo file attached (xdg-desktop-portal, Qt platform services, hyprland-IPC chattiness) are reported as ignored rather than hidden.

Decision on warnings: **warnings fail.** In Quickshell a type error, a missing property and an unresolved binding all surface as WARN lines from the faulting file, and the process exits 0 regardless — which is exactly the ServiceTest trap, where ~13 property TypeErrors coexisted with a clean exit. So the script parses the log rather than trusting the exit code, and `Qt.exit(N)` is only a courtesy because it does not exit quickshell. Strictness is affordable because the runner was made deterministic: singletons are constructed at t=0 and the script waits, capped at 8 s, for the exact sub-objects widgets dereference (`defaultSink`, `defaultSource`, `activeNetwork`) before instantiating. A fixed 2 s settle was measurably racy (red one run, green the next), so it waits instead of guessing. There is no allowlist anywhere, which is what keeps the check honest; if the cap expires the log says so and a warning after it is counted as a defect.

`testing/ServiceTest.qml` became `testing/ServiceReadout.qml`, with a header stating it asserts nothing and is run by no script. Its live-readout value moved into the smoke test's per-service PASS lines, which print live values without needing a panel on screen. Two half-tests were not left side by side.

`shell.qml` is deliberately **not** instantiated by the smoke test: loading it as a component resolves `TopIsland is not a type`, because a config's local-dir types only work as the config root. Its composition stays covered by `scripts/verify-launch-reload.sh`. One seam per job.

Negative tests confirm the harness has teeth: an injected undefined reference in a widget fails with a `ReferenceError` naming file and line; a syntax break fails with `component failed to load`; an unlisted module file fails; a ghost plan entry fails.

Out-of-scope one-line fix, flagged in case it should be reverted: the smoke test caught `NetworkService.activeNetwork` falling off the end of its binding block (no trailing `return null`), producing `Unable to assign [undefined] to Network*`. Fixed so the verifier can pass out of the box rather than shipping with a permanent allowlist.

Known fragility, deliberately not papered over: on a machine with no audio device, the pre-existing `defaultSink.description` read in `VolumeModule` would make this check red — a genuine story-83 defect for the widget tickets to fix. `NetworkModule[194]` has a latent `Unable to assign [undefined] to QString` when wifi is off, which does not fire on this machine.

Runs under `dbus-run-session`; swaync still owns `org.freedesktop.Notifications`; no surfaces drawn. Verified green on the integration branch: planned=22, passed=22, failed=0.

