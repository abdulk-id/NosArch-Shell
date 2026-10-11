# 08: Three zones, true centre, floating or full-width bar

**What to build:** My bar has left, centre and right zones, matching the waybar muscle memory I already have. The centre zone is truly centred, so the clock does not shift when other widgets change size — the current bar's centre is an overlay that only appears centred because its neighbours happen to be symmetric. The bar appears as a floating rounded island by default, and I can switch it to a full-width background from configuration without touching code.

**Blocked by:** 07 (bar contents driven by a user-owned configuration file).

**Status:** ready-for-agent

- [ ] The bar shows widgets in three zones — left, centre, right.
- [ ] The centre zone holds its widgets truly centred, so the clock does not shift when other widgets change size.
- [ ] The bar appears as a floating rounded island by default.
- [ ] Switching the bar to a full-width background is a configuration change, not a code change.
- [ ] Zone contents and their ordering reflect the configuration file.