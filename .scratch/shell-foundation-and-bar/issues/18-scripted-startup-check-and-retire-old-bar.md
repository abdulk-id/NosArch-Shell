# 18: Scripted real-shell startup check, twelve live widgets, retire the old bar

**What to build:** The phase is done when the new bar is a complete replacement for the old one. All twelve widgets render with live data — clock, workspaces, tray, CPU, memory, network, bluetooth, volume, battery, notification, media player, launcher — so the new bar can carry the cutover. A scripted run of the real shell fails on QML warnings, catching the failures that only appear once real services connect, which is exactly where a silent wiring error hides across twelve live widgets. The shell starts with no errors in the log, and starts cleanly with no configuration file at all, so a fresh install works.

The old bar is retired here: the top-island bar, its module directory and the unused module base class are deleted, since every widget now lives on the contract from 06. They are kept until this point rather than deleted widget-by-widget, because a single edit that breaks the whole old bar is cheaper to revert than twelve partial migrations.

My live desktop configuration is untouched throughout, and the new shell runs alongside waybar — the cutover moment is mine to choose. The lock screen explicitly stays with the existing tool; if the shell crashed while owning the lock screen, I could not get back into my machine.

**Blocked by:** 11 (panels as full-screen overlay surfaces, with the volume widget), 12 (network widget and its panel), 13 (CPU, memory, battery, and bluetooth widgets), 14 (media player widget and the MediaService rename), 15 (workspaces, tray, and launcher widgets), 16 (notification indicator with persisted do-not-disturb state), 17 (idle-lock indicator via the NosArch session helper).

**Status:** ready-for-agent

- [ ] All twelve bar widgets render with live data.
- [ ] The bar shows correct CPU, memory, clock, workspace, tray and volume data.
- [ ] A scripted run of the real shell fails on QML warnings.
- [ ] The shell starts with no errors in the log.
- [ ] The shell launches with no errors when the configuration file is absent.
- [ ] The smoke test still passes for every widget and service after the old bar is removed.
- [ ] The old bar, its module directory and the unused module base class are deleted.
- [ ] No live desktop configuration is changed — waybar, swaync, swayosd, hyprpaper and hyprlock all still start exactly as before.
- [ ] The new shell runs alongside waybar so I can compare them and choose my own cutover moment.