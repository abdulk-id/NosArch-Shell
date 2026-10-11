# 05: Vocabulary, recorded decisions, and restored repo conventions

**What to build:** The design decisions this spec settles are recorded where a future reader will find them, so a person tidying up the code later does not silently undo them. Concretely: a glossary covering bar, zone, widget, panel, service, palette and idle-lock inhibit, each with the terms to avoid — the word "module" is explicitly retired because it currently means three different things in this codebase and is a direct cause of the unapplied abstraction. Two decision records: the service and widget boundary, because a future reader seeing presentation removed from services will be tempted to move it back; and the panel architecture, because abandoning framework popups looks like a mistake without knowing why.

**Blocked by:** 03 (smoke-test entrypoint).

**Status:** ready-for-agent

- [ ] A glossary exists at the repo root covering bar, zone, widget, panel, service, palette and idle-lock inhibit.
- [ ] Each glossary entry states the terms to avoid, not just the definition.
- [ ] The word "module" is explicitly retired, with a note that it currently means three different things in this codebase and caused the unapplied abstraction.
- [ ] A decision record captures the service and widget boundary, including the reasoning that a future reader would otherwise undo.
- [ ] A decision record captures the panel architecture, including that abandoning framework popups is deliberate and why.
- [ ] The Hyprland-only trade-off for the panel focus model is recorded as a deliberate decision, not left implicit.
- [ ] The decision that the idle-lock semantics are inverted relative to their names is documented where the helper is used.