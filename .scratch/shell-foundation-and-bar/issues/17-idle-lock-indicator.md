# 17: Idle-lock indicator via the NosArch session helper

**What to build:** An idle-lock indicator showing whether my machine will lock when idle, so I know before I walk away, clickable to prevent my machine locking so long-running work is not interrupted.

Read and write both go through the existing NosArch session helper. Reading state from one source and writing through another was considered and rejected: two sources for the same fact drift apart silently when either changes, and I would see an indicator that disagrees with reality.

The semantics are inverted relative to their names, and this is documented where it is used: the helper reports idle locking as "enabled" when the inhibit is running, that is, when locking will *not* happen. The indicator shows whether the machine will lock when idle, and the toggle action flips it. A reader who takes "enabled" at face value will invert the indicator.

The session helper's idle-lock commands also contain a process-kill targeting the old bar to force a refresh. That call becomes inert once the old bar is retired. It is recorded, not edited — the file is managed by the NosArch tooling and will be updated when the shell is folded into the NosArch codebase at v1.0.

**Blocked by:** 08 (three zones, true centre, floating or full-width bar).

**Status:** ready-for-agent

- [ ] The indicator shows whether my machine will lock when idle.
- [ ] Clicking the indicator prevents idle locking; clicking again restores it.
- [ ] Reading state and writing state both go through the NosArch session helper — never one source for reading and another for writing.
- [ ] The inverted semantics are documented where the helper is used, so "enabled" is not read as "will lock".
- [ ] The indicator's displayed meaning is checked against the helper's actual output, so the indicator cannot disagree with reality.
- [ ] The session helper's stale process-kill against the old bar is recorded, not edited.