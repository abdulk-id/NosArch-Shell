# 09: Per-widget options in configuration

**What to build:** Each widget declares its own options, and its configuration entry carries them, so a widget can be tuned without a code change. This is what the object-shaped entries from 07 exist for: the configuration file ships to every target machine, so options had to be anticipated in the format rather than added by breaking it later.

**Blocked by:** 08 (three zones, true centre, floating or full-width bar).

**Status:** resolved

- [ ] Each widget declares its own options, and receives them from its configuration entry.
- [ ] At least one widget's behaviour is tunable by configuration alone, with no code change.
- [ ] An option a widget does not recognise does not break the shell — it is skipped like any other bad entry.
Implemented on branch `09-per-widget-options`, merged to `feat/shell-foundation-and-bar`.

All of the mechanism sits on the widget contract in `shell/widgets/BarWidget.qml`, not in any widget, so the unknown-key rule is the same everywhere rather than re-implemented twelve times: `options` (the entry's settings, handed over by `BarZone` at construction as `options: entry.settings`), `optionDefaults` (what *this* widget takes, as name → default), `hasOptions`, `unrecognisedOptions`, and `optionValue(name)` — configuration's value, or the widget's own default. A widget **assigns** `optionDefaults` and reads only through `optionValue()`. A widget with nothing to tune declares nothing at all, exactly as one with no panel declares no `panelContent`.

**Two probed QML constraints decided the shape, both easy to get wrong silently:**

1. **`optionDefaults` must NOT be `readonly`.** A derived QML type can neither re-declare nor assign a property its base already has. Re-declaring **compiles clean and silently does nothing**; assigning to a base `readonly` one **fails to compile**. A readonly declaration would have made every widget's option list unreachable while still loading clean — precisely the failure mode the retired module base had, where the abstraction compiled and did nothing.
2. **One `var options` bag, not one property per option.** `Component.createObject()` ignores an unknown *named* property, but assigning one to a *live* object throws (`Cannot assign to non-existent property`). Per-option properties would therefore turn every option the shell does not know about into a runtime error from a perfectly ordinary configuration file.

**Unknown option keys: refused BY NAME, but the widget is still built.** This deliberately splits the `path`/`file` precedent: its *loudness* transfers, its *cost* does not. Refusing silently is what the precedent forbids, so the refusal names the key and lists what the widget **does** declare — "which did I mean" becomes answerable from the log. But refusing the entry buys no safety (the worst an unknown option can do is have no effect, whereas honouring `path` is a code-execution hole) and would break the shipped file on any machine running a shell *older* than its own configuration — the exact format break the object-shaped entries exist to prevent, arriving through a different door. Layer split: the reader still **keeps** unknown keys verbatim (ticket 07's decision, untouched); only a widget knows what it declares, so `BarZone` reports `widget.unrecognisedOptions` through `BarConfig`'s one logging path. An unknown option key is never fatal (ADR 0003).

Demonstrated on the clock: `{"type":"clock","timeFormat":"long"}` renders `h:mm:ss Ap tttt` versus `h:mm Ap`. With no options at all it renders exactly as ticket 07 left it. **No options added to any other widget** — that is tickets 12–15.

`scripts/verify-widget-options.sh`: 9 static checks; the option reaches the widget end-to-end from a real file; **two runs of the unmodified tree against two different files produce different rendered text** (a mechanism that delivered a value but changed no behaviour would pass the first check and fail this one); and the failure policy for both a misspelt key and an option no widget declares.

**Mutation-testing the harness found a real defect in the harness itself:** a mutation making an unrecognised option fatal initially reported PASS, because a stray `policy_rc=0` discarded the failure policy's result. Fixed and noted in the script. A second weak check — "refusal appears at least once" — passed against misattributed and repeated refusals, and was replaced with "every refusal names the entry that actually carried the key". Five mutations now all caught.

**Known limitation, recorded here rather than fixed:** options apply at **launch**, not on edit. `BarConfig`'s `FileView` never enables watching, and `BarZone._signatureOf` compares only widget *types*, so changing `timeFormat` takes effect on reload rather than live. That sits within ticket 10's hot-plug scope, so neither was touched.

Three further QML traps recorded in `quickshell-api-notes.md` (§7–9), one of them self-inflicted: `readonly property var LONG_FORMAT` is a *load* error, since QML property names cannot begin with an uppercase letter.

Full suite green (all nine verifiers). `verify-docs.sh` check (F) correctly failed until the new script was documented in AGENTS.md.

Live desktop: waybar 1333, hyprpaper 1335, swayosd 1347, swaync 1487 unchanged; `~/.config/quickshell` still absent; no stray processes; `.qmlls.ini` never staged.

