# 05: Vocabulary, recorded decisions, and restored repo conventions

**What to build:** The design decisions this spec settles are recorded where a future reader will find them, so a person tidying up the code later does not silently undo them. Concretely: a glossary covering bar, zone, widget, panel, service, palette and idle-lock inhibit, each with the terms to avoid — the word "module" is explicitly retired because it currently means three different things in this codebase and is a direct cause of the unapplied abstraction. Two decision records: the service and widget boundary, because a future reader seeing presentation removed from services will be tempted to move it back; and the panel architecture, because abandoning framework popups looks like a mistake without knowing why.

**Blocked by:** 03 (smoke-test entrypoint).

**Status:** resolved

- [ ] A glossary exists at the repo root covering bar, zone, widget, panel, service, palette and idle-lock inhibit.
- [ ] Each glossary entry states the terms to avoid, not just the definition.
- [ ] The word "module" is explicitly retired, with a note that it currently means three different things in this codebase and caused the unapplied abstraction.
- [ ] A decision record captures the service and widget boundary, including the reasoning that a future reader would otherwise undo.
- [ ] A decision record captures the panel architecture, including that abandoning framework popups is deliberate and why.
- [ ] The Hyprland-only trade-off for the panel focus model is recorded as a deliberate decision, not left implicit.
- [ ] The decision that the idle-lock semantics are inverted relative to their names is documented where the helper is used.
Implemented on branch `05-vocabulary-and-recorded-decisions`, merged to `feat/shell-foundation-and-bar` (AGENTS.md conflict resolved by hand — see below).

`GLOSSARY.md` follows `.agents/skills/domain-modeling/GLOSSARY-FORMAT.md`: title, `## Language`, one definition plus an `_Avoid_:` line per term. Terms: bar, zone, widget, panel, service, palette, idle-lock inhibit, plus **widget registry** (added deliberately — the naming convention hangs off it) and the retired **module**.

The retirement entry names the three senses, all verified real in the tree: (1) the twelve bar widgets in `shell/topisland/modules/`; (2) `components/TopIslandModule.qml`, the base class, extended by **one widget of twelve** (`VolumeModule.qml`); (3) QML's own sense of a `qmldir`-bearing directory of types, which `services/`, `components/` and `shell/ui/` genuinely are while `shell/topisland/modules/` has no `qmldir` and is not one.

`docs/adr/0001-services-expose-state-never-presentation.md` and `docs/adr/0002-panels-are-overlay-surfaces-not-popups.md`, numbered from 0001. ADR 0002 carries the Hyprland trade as its own section, marked as a deliberate trade rather than an oversight.

**Honesty over assertion.** ADR 0001 is marked *in progress* and names all four services still publishing glyphs plus the tickets that will move them — describing the intended end state as achieved would be a falsehood. ADR 0002 is marked *not yet implemented* and names the files holding framework popups.

**A fabricated number, caught and corrected.** The ADR initially said the service-glyph consumers are "six call sites". They are **thirteen** — seven in `shell/`, three in `smoke.qml`, three in `testing/ServiceReadout.qml`. The first grep was scoped to `shell/ components/ testing/` and missed `smoke.qml`. A check now locks the count to the tree, precisely because that is the failure mode the ticket warns about.

`scripts/verify-docs.sh` (executable, six checks) launches nothing. It checks the documents exist in the house formats and — mostly — that their claims about the tree are still true: which services still publish glyphs, whether any framework popups remain, whether the retired word "module" still names what the glossary says, and whether the idle-lock inversion still matches the installed session helper. It was mutation-tested: **34 edits each falsifying one claim, 34 caught, 0 missed.** That process found five real holes in the checker itself.

**AGENTS.md — what was actually stale.** The layer-shell convention restored by ticket 02 was already present and was left alone. Two things were still wrong: the verification-script list had gone stale *again* (ticket 03 fixed the "no verification step" claim, then ticket 04 added a script and re-staled the count), and `docs/adr/` was described as being "at the repo root". Added: never call anything a module; the widget naming rule; the idle-lock helper convention including the recorded-not-edited `pkill … waybar`.

**Naming convention:** config `type` is kebab-case → file is UpperCamelCase → QML type is that same name (`system-tray` → `SystemTray.qml` → `SystemTray`); one-word names stay one word; no underscores, no `Module`/`Widget` suffix. Widgets live in one flat directory, one file per widget; a widget is added by writing the file and adding one registry entry. **No path is pinned**, deliberately, because ticket 06 was choosing the directory in parallel. A check actively fails if AGENTS.md ever pins `shell/topisland/modules/` as the widget location, so a future mistake fails loudly rather than silently. Check (F) also verifies no widget QML was touched by this ticket.

**Merge coordination.** Ticket 06 ran in parallel and conflicted in AGENTS.md's Running section. Resolved by union: all six verifiers are now documented, and the count was corrected from five to six. Had that been merged without care, `verify-docs.sh` check (F) would have failed on the undocumented script.

**Spec flagged as wrong or ambiguous — worth the maintainer's attention:**

1. The spec says panels are being moved off "framework popup windows" as though there is one. There are **two** popup-based panels: `components/TopIslandModule.qml` and `NetworkModule.qml`. Ticket 11 deletes the base class's popup, ticket 12 deletes NetworkModule's — both need to know the teardown is split.
2. The glyph-migration scope is larger than the spec implies. Tickets 11/12/13 have **thirteen** consumer sites to move, not five properties.
3. **"Component" is a fourth word collision the spec does not name.** `components/` holds shared non-widget types (`Separator`, `ProgressOSDItem`) *and* the retired widget base, so it overlaps "widget" the same way "module" did. Listed under Widget's `_Avoid_` and under Module's replacements. If a later ticket introduces a new shared-types directory, that is a decision worth making deliberately rather than inheriting — flagged to ticket 06.
4. AGENTS.md's File Layout calls `components/` "shared components" and `shell/` "all the shell components" — the word already means two things. Out of scope to rename here; noted so it is not a surprise.

**One acceptance criterion is only partly met.** Criterion 7 (idle-lock inversion documented *where the helper is used*) is soft, because the widget does not exist yet — there is no point of use to write to. It is recorded in the two places an implementer will actually read (the glossary entry and an AGENTS.md convention naming the helper path), and verified against the installed `/usr/local/bin/nosarch/nosarch-session`: `idle_lock_status()` echoes `true` exactly when `nosarch-idle-inhibit.service` is active. **Ticket 17 still owes a note at the point of use** in the widget it builds.

Live desktop untouched: nothing was launched (the checker only reads), and waybar 1333, hyprpaper 1335, swayosd 1347 and swaync 1487 hold their original PIDs.

