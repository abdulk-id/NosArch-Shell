pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io

import "../widgets" as Widgets

// BarConfig — the bar's contents, read from a user-owned JSON file (ticket 07).
//
// WHAT THIS IS
//
//   Everything about what appears in the bar comes from a JSON file rather
//   than from QML. Reordering widgets, removing one and adding one are
//   configuration edits. This type owns the four steps between the file and the
//   bar: where the file is, what shape it has, what in it is usable, and what
//   to say about whatever was not.
//
// WHERE THE FILE IS
//
//     $XDG_CONFIG_HOME/quickshell/nosarch/shell.json
//     (defaulting to ~/.config/quickshell/nosarch/shell.json)
//
//   It is ABSOLUTE on purpose. It is not resolved against the shell's own
//   directory, the directory this QML file lives in, or anything else in the
//   tree: resolving it relatively would appear to work during development and
//   silently break the moment the shell is deployed somewhere else, which is
//   exactly the class of bug that only appears on a user's machine. It also
//   means the configuration survives the shell being moved.
//
//   It is user-owned and NOT tracked in git, because the NosArch installer
//   deploys it to target machines. During development the shell runs from the
//   repository while configuration is read from this final absolute location —
//   that asymmetry is deliberate and must not be "fixed" by making it relative.
//
//   NOSARCH_SHELL_CONFIG overrides the whole path. That exists so a test can
//   point the reader somewhere disposable without touching a real
//   ~/.config — every verification script sets it, or redirects HOME, or both.
//
// WHY A PLAIN TEXT READ AND NOT A JsonAdapter
//
//   The schema's shape IS its content: three zone lists whose entries name
//   whatever widgets exist. A JsonAdapter deserializes into *declared*
//   properties, so using one would mean declaring the configuration's shape as
//   QML properties — putting the layout back into the shell code, which is the
//   thing this file exists to remove, and breaking every time a widget is
//   added. So the file is read as text and parsed, and the meaning is applied
//   by the code below. That also sidesteps the 0.3.2 adapter timing trap: at
//   Component.onCompleted an adapter still holds its QML defaults, not the
//   file's values (see quickshell-api-notes.md).
//
// THE SCHEMA
//
//   {
//     "bar": {
//       "floating": true,
//       "zones": {
//         "left":   [ { "type": "clock" }, … ],
//         "center": [ { "type": "clock" } ],
//         "right":  [ { "type": "clock" } ]
//       }
//     }
//   }
//
//   Entries are OBJECTS carrying at least a `type`, never bare name strings,
//   even though a bare string would be shorter today. The file ships to every
//   target machine, so per-widget options have to be anticipated in the format
//   rather than added later by breaking it — a format break would mean a
//   migration on every machine. Ticket 09 is what starts reading the extra keys.
//
//   The schema is deliberately minimal: only what the bar needs, keys added as
//   features require them.
//
// CONFIGURATION CANNOT LOCATE CODE
//
//   An entry's `type` is the ONLY thing configuration gets to influence, and it
//   influences only which NAME is looked up. Resolution goes through the widget
//   registry, which maps a name to a file that lives in shell/widgets/ —
//   configuration never names a file, so a user-owned text file cannot become a
//   code-execution surface. An entry carrying a `path` or `file` key is REFUSED
//   rather than quietly stripped, because a user who wrote one would otherwise
//   believe it worked. Refusing loudly costs one missing icon; honouring it
//   would cost an arbitrary-code hole in a file the installer ships.
//
// THE FAILURE POLICY (spec, "Failure policy")
//
//   A bad configuration never stops the shell. An unrecognised widget name, a
//   malformed entry, or a widget that fails to construct is logged with the
//   offending name and skipped; everything valid still renders. A file that is
//   malformed as a whole falls back to the built-in defaults and is left
//   byte-for-byte alone.
//
//   This is deliberate for the shipped case. This shell runs on other people's
//   machines: bad code shipped by accident, or a configuration that disagrees
//   with the installed version, must cost one missing icon rather than the
//   whole desktop. A shell that refuses to start on one bad line also teaches
//   its users to edit configuration defensively, which is worse.
//
//   Nothing here is ever written back to the file. The shell creates no
//   configuration file: unlike the palette, there is no reason for it to, since
//   the defaults are in this file and the installer deploys the real one.
//   `NOSARCH_CONFIG_EMIT=1` prints the effective configuration as one JSON log
//   line so there is something to save; see scripts/verify-bar-config.sh.
Singleton {
    id: barConfig

    // ------------------------------------------------------------------ path

    // Absolute, and never relative to the shell's own source tree. See the
    // header: resolving it relatively would work in development and break on a
    // deployed machine.
    readonly property string configFile: barConfig._resolvePath()

    function _resolvePath(): string {
        // The override wins over everything, so a test can point the reader at
        // a disposable file without editing anything and without a real one.
        const override = Quickshell.env("NOSARCH_SHELL_CONFIG")
        if (override !== null && override !== "") {
            return override
        }
        const xdg = Quickshell.env("XDG_CONFIG_HOME")
        const base = (xdg !== null && xdg !== "")
            ? xdg
            : ((Quickshell.env("HOME") || "") + "/.config")
        return base + "/quickshell/nosarch/shell.json"
    }

    // ------------------------------------------------------------------ shape

    // The three zones, in the order the spec names them. A fixed list, not
    // whatever keys the file happens to have: an unknown zone name is ignored
    // rather than becoming a fourth zone nothing renders.
    readonly property var zoneNames: ["left", "center", "right"]

    // Entry keys configuration is never allowed to carry. Refused, not
    // stripped — see "CONFIGURATION CANNOT LOCATE CODE" above.
    readonly property var rejectedEntryKeys: ["path", "file"]

    // THE BUILT-IN DEFAULTS, AND THE ONLY PLACE THEY ARE WRITTEN.
    //
    // Only widgets that exist in the registry are named here: with the clock as
    // the sole contract widget so far, the defaults place the clock in the
    // centre and leave the wings empty. Each widget's own ticket adds its name
    // in its natural place, and this stays the single source. Floating by
    // default matches spec story 12.
    readonly property var defaultConfiguration: ({
        "bar": {
            "floating": true,
            "zones": {
                "left": [],
                "center": [{ "type": "clock" }],
                "right": []
            }
        }
    })

    // -------------------------------------------------------------- verdicts

    property string source: "defaults"      // "file" when the file was usable
    property string note: "pending"          // machine-readable outcome tag
    property bool floating: true             // consumed by ticket 08
    property var _entries: []                // validated, in file order
    property int _skipped: 0
    property var _loaded: false

    // ---------------------------------------------------- floating geometry
    //
    // What `floating` MEANS, declared beside the flag it comes from.
    //
    // Two separate objects need these numbers: the window, which takes them as
    // its margins, and the plate, which takes them as its corner radius. If
    // each held its own copy they could disagree, and a bar whose window insets
    // by 8 while its plate insets by 5 is visibly wrong in a way neither file's
    // own checks would catch. One answer, read from both — that is the whole
    // reason these live here rather than beside either consumer.
    //
    // These are SHELL constants, not configuration. The schema stays minimal:
    // `floating` is the one switch, and a user who wants a different inset gets
    // it by editing two numbers in one place, not by a key that would have to
    // be validated, defaulted and documented on every target machine.
    property int floatingMargin: 8
    property int floatingRadius: 10

    // The derived answers, so neither consumer has to restate the branch.
    readonly property int edgeMargin: barConfig.floating ? barConfig.floatingMargin : 0
    readonly property int cornerRadius: barConfig.floating ? barConfig.floatingRadius : 0

    // Whether the verdict has been reached at all — and, more usefully, whether
    // it has been reached COMPLETELY. This exists for the BAR, not for a log
    // reader.
    //
    // It must NOT be derived from `note`. `note` is assigned early in each
    // outcome path — before `floating` has been read out of the file, in fact
    // before most of the verdict is known — and QML delivers a property change
    // to a binding synchronously. Gating the bar's window on `note` therefore
    // created it at the exact moment the reader said "none", which is one
    // statement before the reader had read `floating`: the window mapped with
    // the built-in default's margins, a layer-shell surface is not given a
    // second size, and `"floating": false` in the user's file silently did
    // nothing. That is what `_settled` is for, and it is set in `_report()`,
    // which `_setEntries` calls once the whole verdict is in hand.
    //
    // A layer-shell surface has its size negotiated once, when it maps, so
    // waiting is what makes the bar come up the width the user actually asked
    // for. See Bar.qml.
    property bool _settled: false
    readonly property bool configured: barConfig._settled

    readonly property int skippedCount: barConfig._skipped
    readonly property int entryCount: barConfig._entries.length

    // -------------------------------------------------------------- the file

    // No adapter: a malformed file must not reach a deserializer and log a
    // warning naming it. The text is parsed below, where a parse failure is an
    // outcome this type reports rather than an error it suffers. blockLoading
    // means the verdict is settled during construction, so nothing can read a
    // half-configured bar.
    property FileView store: FileView {
        id: store
        path: barConfig.configFile
        blockLoading: true
        printErrors: false   // every outcome is expected, and all are reported

        onLoaded: barConfig._apply(store.text())
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                barConfig.note = "no-file"
                console.info("nosarch-shell ▸ CONFIG no configuration file at " +
                    barConfig.configFile + " — using the built-in defaults; " +
                    "set NOSARCH_CONFIG_EMIT=1 to print one to save")
            } else {
                barConfig.note = "unreadable-left-untouched"
                console.warn("nosarch-shell ▸ CONFIG " + barConfig.configFile +
                    " could not be read (error " + error + ") — using the built-in " +
                    "defaults; the file was left untouched")
            }
            barConfig._useDefaults()
        }
    }

    function _apply(text: string): void {
        if (barConfig._loaded) {
            return   // a second load (the watched file changed) is handled below
        }
        barConfig._loaded = true
        const trimmed = (text || "").trim()
        if (trimmed === "") {
            barConfig.note = "malformed-left-untouched"
            console.warn("nosarch-shell ▸ CONFIG " + barConfig.configFile +
                " is empty — using the built-in defaults; the file was left untouched")
            barConfig._useDefaults()
            return
        }
        let raw
        try {
            raw = JSON.parse(trimmed)
        } catch (e) {
            // The whole file is malformed. That is a different failure from one
            // bad entry, and it is answered differently: there is nothing
            // trustworthy left to salvage, so the built-in defaults are used and
            // the file is left exactly as the user left it. Writing over it
            // would destroy the thing they are trying to fix.
            barConfig.note = "malformed-left-untouched"
            console.warn("nosarch-shell ▸ CONFIG " + barConfig.configFile +
                " is not valid JSON (" + e + ") — using the built-in defaults; " +
                "the file was left untouched")
            barConfig._useDefaults()
            return
        }
        if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
            barConfig.note = "malformed-left-untouched"
            console.warn("nosarch-shell ▸ CONFIG " + barConfig.configFile +
                " is not a JSON object — using the built-in defaults; the file was " +
                "left untouched")
            barConfig._useDefaults()
            return
        }
        barConfig._take(raw)
    }

    // The file parsed. Anything wrong from here on is a bad ENTRY, which costs
    // one widget rather than the whole bar.
    function _take(raw: var): void {
        barConfig.source = "file"
        barConfig.note = "none"

        const bar = (raw["bar"] === undefined || raw["bar"] === null) ? {} : raw["bar"]
        if (typeof bar !== "object" || Array.isArray(bar)) {
            console.warn("nosarch-shell ▸ CONFIG `bar` is not an object in " +
                barConfig.configFile + " — using the default bar")
            barConfig._useDefaults()
            return
        }

        // `floating` belongs to ticket 08, but it is parsed and validated here
        // because this type owns the schema. A non-boolean is kept out rather
        // than coerced: `false` and `0` and `"no"` are three different answers
        // and guessing which one was meant is how a toggle ends up inverted.
        if (bar["floating"] === undefined) {
            barConfig.floating = barConfig.defaultConfiguration["bar"]["floating"]
        } else if (typeof bar["floating"] === "boolean") {
            barConfig.floating = bar["floating"]
        } else {
            console.warn("nosarch-shell ▸ CONFIG `bar.floating` is " +
                typeof bar["floating"] + ", not true/false, in " + barConfig.configFile +
                " — keeping the default " +
                barConfig.defaultConfiguration["bar"]["floating"])
            barConfig.floating = barConfig.defaultConfiguration["bar"]["floating"]
        }

        const zones = bar["zones"]
        if (zones === undefined || zones === null || typeof zones !== "object"
                || Array.isArray(zones)) {
            barConfig.note = "no-zones-in-file"
            console.warn("nosarch-shell ▸ CONFIG `bar.zones` is missing or not an object in " +
                barConfig.configFile + " — every zone is empty; the built-in defaults " +
                "would be used instead")
            barConfig._setEntries(barConfig.entriesFrom({}))
            return
        }
        barConfig._setEntries(barConfig.entriesFrom(zones))
    }

    function _useDefaults(): void {
        const d = barConfig.defaultConfiguration
        barConfig.source = "defaults"
        barConfig.floating = d["bar"]["floating"]
        barConfig._setEntries(barConfig.entriesFrom(d["bar"]["zones"]))
    }

    // ---------------------------------------------------------- validation
    //
    // A pure function from a raw zones object to the entries that will
    // actually be built: public, and the seam the smoke test drives with
    // shapes no real file needs to contain. `wantedZones` defaults to the bar's
    // three zones; passing a different list is how a caller validates a zones
    // map that is not the bar's.
    //
    // Everything it can reject, it rejects here, with a named log line, so the
    // thing that builds widgets only ever sees entries that are known to be
    // buildable.

    function entriesFrom(rawZones: var, wantedZones: var): var {
        const names = wantedZones === undefined ? barConfig.zoneNames : wantedZones
        const out = []
        barConfig._skipped = 0
        for (let z = 0; z < names.length; z++) {
            const zone = names[z]
            const list = rawZones[zone]
            if (list === undefined || list === null) {
                continue                      // an absent zone is an empty zone
            }
            if (!Array.isArray(list)) {
                barConfig._skip(zone, -1, { reason: "zone-not-a-list", got: typeof list })
                continue
            }
            for (let i = 0; i < list.length; i++) {
                const entry = barConfig._validate(zone, i, list[i])
                if (entry !== null) {
                    out.push(entry)
                }
            }
        }
        return out
    }

    // One entry, or null plus a named log line. The order of the checks is the
    // order of the promises: shape first (so the later checks can read a field
    // safely), then the no-code rule, then the required `type`, then whether
    // that name resolves at all.
    function _validate(zone: string, index: int, raw: var): var {
        if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
            return barConfig._skip(zone, index, { reason: "not-an-object", got: typeof raw })
        }
        for (let k = 0; k < barConfig.rejectedEntryKeys.length; k++) {
            const key = barConfig.rejectedEntryKeys[k]
            if (Object.keys(raw).indexOf(key) !== -1) {
                return barConfig._skip(zone, index, {
                    reason: "entry-cannot-locate-code", key: key
                })
            }
        }
        if (typeof raw["type"] !== "string" || raw["type"] === "") {
            return barConfig._skip(zone, index, {
                reason: "no-type", got: typeof raw["type"]
            })
        }
        const name = raw["type"]
        if (!Widgets.WidgetRegistry.isKnown(name)) {
            // The names that DO exist are in the line: "which widget did you
            // mean" is the question the user actually has, and it is answered
            // by reading the log rather than by opening the registry.
            return barConfig._skip(zone, index, {
                reason: "unknown-widget", type: name,
                known: Widgets.WidgetRegistry.names().join(",")
            })
        }
        const component = barConfig.componentFor(name)
        if (component === null || component.status !== Component.Ready) {
            return barConfig._skip(zone, index, { reason: "widget-failed-to-load", type: name })
        }
        // The original entry object, deep-copied, so the per-widget settings
        // ticket has a stable record to read and mutating one cannot reach
        // another.
        return {
            zone: zone,
            index: index,
            type: name,
            settings: barConfig._settingsOf(raw),
            original: JSON.parse(JSON.stringify(raw))
        }
    }

    // Everything on the entry except the widget name. Unknown keys are kept:
    // the file may name an option no shipped widget reads yet, and refusing it
    // would make the format hostile to the very future it was designed for.
    function _settingsOf(raw: var): var {
        const out = {}
        const keys = Object.keys(raw)
        for (let i = 0; i < keys.length; i++) {
            if (keys[i] !== "type") {
                out[keys[i]] = raw[keys[i]]
            }
        }
        return out
    }

    // The one place a skip is logged, so every failure reads the same way and
    // a user can grep one pattern. Returns null, which is what the caller
    // pushes nothing for.
    function _skip(zone: string, index: int, detail: var): var {
        barConfig._skipped++
        const where = "bar.zones." + zone + "[" + index + "]"
        let line = "nosarch-shell ▸ CONFIG skipped " + where
        const keys = Object.keys(detail)
        for (let i = 0; i < keys.length; i++) {
            line += " " + keys[i] + "=" + detail[keys[i]]
        }
        console.warn(line + " — skipped; the rest of the bar is unaffected")
        return null
    }

    // Same shape as a configuration skip, but reported from wherever a widget
    // was actually built: the one failure validation cannot see, because it
    // only happens when an object is created.
    function skipAt(where: string, index: int, detail: var): var {
        let line = "nosarch-shell ▸ CONFIG skipped " + where + "[" + index + "]"
        const keys = Object.keys(detail)
        for (let i = 0; i < keys.length; i++) {
            line += " " + keys[i] + "=" + detail[keys[i]]
        }
        console.warn(line + " — skipped; the rest of the bar is unaffected")
        return null
    }

    // A configuration option that the widget it was written for does not
    // declare (ticket 09). Reported through the same CONFIG stream as every
    // other configuration problem, because that is the point of there being one
    // stream: a user greps one pattern and finds everything wrong with their
    // file.
    //
    // WHY THE WIDGET IS STILL BUILT — the decision, and what it costs
    //
    //   Not silent, like `path`/`file` is not silent: a user who wrote an
    //   option their shell does not know must be TOLD, or they believe it
    //   worked. That is the whole of the precedent, and it is honoured here.
    //
    //   What is NOT honoured is the rest of it. `path`/`file` are refused
    //   outright rather than stripped because HONOURING them would let a
    //   user-owned text file choose which code runs — refusing the entry is
    //   the only safe answer there. No such danger exists in an option key: the
    //   worst an unrecognised one can do is have no effect, which is the same
    //   thing that happens if it is ignored. So refusing the ENTRY here would
    //   buy no safety at all, and would cost the user a working widget.
    //
    //   It would also break the file for every machine, which is the decisive
    //   argument. This file is deployed by the installer to every target
    //   machine, and a target may be running a shell OLDER than the
    //   configuration written for it. Under "refuse the entry", naming an
    //   option a future release adds would delete the widget entirely on every
    //   older machine — the exact format break the object-shaped entries
    //   (ticket 07) exist to prevent, arriving through a different door.
    //
    //   So: the KEY is refused and named; the WIDGET is kept. A bad option
    //   costs one key, never one widget, and never the bar.
    function reportUnrecognisedOption(where: string, index: int, type: string,
            key: string, declared: var): void {
        let line = "nosarch-shell ▸ CONFIG refused option " + where + "[" + index + "]"
            + " type=" + type + " key=" + key
            + " declared=" + (Array.isArray(declared) && declared.length > 0
                ? declared.join(",") : "none")
        console.warn(line + " — not applied; the widget is shown with its "
            + "declared defaults")
    }

    function _setEntries(entries: var): void {
        barConfig._entries = entries
        barConfig._report()
    }

    // ------------------------------------------------------- the public read

    // The valid entries for one zone, in the file's own order. Unknown zone
    // names get an empty list rather than an error — the caller is drawing a
    // bar, not validating a file.
    function entriesFor(zone: string): var {
        const out = []
        for (let i = 0; i < barConfig._entries.length; i++) {
            if (barConfig._entries[i].zone === zone) {
                out.push(barConfig._entries[i])
            }
        }
        return out
    }

    // The Component for a configuration name, or null. The ONLY resolution in
    // the bar: it asks the registry, which owns the name→file map. There is no
    // second way for configuration to become a widget.
    function componentFor(type: string): Component {
        return Widgets.WidgetRegistry.componentFor(type)
    }

    // ------------------------------------------------------------- reporting

    function _report(): void {
        // The verdict is complete from here on — `floating`, the entries and the
        // skip count are all in hand. Anything waiting on the whole answer (the
        // bar's window, which can only be sized once) is released at this point
        // and not one statement earlier; see `configured` above.
        barConfig._settled = true

        let entries = 0
        for (let z = 0; z < barConfig.zoneNames.length; z++) {
            const zone = barConfig.zoneNames[z]
            const list = barConfig.entriesFor(zone)
            const types = []
            for (let i = 0; i < list.length; i++) {
                types.push(list[i].type)
            }
            entries += list.length
            console.info("nosarch-shell ▸ CONFIG zone " + zone + " count=" + list.length +
                " types=" + (types.length === 0 ? "" : types.join(",")))
        }
        console.info("nosarch-shell ▸ CONFIG verdict source=" + barConfig.source +
            " file=" + barConfig.configFile +
            " zones=" + barConfig.zoneNames.length +
            " entries=" + entries +
            " skipped=" + barConfig._skipped +
            " note=" + barConfig.note)

        // The effective configuration as one JSON line, on request. This is how
        // a user gets a file to edit without a write-out the shell performs on
        // its own: it prints, it does not create anything.
        const emit = Quickshell.env("NOSARCH_CONFIG_EMIT")
        if (emit === "1" || emit === "true") {
            console.info("nosarch-shell ▸ CONFIG effective " +
                JSON.stringify(barConfig.effectiveConfiguration()))
        }
    }

    // The configuration the shell is ACTUALLY running: the file's settings
    // with every unusable entry removed, so what it says is what the bar shows
    // rather than what the user hoped for.
    function effectiveConfiguration(): var {
        const zones = {}
        for (let z = 0; z < barConfig.zoneNames.length; z++) {
            const zone = barConfig.zoneNames[z]
            const list = barConfig.entriesFor(zone)
            const originals = []
            for (let i = 0; i < list.length; i++) {
                originals.push(list[i].original)
            }
            zones[zone] = originals
        }
        return { "bar": { "floating": barConfig.floating, "zones": zones } }
    }

    // The built-in defaults, rendered as the text a user would save. One line,
    // no side effects — see the header on why the shell does not write this
    // itself.
    function defaultConfigurationText(): string {
        return JSON.stringify(barConfig.defaultConfiguration, null, 2)
    }
}