# 16: Notification indicator with persisted do-not-disturb state

**What to build:** A notification indicator showing whether anything is waiting for me, clickable to toggle do-not-disturb so I can silence interruptions, and looking different while do-not-disturb is on so I can tell it is active. Do-not-disturb stays off across a shell restart, so I set it once.

State that must outlive the process is written to the framework's per-shell state directory, so it does not collide with other shells. State writes succeed even when the state directory does not exist yet, so a first run works with no bootstrap step. The do-not-disturb setting is the single source of truth — the indicator and the notification behaviour read the same value, so they never disagree.

This ticket establishes the state-persistence seam for later phases. Services hold no persistent-property state: on the installed Quickshell 0.3.2, persistent properties do not survive a reload in any arrangement tested, so anything that must outlive a reload goes to disk.

**Blocked by:** 08 (three zones, true centre, floating or full-width bar).

**Status:** ready-for-agent

- [ ] The notification indicator shows whether anything is waiting.
- [ ] Clicking the notification indicator toggles do-not-disturb.
- [ ] The indicator looks different while do-not-disturb is on, so I can tell it is active.
- [ ] Do-not-disturb stays as I set it across a shell restart.
- [ ] State is written to a per-shell state directory, so it does not collide with other shells.
- [ ] State writes succeed on a first run when the state directory does not exist yet.
- [ ] The indicator and the notification behaviour read the same do-not-disturb value, so they cannot disagree.
- [ ] No service holds state in a persistent property, since that state would not survive a reload.