# 07: Bar contents driven by a user-owned configuration file

**What to build:** What appears in my bar comes from a JSON configuration file, not from QML, so reordering widgets, removing one, and adding one are all config edits rather than code changes. The file lives outside the repository, in the user's Quickshell config directory, at a deliberately absolute path that is not resolved relative to the QML source — resolving it relatively would appear to work during development and silently break once the shell is deployed. It is owned by the user, not tracked in git, because the installer deploys it.

A bad configuration never costs me my desktop. An unrecognised widget name, a malformed entry, or a widget that fails to construct is logged with the offending name and skipped; everything valid still renders. A malformed file as a whole falls back to defaults and the shell still starts.

Bar layout has three named zones, each an ordered list of widget entries. Each entry is an object carrying at least a type, with optional per-widget settings — entries are objects rather than bare name strings from the outset, because the config file ships to every target machine and a future format break would mean a migration on every machine.

**Blocked by:** 06 (widget contract, widget registry, and the clock widget).

**Status:** ready-for-agent

- [ ] Bar contents come from a JSON configuration file rather than from QML.
- [ ] The configuration path is absolute and not resolved relative to the QML source, so it survives the shell being deployed.
- [ ] The configuration lives outside the repository and is not tracked in git.
- [ ] Bar layout has three named zones — left, centre, right — each an ordered list of widget entries.
- [ ] Each entry is an object carrying at least a type, not a bare name string, so per-widget settings can be added later without a format change.
- [ ] An unrecognised widget name is skipped rather than fatal, and the log names the offending widget.
- [ ] A malformed entry, or a widget that fails to construct, is logged with its name and skipped; everything valid still renders.
- [ ] Malformed configuration as a whole falls back to defaults and the shell still starts.
- [ ] With no configuration file present, the shell starts with defaults and a working bar.
- [ ] Reordering widgets within a zone, removing a widget, and adding a widget are each achievable by editing configuration alone.