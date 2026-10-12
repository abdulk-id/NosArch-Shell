# 07: Bar contents driven by a user-owned configuration file

**What to build:** What appears in my bar comes from a JSON configuration file, not from QML, so reordering widgets, removing one, and adding one are all config edits rather than code changes. The file lives outside the repository, in the user's Quickshell config directory, at a deliberately absolute path that is not resolved relative to the QML source — resolving it relatively would appear to work during development and silently break once the shell is deployed. It is owned by the user, not tracked in git, because the installer deploys it.

A bad configuration never costs me my desktop. An unrecognised widget name, a malformed entry, or a widget that fails to construct is logged with the offending name and skipped; everything valid still renders. A malformed file as a whole falls back to defaults and the shell still starts.

Bar layout has three named zones, each an ordered list of widget entries. Each entry is an object carrying at least a type, with optional per-widget settings — entries are objects rather than bare name strings from the outset, because the config file ships to every target machine and a future format break would mean a migration on every machine.

**Blocked by:** 06 (widget contract, widget registry, and the clock widget).

**Status:** resolved

- [ ] Bar contents come from a JSON configuration file rather than from QML.
- [ ] The configuration path is absolute and not resolved relative to the QML source, so it survives the shell being deployed.
- [ ] The configuration lives outside the repository and is not tracked in git.
- [ ] Bar layout has three named zones — left, centre, right — each an ordered list of widget entries.
- [ ] Each entry is an object carrying at least a type, not a bare name string, so per-widget settings can be added later without a format change.
- [ ] An unrecognised widget name is skipped rather than fatal, and the log names the offending widget.
- [ ] A malformed entry, or a widget that fails to construct, is logged with its name and skipped; everything valid still renders.
- [ ] Malformed configuration as a whole falls back to defaults and the shell still starts.
- [ ] With no configuration file present, the shell starts with defaults and a working bar.
- [ ] Reordering widgets within a zone, removing a widget, and adding a widget are each achievable by editing configuration alone.
Implemented on branch `07-config-driven-bar-contents`, merged to `feat/shell-foundation-and-bar`.

**Path: `$XDG_CONFIG_HOME/quickshell/nosarch/shell.json`**, defaulting to `~/.config/...`, overridable in full by `NOSARCH_SHELL_CONFIG`. Absolute on purpose: resolved against the shell's own directory it works perfectly in the repository and breaks silently the moment the installer deploys the shell elsewhere. `verify-bar-config.sh` check (A) fails the build if `Qt.resolvedUrl`, `Quickshell.shellDir`, `configDir`, `shellPath` or `configPath` appear in the reader.

**`XDG_CONFIG_HOME` is set on this machine**, so redirecting `HOME` alone in a test would still point the reader at the real `~/.config`. The verifier redirects both. Worth noting for ticket 04's palette: it resolves from `HOME` only, so it is not exposed to this, but the two verifiers are inconsistent about it.

**Schema.** Entries are objects carrying at least a `type`, everything else being that widget's settings. Unknown keys are *kept*, not stripped, so a future per-widget option needs no format change — the file ships to every target machine, so a format break is a migration on every machine. `BarConfig.defaultConfiguration` is the single place the built-in defaults live, and it names only registered widgets, so it must grow as widgets land.

**Did not use `JsonAdapter`.** The schema's shape *is* its content, so an adapter would put the configuration's shape back into QML — the exact thing configuration exists to remove. Reading text and calling `JSON.parse` also sidesteps the adapter timing trap.

**Failure policy**, logged through one path so the log reads the same way whatever went wrong:

```
CONFIG skipped bar.zones.left[1] type=not-a-widget reason=unknown-widget known=clock
CONFIG skipped bar.zones.left[2] type=clock key=path reason=entry-cannot-locate-code
CONFIG skipped bar.zones.left[4] reason=not-an-object got=string
CONFIG skipped bar.zones.left[5] reason=no-type got=undefined
CONFIG skipped bar.zones.probe[0] type=probe-unconstructible reason=widget-failed-to-construct
CONFIG <path> is not valid JSON (…) — using the built-in defaults; the file was left untouched
CONFIG no configuration file at <path> — using the built-in defaults; set NOSARCH_CONFIG_EMIT=1 to print one to save
```

Every skip names its index, type and reason, and says the rest of the bar is unaffected. A `path`/`file` key is **refused, not stripped** — stripping leaves its author believing it worked. Recorded as ADR 0003.

**Emit-defaults: my decision was no first-run write, print on demand via `NOSARCH_CONFIG_EMIT=1`.** The palette's write is not a precedent — the palette *must* exist as a file a theme manager will later replace; configuration does not. And a first-run write creates a race the palette lacks: whoever starts first owns the file, so a shell started before the installer would silently win and the installed configuration would be replaced. The trade-off, stated plainly: **stories 14/15/16 have no file to edit on any machine that has not run the installer**, which is what the printer exists to work around today. Worth a maintainer decision at v1.0.

**Split from 08.** 07 = schema, parsing, validation, instantiation, failure policy. 08 = the three-zone surface, centring, floating/full-width. `BarZone.qml` deliberately contains a `Row` so a *reorder* is observable in this ticket; 08 replaces it.

**Four QML traps found, all now in the API notes addendum:**

1. `number` is not a QML type. A parameter annotated `index: number` logs an ERROR naming a repo file **on every call**; `int` is correct. Isolated with a probe: `string`/`int`/`real`/`double`/`bool`/`var`/`Component` are all silent. Ticket 18's "shell starts with no errors in the log" would have failed on this.
2. `array` is not a valid return type either, and fires the same ERROR. `WidgetRegistry.names(): array` had this **pre-existing from ticket 06**; found on c76713f and fixed.
3. A `pragma Singleton` is not creatable — `BarConfig {}` fails with "Composite Singleton Type BarConfig is not creatable". Same trap as `createObject()`, different disguise. Must be referenced.
4. QML property names cannot begin with an uppercase letter (`ZONE_NAMES` is a compile error), and `: null` is not a valid return type.

**Verifier:** `scripts/verify-bar-config.sh` — RED first (all six cases failed against the hardcoded bar), then PASS on six promises: defaults with no file; a file drives contents and order; nine sub-cases each skipping with an index while valid entries either side still render in order and no WARN/ERROR names a repo file (skipping is not throwing); six cases of malformed-file fallback with byte-for-byte sha256; reorder/remove/add as config-only edits; and four cases of unconstructible widget.

**A known fragility, reported not hidden:** `verify-palette.sh` case 2 flaked once in 15 full runs on the 07 tree and 0 in 10 on a clean c76713f, with 0 in 12 direct smoke launches on both. Not distinguishable from noise, and it is in ticket 04's code which 07 did not touch — but it is a real fragility in that verifier worth knowing about.

`verify-launch-reload.sh` needed no change (it copies `shell/`, so `shell/bar/` came along); `verify-smoke.sh` needed one line for the new `configPlan` ↔ `shell/bar/qmldir` both-directions entry. All seven verifiers green.

Live desktop: waybar 1333, hyprpaper 1335, swayosd 1347, swaync 1487 unchanged; `~/.config/quickshell` still absent; no writes to `~/.config/hypr` or `~/.local/share/nosarch`; no autostart; no stray quickshell or dbus-daemon.

