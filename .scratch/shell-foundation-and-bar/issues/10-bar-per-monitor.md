# 10: Bar on every monitor, surviving monitor add/remove

**What to build:** My bar appears on every attached monitor, and appears or disappears as I plug monitors in and out at runtime, without restarting the shell. Every monitor gets the same layout — per-monitor differing layouts are out of scope.

This also fixes a class of bug that is currently invisible and wrong the moment a second monitor is attached: popup state is managed by a single global object keyed on monitor-name strings, and the network widget and the volume widget call it with different argument counts, so the network panel ignores which monitor it was opened on entirely.

**Known gap, recorded rather than closed:** only one monitor is attached, so multi-monitor correctness is structured for but unverified. The behaviour under a second monitor is not tested, and this ticket does not claim otherwise.

**Blocked by:** 08 (three zones, true centre, floating or full-width bar).

**Status:** ready-for-agent

- [ ] The bar appears on every attached monitor.
- [ ] Adding or removing a monitor at runtime makes the bar appear or disappear without restarting the shell.
- [ ] Every monitor shows the same layout; per-monitor differing layouts are not attempted.
- [ ] The different-arity popup-state calls that let the network panel ignore its monitor are gone, replaced by a mechanism whose monitor handling cannot disagree between widgets.
- [ ] The multi-monitor known gap is recorded where a future reader will find it, so unverified is not mistaken for overlooked.