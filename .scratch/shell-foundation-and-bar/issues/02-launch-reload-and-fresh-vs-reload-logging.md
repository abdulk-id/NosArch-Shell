# 02: Launch, reload, and tell a fresh start from a reload

**What to build:** As a maintainer I can launch the shell by pointing it at an explicit path in my repository, without installing it, and save a file to see the change within about a second. When I read the log I can tell whether the shell started fresh or reloaded, so a state reset is never confused with a clean start. This also establishes the layer-shell convention — every overlay surface sets a layer and a namespace — which the panel architecture later depends on for distinguishing per-monitor surfaces.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The shell launches from an explicit path passed on the command line, from the repository, with nothing installed and no autostart entry required.
- [ ] Saving a file reloads the shell and the reload is visibly fast — the edit loop is under a second in normal operation.
- [ ] The log states plainly whether this process started fresh or reloaded, so the two are distinguishable at a glance.
- [ ] Every overlay surface sets both a layer and a namespace, following the restored layer-shell convention.
- [ ] The convention is recorded in the project instructions, since it is load-bearing for the panel architecture rather than incidental.