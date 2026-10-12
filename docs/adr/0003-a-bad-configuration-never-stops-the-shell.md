# A bad configuration never stops the shell

Status: accepted.

A bad configuration costs the user one missing widget. It never costs them
their desktop. An unrecognised widget name, a malformed entry, a widget that
fails to construct, or a file that is malformed as a whole are each handled,
each logged with the offending name, and each survived.

## Why this gets undone by accident

A reader sees a validator that returns `null` and logs a warning, and reads it
as an error path that was never finished — because in every other language a
warning next to a failed return *means* the caller should stop. Tightening it is
the obvious tidy-up, and it looks like robustness work. Four things make the
reflex wrong:

1. **The log line looks like a defect report.** `console.warn` is the right
   level — the user's file genuinely has a problem in it — so a reader scanning
   for warnings sees a page of them and reaches for the obvious fix: make the
   parser throw so the failure is loud and centralised. The result is a shell
   that does not start, which is exactly what this record forbids.
2. **A whole-file fallback makes the entry-level handling look redundant.**
   Malformed JSON already falls back to defaults cleanly, so a reader concludes
   that a missing widget name should do the same. It must not: that throws away
   eleven working widgets to report a twelfth's typo.
3. **Refusing the entry looks more consistent than skipping it.** The reader
   sees one rule ("configuration is never trusted") and applies it to the
   `path` key, deciding that a bad entry should abort rather than be skipped.
   But the two cases are not the same kind of thing. A `path` key is an
   *attempt* to make configuration into code, and refusing it loudly is right. A
   misspelled widget name is an *ordinary mistake*, and refusing the whole bar
   over one is what this decision exists to prevent.
4. **The tests still pass.** Every verifier here checks that valid things work
   and that bad things are reported; none of them checks that the shell stayed
   up, because "stayed up" looks like the absence of a crash rather than a
   behaviour. So there is nothing to object with when the fatal path appears —
   only a user with no bar.

## What "skip" means precisely

Skipping is not silence and it is not a default. Each of these produces its own
log line, naming what was wrong and where:

| What went wrong | Logged as |
| --- | --- |
| Entry is not an object | `reason=not-an-object got=string` |
| Object with no usable `type` | `reason=no-type got=undefined` |
| Name is not in the registry | `reason=unknown-widget type=… known=…` |
| Entry carries `path` or `file` | `reason=entry-cannot-locate-code key=…` |
| Widget's file will not load | `reason=widget-failed-to-load` |
| Widget will not construct | `reason=widget-failed-to-construct` |
| Zone is not a list | `reason=zone-not-a-list` |
| File is not valid JSON | `note=malformed-left-untouched`, defaults used |

The `known=` field on an unknown widget name lists the names that do exist. The
question a user actually has is "which one did I mean", and answering it in the
log is the difference between a one-second fix and an afternoon in the registry.

A skipped entry's **index** is in the line, because a zone that silently
re-flows after a skip looks like an off-by-one bug in the layout rather than the
skip that caused it.

## The whole-file case is different, and is not a special case of the above

When the file itself will not parse there is nothing trustworthy left to
salvage, so the built-in defaults are used and **the file is left byte-for-byte
untouched**. That last part is the whole reason this rule exists as written:
the file is malformed *because the user is editing it*, and rewriting it —
even with defaults, even "helpfully" — destroys the thing they are trying to
fix. Compare the palette, which does write its defaults out: it writes only on a
run that found *no file at all*, and never overwrites or repairs one. Both rules
exist for the same reason, which is that a user's half-finished file is work in
progress, not litter.

## Why the shell writes no configuration file

Unlike the palette, the shell does not create one on first run, and this is
deliberate. The palette has to be written: its whole purpose is to be a file a
theme manager will later replace, and without a file there is nothing to replace.
Configuration has no such need — the defaults are in `BarConfig` and are
authoritative until a file appears — and the real file is deployed by the NosArch
installer at v1.0.

Writing on first run would also create a race the palette does not have: whoever
starts first owns the file. A shell that started before the installer ran would
win, and the installed configuration would be silently replaced by whatever that
shell wrote.

Instead the effective configuration can be **printed** rather than written:
`NOSARCH_CONFIG_EMIT=1` makes the shell emit it as one JSON log line. A user
saves that to the path the verdict names. Nothing is created as a side effect of
starting, and the defaults still live in exactly one place.

## Consequences

- **Validation is a pure function.** `BarConfig.entriesFrom(rawZones, wantedZones)`
  maps a raw structure to the entries that will be built, so every rejection can
  be exercised without a file containing shapes no real user would type. What
  builds widgets only ever sees entries already known to be buildable.
- **The one thing validation cannot check is construction.** A file that loads
  and a name that resolves do not guarantee an object can be built — a widget may
  fail to supply a required member. So `BarZone` builds each widget directly
  rather than through a `Loader`: a `Loader` given an unbuildable component logs
  its own failure naming a file in this repository, which every other verifier
  reads as a defect. Skipping has to be loud in the shell's log and quiet in
  QML's, and only doing it by hand gets both.
- **Configuration cannot become code.** An entry's `type` is the only thing it
  decides, and it decides only a *name*, which the widget registry maps to a file
  inside `shell/widgets/`. An entry carrying `path` or `file` is refused with a
  named line rather than stripped, because a stripped key leaves the author
  believing it worked — and because this file is installer-deployed to every
  machine, so honouring it would turn a user-owned text file into a
  code-execution surface.
- **A widget's failure is worth exactly as much as the widget.** Nothing in the
  failure path is allowed to be fatal, including a widget that throws while
  building. The shell catches it, names it, and renders the rest.