# 04: Theme-driven palette and fonts

**What to build:** The shell reads its colours from a palette file in the existing NosArch theme directory — which today holds wallpapers only and has no palette of any kind — and falls back to a known-good default palette when none exists, so a fresh install still renders correctly. On first run it writes those defaults out so I have something to edit. It never overwrites an existing file, and a file I was midway through editing is left completely alone if it turns out to be malformed. Fonts are configured in one place so a font change applies everywhere. No colour is hardcoded in any widget.

**Blocked by:** 02 (launch, reload and fresh-vs-reload logging).

**Status:** resolved

- [ ] Colours come from a palette file read from the NosArch theme directory.
- [ ] With no palette file present, the shell renders using a known-good default palette.
- [ ] On first run with no palette file, the shell writes the defaults out so there is something to edit.
- [ ] An existing palette file is never overwritten.
- [ ] A malformed palette file falls back to defaults and leaves the file itself untouched.
- [ ] Fonts are configured in a single place and a change there applies everywhere.
- [ ] No widget hardcodes a colour or a font property.
- [ ] Accent, background, foreground and alert colours are named consistently, so widgets do not invent their own names for the same colour.

## Comments

Implemented on branch `04-theme-driven-palette-and-fonts`, merged to `feat/shell-foundation-and-bar`.

`shell/ui/Colors.qml` is rewritten. The path is resolved from `Quickshell.env("HOME")`, not `Quickshell.statePath()` — the palette lives in the NosArch theme directory beside the wallpapers, so a theme change updates the shell; a Quickshell state directory would be the wrong home for it.

Format decision: **JSON via FileView + JsonAdapter.** The repo's configuration direction is already JSON, and `JsonAdapter` makes the defaults ordinary QML declarations — there is no second copy of the colour literals to drift, which is the whole point of the spec's "defaults held in the shell code". The file is a flat JSON object, one hex colour per key, human-editable in place.

**Two FileViews, and why.** A `JsonAdapter` deserializes when its file is loaded, so a malformed file makes it log `Failed to deserialize json` — a WARN naming `Colors.qml` on every start, which is exactly the log-clean fallback the spec forbids. So an adapter-less *sniffer* `FileView` reads the content first and only approves a `reload()` when it structurally looks like a JSON object; the palette `FileView` (adapter attached from the start, `preload: false`, `blockLoading: false`) then performs exactly one load — of approved content only. Every link of this chain was verified against the installed 0.3.2 with throwaway probes first, including that `reload()` populates an adapter attached from the start, and that `blockLoading` forces a load despite `preload: false` (which is why the palette FileView sets both false).

The `JsonAdapter` timing rule from the API notes was the thing that mattered: at `Component.onCompleted` the adapter still holds its QML defaults, not the file's values. `text()` is the documented flush and is called before `_merge()`. Get this wrong and the palette silently reads as defaults.

Defaults live in exactly one place — the `JsonAdapter` property declarations. Public properties are seeded from them in `_startup()` before any file loads, then replaced per-key in `_merge()`. A key the file omits keeps its default; a value that is not a colour falls back to the default for that key with a named log line. Every run logs a `PALETTE verdict` and `PALETTE values` pair.

Canonical colour names: `accent`, `background`, `foreground`, `alertRed`. **"alert" is spelled `alertRed` in the code and was deliberately NOT renamed** — the spec's promise is that widgets use the one canonical name rather than inventing their own, and renaming would break every widget that references `alertRed`. Four supporting names complete the palette: `backgroundSurface`, `backgroundHover`, `foregroundSecondary`, `foregroundMuted`. The file exposes exactly these eight keys.

Fonts: already in one place (`shell/ui/Fonts.qml`); every shipped widget and component uses `UI.Fonts.*`. No change needed.

Hardcoded-colour grep, and what it found:

- **Fixed:** `ArchIconModule` `#1793d1` → `UI.Colors.accent`; `BatteryModule` `#ff5555` → `UI.Colors.alertRed`; `ProgressOSDItem`'s `#50ffffff` track → `UI.Colors.foreground` at 0.31 opacity. The last one is pixel-identical in the default theme (`#50ffffff` is white at 80/255 ≈ 0.31) and was restructured as a *sibling* of the fill rather than its parent, so the fill keeps full opacity.
- **Reported, not changed:** `BatteryModule` and `NetworkModule` both use `#ffb86c` for a warning state with no palette home. Adding a `warning` key would break the "exactly the names Colors.qml already uses" promise. Both widgets already agree on the literal, so migration is one line each — recommend a follow-up ticket.
- `NetworkModule`'s `#e74c3c`/`#f39c12` are in commented-out dead code. `testing/ServiceReadout.qml` (dev-only panel, no script runs it) keeps its literals, including a misspelled font family. `smoke.qml`'s `font.pixelSize: 12` is test scaffolding, not a widget.

`scripts/verify-palette.sh` runs all six filesystem cases against a real filesystem, each launching the smoke entrypoint under `dbus-run-session` with `HOME` at a scratch dir so the live theme directory is never touched. TDD followed: red showed all six cases failing against the pre-ticket tree ("no palette file is ever read"), green is PASS on all six — case 3 shows the file's distinctive values, cases 4 and 5 show byte-for-byte sha256-unchanged files, case 6 shows `accent`/`alertRed` from file with the other six at defaults.

`scripts/verify-smoke.sh` and `scripts/verify-launch-reload.sh` now redirect `HOME` to a scratch directory too, since the palette writes under `$HOME` on first run — without that they would have written into the live theme directory. Both still PASS, as does the new palette check.

Live desktop untouched: waybar 1333, hyprpaper 1335, swayosd 1347, swaync 1487 still hold their original PIDs; the live theme dir contains only its original three entries (no `palette.json`); no stray quickshell or session-bus processes. `.qmlls.ini` was repointed by quickshell launches as warned, reverted, working tree clean.
