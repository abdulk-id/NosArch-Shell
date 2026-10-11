pragma Singleton

import QtQuick

import Quickshell
import Quickshell.Io

// Colors — the shell's single palette, file-backed (ticket 04).
//
// WHERE THE COLOURS COME FROM
//
//   ~/.local/share/nosarch/current-theme/palette.json — the EXISTING NosArch
//   theme directory, which today holds wallpapers only and has no palette of
//   any kind. The path is resolved from HOME on purpose: it is not a Quickshell
//   state directory, so Quickshell.statePath() is the wrong home for it. The
//   palette lives beside the wallpapers so that a theme change updates the
//   shell.
//
//   The file is a flat JSON object with one colour per key:
//
//     { "background": "#1D1D20", "backgroundSurface": "#2E2E32", ... }
//
//   Keys the file does not mention keep their defaults; a value that is not a
//   colour falls back to the default for that key (with a named log line).
//   The shell never writes to a file it did not create on this run.
//
// THE FOUR GUARANTEES (spec, "Palette")
//
//   * no file        → the built-in defaults are used (a fresh install still
//                      renders correctly).
//   * no file, first run → the defaults are written out, so there is something
//                      to edit.
//   * existing file  → never overwritten.
//   * malformed file → defaults, and the file is left untouched.
//
// WHY TWO FILEVIEWS
//
//   A JsonAdapter deserializes when its file is loaded, and a malformed file
//   makes it log "Failed to deserialize json". To keep a malformed palette a
//   silent, log-clean fallback, an adapter-less "sniffer" FileView reads the
//   content first and only approves a reload when it structurally looks like a
//   JSON object. The palette FileView (adapter attached, preload: false,
//   blockLoading: false) then performs exactly one load — of content the
//   sniffer approved.
//
// DEFAULTS LIVE IN EXACTLY ONE PLACE
//
//   The JsonAdapter property declarations below. The public properties are
//   seeded from them before any file is loaded, and replaced by file values
//   where the file provides a valid one.
//
// CANONICAL NAMES
//
//   The spec's four canonical colours map to: accent, background, foreground,
//   alertRed. ("alert" is spelled alertRed in the code; it is NOT renamed —
//   the promise is that widgets use the one canonical name rather than
//   inventing their own, and renaming would break every widget.) Four
//   supporting names complete the palette: backgroundSurface,
//   backgroundHover, foregroundSecondary, foregroundMuted. The palette file
//   exposes exactly these eight keys.
QtObject {
    id: colors

    // ---- the palette widgets bind to --------------------------------------
    // Seeded from the adapter's declared defaults in _startup(), replaced by
    // file values in _merge(). Nothing else writes them.
    property string background: ""
    property string backgroundSurface: ""
    property string backgroundHover: ""
    property string foreground: ""
    property string foregroundSecondary: ""
    property string foregroundMuted: ""
    property string alertRed: ""
    property string accent: ""

    // ---- load verdict (one pair of log lines per run) ----------------------
    // Written once per run by the load handlers below; read by the smoke
    // readout and the verification script.
    property string source: "default"   // "file" when values came from the file
    property int keysFromFile: 0        // how many of the 8 the file overrode
    property string note: ""            // machine-readable outcome tag

    property bool _merged: false
    property int _keysFromFile: 0

    // ---- the file -----------------------------------------------------------
    // Empty themeDir means HOME was not set; the empty path simply fails to
    // load and the shell runs on defaults.
    readonly property string themeDir: {
        const home = Quickshell.env("HOME")
        return home !== null ? home + "/.local/share/nosarch/current-theme" : ""
    }
    readonly property string palettePath: colors.themeDir + "/palette.json"

    // The sniffer: reads the file's raw text. No adapter, so a malformed file
    // never reaches a JsonAdapter and never logs a deserialize warning.
    // (Typed properties, not anonymous children: a QtObject has no default
    // property for children to attach to.)
    property FileView sniffer: FileView {
        id: paletteSniffer
        path: colors.palettePath
        blockLoading: true
        printErrors: false   // every outcome is expected and reported below

        onLoaded: {
            const t = paletteSniffer.text().trim()
            if (t.startsWith("{") && t.endsWith("}")) {
                paletteFile.reload()          // approved: deserialize it
            } else {
                colors.note = "malformed-left-untouched"
                console.warn("nosarch-shell ▸ PALETTE " + colors.palettePath +
                    " is malformed — using the built-in defaults; the file was left untouched")
                colors._report()
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                // First run: write the defaults out so there is something to
                // edit. The adapter still holds its declared defaults (the
                // file was never loaded), so writeAdapter() writes exactly
                // those. waitForJob() lands the write before the process can
                // quit — nothing depends on the saved() signal.
                paletteFile.writeAdapter()
                paletteFile.waitForJob()
                colors.note = "no-file-wrote-defaults"
                console.info("nosarch-shell ▸ PALETTE no palette file at " + colors.palettePath +
                    " — wrote the built-in defaults; edit that file to re-theme the shell")
            } else {
                colors.note = "unreadable-left-untouched"
                console.warn("nosarch-shell ▸ PALETTE " + colors.palettePath +
                    " could not be read (error " + error + ") — using the built-in defaults; the file was left untouched")
            }
            colors._report()
        }
    }

    // The palette: the adapter is attached from the start (so a load
    // deserializes into it), but preload: false + blockLoading: false mean it
    // never loads until the sniffer approves the content.
    property FileView store: FileView {
        id: paletteFile
        path: colors.palettePath
        preload: false
        blockLoading: false
        printErrors: false

        JsonAdapter {
            // The known-good default palette — the only place the default
            // literals are written (spec: "a default palette held in the shell
            // code — the current colour values").
            property string background: "#1D1D20"
            property string backgroundSurface: "#2E2E32"
            property string backgroundHover: "#434346"
            property string foreground: "#FFFFFF"
            property string foregroundSecondary: "#9A9A9C"
            property string foregroundMuted: "#444B6A"
            property string alertRed: "#FF6666"
            property string accent: "#6799e4"
        }

        onLoaded: {
            if (colors._merged) {
                return
            }
            colors._merged = true
            // text() is the documented flush: it makes the adapter's loaded
            // values available synchronously (Quickshell 0.3.2 API notes,
            // JsonAdapter timing).
            paletteFile.text()
            colors.source = "file"
            colors._merge()
            colors._report()
        }
        onLoadFailed: (error) => {
            // Defensive: the file vanished or became unreadable between the
            // sniffer's read and this load. Defaults stay; no write — the
            // sniffer owns the first-run write.
            if (colors._merged) {
                return
            }
            colors._merged = true
            colors.note = "unreadable-left-untouched"
            console.warn("nosarch-shell ▸ PALETTE " + colors.palettePath +
                " became unreadable while loading — using the built-in defaults")
            colors._report()
        }
    }

    Component.onCompleted: colors._startup()

    function _startup(): void {
        // Seed the public properties from the adapter's declared defaults.
        // paletteFile has not loaded at this point (it never loads before the
        // sniffer approves), so the adapter holds exactly its QML defaults —
        // the literals above are the single source of the default values.
        colors.background = paletteFile.adapter.background
        colors.backgroundSurface = paletteFile.adapter.backgroundSurface
        colors.backgroundHover = paletteFile.adapter.backgroundHover
        colors.foreground = paletteFile.adapter.foreground
        colors.foregroundSecondary = paletteFile.adapter.foregroundSecondary
        colors.foregroundMuted = paletteFile.adapter.foregroundMuted
        colors.alertRed = paletteFile.adapter.alertRed
        colors.accent = paletteFile.adapter.accent
    }

    // Merge the loaded file over the seeded defaults. The adapter holds the
    // file's value for keys the file mentions and its declared default for
    // keys it does not — so a value that differs from the seeded default IS a
    // file value, and a key the file omits keeps its default untouched.
    function _merge(): void {
        colors._keysFromFile = 0
        colors.background = colors._take("background", paletteFile.adapter.background, colors.background)
        colors.backgroundSurface = colors._take("backgroundSurface", paletteFile.adapter.backgroundSurface, colors.backgroundSurface)
        colors.backgroundHover = colors._take("backgroundHover", paletteFile.adapter.backgroundHover, colors.backgroundHover)
        colors.foreground = colors._take("foreground", paletteFile.adapter.foreground, colors.foreground)
        colors.foregroundSecondary = colors._take("foregroundSecondary", paletteFile.adapter.foregroundSecondary, colors.foregroundSecondary)
        colors.foregroundMuted = colors._take("foregroundMuted", paletteFile.adapter.foregroundMuted, colors.foregroundMuted)
        colors.alertRed = colors._take("alertRed", paletteFile.adapter.alertRed, colors.alertRed)
        colors.accent = colors._take("accent", paletteFile.adapter.accent, colors.accent)
        colors.keysFromFile = colors._keysFromFile
    }

    // One key: use the file's value when it is a colour and differs from the
    // default; otherwise keep the default (loudly, when the file clearly
    // carried something unusable).
    function _take(key: string, fileValue: string, defaultValue: string): string {
        if (fileValue !== "" && fileValue !== defaultValue && colors._isColor(fileValue)) {
            colors._keysFromFile++
            return fileValue
        }
        if (fileValue !== "" && fileValue !== defaultValue) {
            console.warn("nosarch-shell ▸ PALETTE key " + key + " value '" + fileValue +
                "' is not a supported colour — kept default " + defaultValue)
        }
        return defaultValue
    }

    // Hex colours (#rgb, #rgba, #rrggbb, #rrggbbaa) plus "transparent".
    function _isColor(v: string): bool {
        return v === "transparent" || /^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v)
    }

    function _report(): void {
        console.info("nosarch-shell ▸ PALETTE verdict source=" + colors.source +
            " file=" + colors.palettePath +
            " keys-from-file=" + colors.keysFromFile + "/8" +
            (colors.note !== "" ? " note=" + colors.note : ""))
        console.info("nosarch-shell ▸ PALETTE values background=" + colors.background +
            " backgroundSurface=" + colors.backgroundSurface +
            " backgroundHover=" + colors.backgroundHover +
            " foreground=" + colors.foreground +
            " foregroundSecondary=" + colors.foregroundSecondary +
            " foregroundMuted=" + colors.foregroundMuted +
            " alertRed=" + colors.alertRed +
            " accent=" + colors.accent)
    }
}
