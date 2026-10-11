# 09: Per-widget options in configuration

**What to build:** Each widget declares its own options, and its configuration entry carries them, so a widget can be tuned without a code change. This is what the object-shaped entries from 07 exist for: the configuration file ships to every target machine, so options had to be anticipated in the format rather than added by breaking it later.

**Blocked by:** 08 (three zones, true centre, floating or full-width bar).

**Status:** ready-for-agent

- [ ] Each widget declares its own options, and receives them from its configuration entry.
- [ ] At least one widget's behaviour is tunable by configuration alone, with no code change.
- [ ] An option a widget does not recognise does not break the shell — it is skipped like any other bad entry.