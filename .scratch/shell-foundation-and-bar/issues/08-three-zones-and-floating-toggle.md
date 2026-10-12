# 08: Three zones, true centre, floating or full-width bar

**What to build:** My bar has left, centre and right zones, matching the waybar muscle memory I already have. The centre zone is truly centred, so the clock does not shift when other widgets change size — the current bar's centre is an overlay that only appears centred because its neighbours happen to be symmetric. The bar appears as a floating rounded island by default, and I can switch it to a full-width background from configuration without touching code.

**Blocked by:** 07 (bar contents driven by a user-owned configuration file).

**Status:** resolved

- [ ] The bar shows widgets in three zones — left, centre, right.
- [ ] The centre zone holds its widgets truly centred, so the clock does not shift when other widgets change size.
- [ ] The bar appears as a floating rounded island by default.
- [ ] Switching the bar to a full-width background is a configuration change, not a code change.
- [ ] Zone contents and their ordering reflect the configuration file.
Implemented on branch `08-three-zones-and-floating-toggle`, merged to `feat/shell-foundation-and-bar`.

**Decision: the new bar replaced `TopIsland` in `shell.qml`.** Three reasons beyond the criteria being user-visible: two bars cannot both be the bar (leaving the old one composed draws a second strip over the top of the screen, worse than either alone); ticket 07's contract explicitly placed the surface in 08; and the window owns the layer-shell namespace (`nosarch-shell-bar`, distinct from the old `nosarch-shell-top-island`), which ticket 10 needs. `import "shell/topisland"` was dropped, so the eleven orphaned widget files are no longer even loaded by the real shell — but they stay on disk and in the smoke plan, so both `verify-docs.sh` check (B) and `verify-smoke.sh` check (A) still hold until ticket 18.

**True centring is the substance of this ticket, and it is proven by measurement.** The old bar "centred" its centre zone with an `Item { anchors.fill: parent }` overlay — balanced only because the neighbouring rows happened to be symmetric, with no independent right-of-centre zone. Each zone is now anchored to one plain `Item`: left → `parent.left`, right → `parent.right`, centre → `anchors.centerIn: parent`. `BarZone` only sizes itself (`implicitWidth`/`implicitHeight`) and never places itself, because a zone that positioned itself would either move with its neighbours or be positioned relative to one.

Measured with deliberately mirror-image wings:

| configuration | left.w | right.w | center.x |
|---|---|---|---|
| 0 left, 3 right | 0 | 456.578 | **431** |
| 5 left, 1 right | 774.297 | 138.859 | **431** |

at bar widths 1000 and 420. The wings changed by 774px and −318px; the centre did not move by a pixel. Edge-hugging is checked independently (`left.x = 10 = pad`, `right.x + right.w = width − pad`).

The residual is **0.43px**, not 0, because QML rounds a `real` to an integer pixel. The mutation test settles whether that tolerance hides anything: reinstating the pre-rewrite relative placement (`anchors.horizontalCenter: leftZone.right`) fails on both the static shape and the measurement, landing at `center.x -59 → 715.297` — off by 200–600px.

**Floating vs full-width.** `bar.floating` maps to `BarConfig.edgeMargin` (window margins, so the transparent gap is not clickable) and `BarConfig.cornerRadius` (plate radius). Measured on the real shell: **floating 1904px** (1920 − 2×8), **full-width 1920px**, radius 10 → 0. Fill is always `UI.Colors.background`, asserted against the palette's reported background value, and the verifier fails on any colour literal in the file.

**Three defects found by measuring rather than reading:**

1. **`"floating": false` silently did nothing.** A layer-shell surface is sized once, at map; the reader's verdict lands *after* first reference to it, so the bar mapped with the defaults and was never re-sized. `Bar.qml` now waits on `BarConfig.configured`. Critically, `configured` is **not** derived from `note` — `_take` assigns `note="none"` one statement before parsing `floating`, and QML delivers that synchronously, so the first attempt at the gate was a no-op. It is `_settled`, set in `_report()`.
2. **`destroy()` is deferred and a `Row` sizes off its children**, so a rebuilt zone was briefly as wide as the old widgets *and* the new ones. Each dying widget is now removed from the row before destruction.
3. **Every widget was constructed twice at startup**, because the entries arrive and then change again. `rebuild()` compares a signature first.

**Documented in place, not hidden:** overlapping wings when they exceed half the bar width is answered with a configuration edit, which is the point of having one. A plain `Item` outside any window does not re-polish after its zones rebuild, so the smoke plan's `BarSurface` entry proves *construction* only — measurement comes from surfaces created once settled, and `Bar.qml` is load-only in the plan because it owns surfaces. The real-shell launch is what proves it maps.

`verify-bar-surface.sh` (new, documented in AGENTS.md in the same commit — `verify-docs.sh` check (F) caught that omission) runs 36 assertions, mutation-tested. Full suite green: smoke, bar-config, widget-contract, bar-surface, launch-reload, palette, docs.

Live desktop: waybar 1333, hyprpaper 1335, swayosd 1347, swaync 1487 unchanged; no stray quickshell/dbus; `~/.config/quickshell` still absent; no `palette.json` written to the live theme dir.

