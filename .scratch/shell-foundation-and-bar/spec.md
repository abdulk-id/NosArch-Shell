# NosArch Shell Foundation and Bar (Phase 0 + Phase 1)

Status: ready-for-agent

## Problem Statement

The NosArch desktop currently runs five separate tools to draw the desktop: waybar (bar), swaync (notifications), swayosd (on-screen displays), hyprpaper (wallpaper), and hyprlock (lock screen). Each is a separate process with its own configuration language, its own theme values, and its own idea of how the desktop should look. Nothing coordinates them.

An attempt was made to replace this with a single Quickshell shell written in QML. That attempt is incomplete and structurally unsound:

- The bar module abstraction was designed but applied to only one of twelve bar widgets. Eleven widgets are bare items that ignore the base class entirely.
- The network widget has grown to roughly one thousand lines because it mixes service logic, panel layout, and bar rendering in a single file.
- Popup state is managed by a single global object keyed on monitor-name strings. The network widget and the volume widget call it with different argument counts, so the network panel ignores which monitor it was opened on entirely. This is invisible on a single-monitor setup and wrong the moment a second monitor is attached.
- No widget reads its layout from configuration. Reordering the bar means editing QML.
- The color palette is hardcoded in the shell and separately hand-maintained in the Hyprland lock screen configuration. The two copies have already drifted.
- There is no verification step of any kind, so nothing objects when a widget grows past a thousand lines.
- The shell has never been run as an actual desktop. It is not installed, not autostarted, and cannot be launched without passing an explicit path.

The result is that the rewrite cannot proceed incrementally: the existing code cannot be extended without touching every file, and it cannot be evaluated because there is no way to run it.

From the maintainer's perspective: I want one Quickshell process that draws my bar, so that adding a widget means writing one file rather than restructuring the shell, and so that the desktop is programmable instead of merely configurable. I want to be able to launch it, see it, and reload it while I work. I want to replace waybar first and keep the other four tools running until each is genuinely replaced.

## Solution

Rebuild the shell around four separations that the current code does not make.

**Services expose state, never presentation.** A service reports what is true (connected, active device, volume, speed). It does not decide what that looks like. Today the network service publishes a glyph string as a first-class property, which is why its widget must re-derive half its own presentation. Moving presentation out of services is the single change that prevents a thousand-line widget from recurring.

**Every bar widget satisfies one uniform contract.** All twelve widgets extend the same base class, declaring the same required interface. A widget that offers a panel supplies panel content; a widget that does not, does not pretend to.

**Panels are full-screen overlay surfaces, not popups.** A panel is a layer-shell surface anchored under its widget, with a short compositor-level focus prime so keyboard input works the moment it opens. This replaces a recursive property-walking workaround whose only purpose was to stop popup dismissal from eating clicks on a volume slider.

**Layout comes from a JSON configuration file.** Bar zones, widget order, and floating behaviour are data, not code. The configuration is owned by the user, not tracked in git, and lives outside the repository so it survives the shell being moved.

Two constraints shape everything else. First, **nothing survives a reload**: verified empirically on the installed Quickshell 0.3.2, persistent-property state does not carry across a reload in any arrangement tested, including the framework's own documented example. Any state that must outlive a reload is written to disk. Second, **a bad configuration must never break the desktop**: an unrecognised widget name or malformed entry is logged and skipped, because a shipped shell that hard-fails leaves the user with no bar at all.

## User Stories

### Running and developing the shell

1. As a maintainer, I want to launch the shell with an explicit path, so that I can work on it in my repository without installing it.
2. As a maintainer, I want the shell to reload automatically when I save a file, so that my edit loop takes under a second.
3. As a maintainer, I want to know from the log whether a running shell started fresh or reloaded, so that I can tell a clean start from a state reset.
4. As a maintainer, I want a smoke-test entrypoint that instantiates every widget and service, so that type errors surface without my live bar being involved.
5. As a maintainer, I want a scripted startup check that runs the real shell and fails on QML warnings, so that failures which only appear once real services connect are caught.
6. As a maintainer, I want the pre-rewrite state preserved and tagged, so that I can diff against it and recover if the rewrite goes badly.
7. As a maintainer, I want to run the new shell alongside waybar, so that I can compare them and choose my own cutover moment.
8. As a maintainer, I want nothing in my live desktop configuration changed by the rewrite, so that my session keeps working throughout.
9. As a NosArch user, I want the shell deployed to a predictable location by the NosArch installer, so that a plain shell command launches it.

### Bar layout and structure

10. As a user, I want my bar to show widgets in three zones (left, centre, right), so that the layout matches the waybar muscle memory I already have.
11. As a user, I want the centre zone to hold its widgets truly centred, so that the clock does not shift when other widgets change size.
12. As a user, I want the bar to appear as a floating rounded island by default, so that it matches the visual style I chose.
13. As a user, I want to switch the bar to a full-width background, so that I can choose the style I prefer without a code change.
14. As a user, I want to reorder widgets within a zone by editing configuration, so that moving an icon does not require touching QML.
15. As a user, I want to remove a widget from the bar by deleting one configuration line, so that thinning out my bar is trivial.
16. As a user, I want to add a widget by adding one configuration entry, so that extending my bar does not require restructuring the shell.
17. As a user, I want each widget to declare its own options in configuration, so that widgets can be tuned without a code change.
18. As a user, I want the bar to appear on every attached monitor, so that the shell is correct on a multi-monitor desktop.
19. As a user, I want the bar to handle being added or removed at runtime, so that plugging in a monitor does not require restarting the shell.

### Widgets

20. As a user, I want a clock showing time and date, so that I can tell what time it is.
21. As a user, I want the clock to update every minute, so that it never shows a stale time.
22. As a user, I want workspace indicators showing which workspaces exist and which is focused, so that I can see my window layout at a glance.
23. As a user, I want to click a workspace indicator to switch to it, so that I can navigate without a keybind.
24. As a user, I want workspaces that have no windows to appear dimmed, so that empty ones are distinguishable.
25. As a user, I want the system tray to show my running applications' icons, so that I can launch and quit them.
26. As a user, I want left-clicking a tray icon to activate it, so that it behaves like every other tray.
27. As a user, I want right-clicking a tray icon to show its context menu, so that tray-only actions are reachable.
28. As a user, I want middle-clicking a tray icon to trigger its secondary action, so that all three mouse buttons work.
29. As a user, I want a CPU usage indicator, so that I can tell when my machine is busy.
30. As a user, I want a memory usage indicator, so that I can tell how much memory is in use.
31. As a user, I want to click the CPU or memory indicator to open a system monitor, so that I can investigate.
32. As a user, I want a battery indicator showing charge percentage, so that I know how much charge is left.
33. As a user, I want the battery indicator to change colour when charge is low, so that I notice without reading the number.
34. As a user, I want a network indicator reflecting connection state, so that I can tell whether I am online.
35. As a user, I want the network indicator to distinguish a captive portal from a normal connection, so that I know when a login page is blocking me.
36. As a user, I want a network panel listing available connections with signal strength, so that I can pick the best one.
37. As a user, I want to see network throughput in the network panel, so that I can tell what is using bandwidth.
38. As a user, I want a volume indicator reflecting my audio output, so that I can see the level without opening anything.
39. As a user, I want the volume indicator to distinguish headphones, handsets, and speakers, so that the icon matches my hardware.
40. As a user, I want the volume indicator to show muted state distinctly, so that I notice I have muted myself.
41. As a user, I want a volume panel with a slider, so that I can set the level precisely.
42. As a user, I want to be able to drag the volume slider without the panel closing under me, so that the interaction works.
43. As a user, I want a Bluetooth indicator, so that I can tell whether Bluetooth is on and whether anything is connected.
44. As a user, I want a media indicator showing what is playing, so that I can see what is making noise.
45. As a user, I want to click the media indicator to play or pause, so that I can control playback.
46. As a user, I want a notification indicator, so that I can see whether anything is waiting for me.
47. As a user, I want to click the notification indicator to toggle do-not-disturb, so that I can silence interruptions.
48. As a user, I want the notification indicator to look different while do-not-disturb is on, so that I can tell it is active.
49. As a user, I want an idle-lock indicator showing whether my machine will lock when idle, so that I know before I walk away.
50. As a user, I want to click the idle-lock indicator to prevent my machine locking, so that long-running work is not interrupted.
51. As a user, I want to click a launcher icon to open my application launcher, so that I can start applications.
52. As a user, I want widgets to dim when I hover over them and brighten on hover, so that I can tell which ones are interactive.

### Panels

53. As a user, I want a panel to open when I click its widget, so that details are one click away.
54. As a user, I want a panel to close when I click elsewhere, so that I can dismiss it without a keybind.
55. As a user, I want a panel to close when I press Escape, so that I have a keyboard way out.
56. As a user, I want interactive elements inside a panel to take keyboard focus, so that I can use the panel without a mouse.
57. As a user, I want a panel to accept keyboard input the instant it opens, so that I can type into it immediately.
58. As a user, I want clicking a different widget to switch panels in one click, so that I do not have to close the current panel first.
59. As a user, I want only one panel open at a time, so that panels never overlap.
60. As a user, I want a panel to close when I click on another monitor, so that clicking elsewhere always dismisses it.
61. As a user, I want a panel to stay interactive while my mouse moves away from it, so that a panel does not vanish when I reach for a control.
62. As a user, I want panel contents to remain clickable while the panel is open, so that a dismissing overlay never swallows my clicks.
63. As a user, I want the panel to be positioned under the widget that opened it, so that I can predict where it appears.
64. As a user, I want the panel to stay within screen bounds, so that it is never cut off.
65. As a user, I want a panel to reopen correctly if it is closed while animating away, so that rapid clicking does not leave it stuck.
66. As a user, I want keyboard focus released as soon as a panel logically closes, so that I am not locked out of my previous window during the animation.

### Theme and colours

67. As a user, I want the shell to read its colours from a theme file, so that changing my theme updates the shell.
68. As a user, I want the shell to fall back to a known-good default palette when no theme file exists, so that a fresh install still renders correctly.
69. As a user, I want the shell to write out a theme file with those defaults the first time it runs, so that I have something to edit.
70. As a user, I want the shell never to overwrite an existing theme file, so that my edits are never destroyed.
71. As a user, I want a theme file I was mid-way through editing to be left alone if it is malformed, so that I do not lose work.
72. As a user, I want no colour hardcoded in any widget, so that every widget follows the theme.
73. As a user, I want the accent, background, foreground, and alert colours named consistently, so that widgets do not invent their own names for the same colour.
74. As a user, I want fonts configured in one place, so that a font change applies everywhere.

### State and persistence

75. As a user, I want do-not-disturb to stay off after I restart my shell, so that I set it once.
76. As a user, I want the shell to write state to a per-shell state directory, so that it does not collide with other shells.
77. As a user, I want state writes to succeed even if the state directory does not exist yet, so that a first run works.
78. As a user, I want my do-not-disturb setting to be the single source of truth, so that the indicator and the notification behaviour never disagree.

### Robustness

79. As a user, I want an unknown widget name in configuration to be skipped rather than fatal, so that one bad line does not cost me my whole desktop.
80. As a user, I want the failure to name the offending widget, so that I can fix it quickly.
81. As a user, I want malformed configuration to fall back to defaults, so that the shell still starts.
82. As a user, I want every widget to be verified by a smoke test, so that a broken widget is caught before I rely on it.
83. As a user, I want the shell to report missing hardware gracefully (no battery, no Bluetooth adapter, no default audio device), so that widgets do not show nonsense.
84. As a user, I want the shell to survive a widget's underlying service being unavailable at startup, so that a service starting late does not break the bar.
85. As a NosArch user, I want a shipped shell to degrade rather than break when something is wrong with it, so that my machine stays usable.
86. As a user, I want each panel's window to be individually named, so that cross-monitor dismissal can tell panels apart.

### Extending the shell later

87. As a maintainer, I want to add a widget by writing one file and adding one line, so that extending the shell is cheap.
88. As a maintainer, I want widgets to live in a predictable location, so that the extension point is discoverable.
89. As a maintainer, I want a documented convention for widget naming, so that the registry stays consistent.
90. As a maintainer, I want the service and widget boundary documented as a decision, so that a future reader does not undo it while cleaning up.

### Phase 1 completion

91. As a user, I want all twelve bar widgets rendering with live data, so that the new bar is a complete replacement for the old one.
92. As a user, I want the bar to show correct CPU, memory, clock, workspaces, tray, and volume data, so that I can trust it.
93. As a user, I want the shell to start with no errors in the log, so that I know it is healthy.
94. As a user, I want the shell to launch with no errors when the configuration file is absent, so that a fresh install works.

## Implementation Decisions

### Scope of this spec

Covers foundation (configuration, palette, state, registry, domain documentation) and the bar. Notifications, on-screen displays, and wallpaper are separate specs written when their phase is reached.

### Preserved from the pre-rewrite shell

Six service singletons are carried forward substantially unchanged because they are correct and already use native framework APIs: audio (pipewire), media (MPRIS), bluetooth, notifications, system information, and networking. The tray widget is likewise carried forward, as its menu anchoring and three-button handling are already right.

One service is renamed for consistency: the media service becomes `MediaService`, matching the `*Service` naming of its siblings.

### Service and widget boundary

Services expose state only. Any property that renders as a glyph, colour, or string chosen for display moves out of services and into the widgets that consume them. This is the change that prevents the current pattern where a widget must re-derive presentation a service half-owned.

### Widget contract

Every bar widget extends one base class and declares a uniform required interface: content for the bar, a click action, a tooltip, and optionally panel content. Widgets with no panel supply none rather than supplying an empty one. A simplified base for trivial label-plus-click widgets is provided so that simple widgets are not forced to declare absent capabilities.

Twelve widgets are in scope: launcher icon, workspaces, CPU, memory, media player, clock, system tray, network, bluetooth, volume, battery, and notification indicator.

### Widget resolution

A widget name in configuration is resolved through a map from name to file, held in the shell code. There is no runtime plugin registry: the framework provides none in the installed version, so the map is ours to maintain. Widgets live in a single predictable directory so that adding one means copying a file and adding one entry.

Configuration does not carry file paths. The configuration is a user-owned file that the installer will ship to target machines, and making it name arbitrary code locations would turn a configuration file into a code-execution surface.

### Configuration schema

Configuration is a JSON object. Bar layout has three named zones, each an ordered list of widget entries. Each entry is an object carrying at least a type, with optional per-widget settings. Entries are objects rather than bare name strings from the outset so that per-widget options can be added later without a format change — the configuration file ships to every target machine, so a future format break would mean a migration on every machine.

The schema is deliberately minimal: only what the bar needs. Keys are added as features require them.

Schema shape, from the design discussion rather than a prototype:

```json
{
    "bar": {
        "floating": true,
        "zones": {
            "left": [{ "type": "launcher" }, { "type": "workspaces" }, { "type": "cpu" }, { "type": "memory" }],
            "center": [{ "type": "player" }, { "type": "clock" }],
            "right": [
                { "type": "tray" },
                { "type": "idle-lock" },
                { "type": "network" },
                { "type": "bluetooth" },
                { "type": "volume" },
                { "type": "battery" },
                { "type": "notification" }
            ]
        }
    }
}
```

### Configuration location and ownership

Configuration lives in the user's Quickshell config directory, alongside where the shell is installed at v1.0. It is **not** tracked in git: it is user-editable, and the installer deploys it. During development the shell runs from the repository while configuration is read from its final absolute location.

The path is absolute and deliberately not resolved relative to the QML source. Resolving it relatively would appear to work during development and silently break once the shell is deployed. This is recorded because it looks like an unnecessary absolute path and is not.

### Palette

A palette file lives in the existing NosArch theme directory, which today holds wallpapers only and has no colour palette of any kind. The shell reads it and falls back to a default palette held in the shell code — the current colour values. On first run, when no palette file exists, the shell writes the defaults out so the user has something to edit.

The shell never overwrites an existing palette file. If one exists but is malformed, the shell falls back to defaults and leaves the file untouched.

This addresses a real existing defect: colours are currently maintained twice, in the shell and in the Hyprland lock screen configuration, and the two have already drifted. The lock screen configuration remains hand-maintained and is not generated by the shell — coupling a shell-side failure to a file the compositor reads at lock time is a bad failure mode. That trade-off is a decision to record.

### Panel architecture

Panels are full-screen layer-shell surfaces with the card positioned inside, not framework popup windows. This was chosen after establishing that interactive popups do not receive keyboard focus until clicked or hovered, which makes them unusable for panels that should be summonable and typed into immediately.

The panel implementation requires:

- A short focus prime on open: the surface requests exclusive keyboard focus briefly, then drops to on-demand. Exclusive alone would make the compositor route every pointer event on every output to the panel, breaking clicks on other monitors; the prime is what makes keyboard input work at open time without that side effect.
- An explicit keyboard-focus target inside the panel, focused after the surface maps, because layer-shell focus alone does not give an in-surface item active focus for key handlers to fire.
- A dismissal surface covering the screen, with the region mask excluding the bar strip so bar widgets stay clickable while a panel is open.
- A transparent dismissal twin on every other output, because pointer input is hit-tested per output and the main dismissal surface cannot see clicks elsewhere.
- A bar-level coordinator tracking which panel is active, so opening one closes the incumbent and clicking a different widget switches panels in a single click.
- Focus and click ownership bound to the panel's logical open state rather than its visibility, so ownership is released the moment it logically closes rather than after its close animation.

Keyboard focus grabbing is **not** used, and the recursive focus-clearing workaround for it is deleted rather than ported.

Panel positioning is top-bar-only. Left, right, and bottom bar positions are not implemented; adding them later is a contained change.

**This binds the shell to Hyprland.** The panel focus model depends on compositor-specific behaviour, so porting to another compositor would require a different panel base. The shell is Hyprland-only today, and this is a deliberate trade to record.

**One panel is open at a time.** Two overlapping full-screen overlay surfaces would compete for input, so this is intrinsic to the architecture rather than a separate product choice.

### Reload behaviour

Verified empirically on the installed Quickshell 0.3.2: persistent-property state does **not** survive a reload. Four arrangements were tested — inside a singleton, inside a plain object, the framework's own documented example verbatim, and both hard and soft reload modes — and all reset to their initial value. Object identity differed on each cycle, confirming new objects rather than a stale binding. The file-watcher reload path was confirmed to fire, ruling out a false negative.

Consequences, which are load-bearing for the whole design:

- Services contain no persistent-property state. They are stateless views over framework APIs.
- Every reload discards live state: notification history empties, open panels close, the notification server restarts.
- Any state that must survive a reload is written to disk.
- Panel open state does not survive a reload. Acceptable, arguably desirable while developing.
- The shell logs whether it started fresh or reloaded, so a state reset is distinguishable from a clean start.

This was checked against the installed build only. Whether a later version behaves differently is unknown and was not investigated.

### State persistence

State that must outlive the process is written to the framework's per-shell state directory. State writes are atomic by default, and parent directories are created automatically, so a first run needs no directory bootstrap code.

Notably, a write whose content is identical to what is already on disk is silently skipped and emits no completion signal. Code must not depend on a completion signal firing for every write.

### Idle-lock inhibit

Read and write both go through the existing NosArch session helper. Reading state from one source and writing through another was considered and rejected: two sources for the same fact drift apart silently when either changes, and the user would see an indicator that disagrees with reality.

The semantics are inverted relative to their names and this must be documented: the helper reports idle locking as "enabled" when the inhibit is **running**, that is, when locking will **not** happen. The indicator shows whether the machine will lock when idle, and a toggle action flips it.

### Failure policy

A bad configuration never stops the shell. An unrecognised widget name, a malformed entry, or a widget that fails to construct is logged with the offending name and skipped; everything valid still renders.

This is deliberate for the shipped case: this shell will be deployed to other people's machines, and bad code shipped accidentally or a configuration that disagrees with the installed version must cost the user one missing icon rather than their entire desktop. A shell that refuses to start on one bad line also trains the user to edit configuration defensively, which is worse.

### Verification

**Foundation:** a smoke-test entrypoint that instantiates every widget and service, surfacing QML load errors — type errors, missing properties, unresolved bindings — without involving the live bar. A startup log check is out of proportion here because foundation output has no user-visible behaviour.

**Bar:** the smoke test plus a scripted run of the real shell that fails on QML warnings, catching failures that only appear once real services connect. This upgrades once there is a bar to test against, because twelve live widgets is the shell's largest surface and exactly where a silent wiring error hides.

Honest limits of this approach: the framework has no unit test framework, so every check is a harness that launches the shell and reads logs. None of these are unit tests. None can assert pixel geometry — position assertions, such as whether a panel appears under the widget that was clicked, remain effectively manual.

### Deployment and the existing desktop

The rewrite changes nothing about how the existing tools start. The new shell is launched explicitly during development and runs alongside the current bar; the cutover is the user's decision per phase.

The existing session helper's idle-lock commands contain a process-kill targeting the old bar to force a refresh. That call becomes inert once the old bar is retired. Such calls are recorded rather than edited, because that file is managed by the NosArch tooling and will be updated when the shell is folded into the NosArch codebase at v1.0.

The lock screen is explicitly out of scope for the foreseeable future and stays with the existing tool. If the shell crashes while it owns the lock screen, the user cannot get back into their machine.

### Repository conventions to restore

A layer-shell convention (always set the layer and a namespace on overlay surfaces) was dropped from the project instructions during the pre-rewrite edits. Under the panel architecture it becomes load-bearing: panel surfaces need distinct namespaces so cross-monitor dismissal twins are distinguishable. The convention is restored as part of this work.

The project instructions also currently state there is no verification step, which this spec makes false. Both lines are corrected as part of this work.

### Documentation deliverables

A glossary is created capturing the vocabulary settled during design: bar, zone, widget, panel, service, palette, and idle-lock inhibit, each with the terms to avoid. The word "module" is explicitly retired: it currently means three different things in this codebase and is a direct cause of the unapplied abstraction.

Two decisions are recorded as architectural decision records: the service and widget boundary, since a future reader seeing presentation removed from services will be tempted to move it back; and the panel architecture, since abandoning framework popups looks like a mistake without knowing why.

## Testing Decisions

**What makes a good test here:** whether the shell's external behaviour is correct — does the bar render, does the configuration drive it, does a panel open and dismiss, does state persist across a restart. Not whether internals are shaped a particular way. A test that asserts a service exposes a particular property name is testing implementation, not behaviour, and will be rewritten for no benefit.

**What is tested:**

- Every widget and service instantiates without error, via the smoke-test entrypoint. This is the broad net and the highest-value check.
- The real shell starts and logs no QML warnings, via the scripted check.
- Configuration drives layout: zone contents and ordering reflect the configuration.
- Unknown widget names are skipped with a named log line rather than being fatal.
- Absent configuration yields defaults and a working bar.
- Palette falls back to defaults when absent, writes the file on first run, and never overwrites an existing file.
- State written for do-not-disturb is read back after a restart.
- A panel opens on click, closes on Escape, closes on outside click including on another output, and switches in one click from another widget.

**Not tested:** pixel geometry and visual layout. Framework limits make these impractical to assert, and visual review by the maintainer is the substitute. Also not tested: behaviour under a second monitor, since only one is attached — multi-monitor correctness is structured for but unverified, and this is recorded as a known gap rather than an oversight.

**Prior art:** the existing project instructions state there is no verification step and that syntax errors surface only at runtime. The smoke test is the first verification artefact in this codebase, so there is no prior art to follow and no existing seam to prefer. The smoke-test entrypoint is the proposed new seam, deliberately placed at the highest point available — a whole-shell entrypoint rather than per-module harnesses — so that the number of seams stays at one.

## Out of Scope

- **Lock screen.** Stays with the existing tool. A shell crash while it owns the lock screen risks locking the user out of their machine.
- **Application launcher.** Deferred pending the maintainer's own evaluation of the existing launcher.
- **Notifications beyond the bar indicator.** The notification daemon, popups, and any notification history or centre are a later phase with their own spec.
- **On-screen displays.** Later phase, own spec.
- **Wallpaper.** Later phase, own spec.
- **Polkit agent.** Not currently part of the shell's role.
- **Bar positions other than top.** Left, right, and bottom positions are not implemented.
- **Multiple simultaneously open panels.** Intrinsic to the panel architecture, not deferred.
- **Runtime plugin loading of widgets from user configuration.** Widget addition means editing the shell, by decision.
- **Per-monitor differing bar layouts.** Every monitor gets the same layout.
- **Generating the Hyprland lock screen configuration from the palette.** The palette drives the shell only.
- **Editing the NosArch-managed session helper.** Stale calls against the old bar are recorded, not changed.
- **Any change to how the existing desktop tools start.** Cutover is the maintainer's decision per phase.

## Further Notes

**Research reference.** The shell that inspired the panel architecture is at the `omacom/omarchy` repository, branch `quattro`, under the shell directory. Note that the commonly cited `omarchy/omarchy-shell` location no longer exists, and the similarly named `omarchy/omarchy` repository is an unrelated profile. Two independent community shells converged on the same full-screen-overlay panel approach, one of them additionally modelling panel state as independent per-panel flags rather than a single coordinator.

**Uncertain ground.** Two things were established empirically and are worth re-checking if the environment changes. First, the persistent-property reload behaviour was verified only on the installed 0.3.2 build; if the shell is later deployed against a different version, this should be re-tested, and if a later version fixes it, panel open state could be made reload-surviving. Second, the compositor focus-grab primitive was confirmed present and functional, but only under Hyprland.

**Sequencing note.** The panel architecture is the largest and hardest component, and it arrives before anything else has been validated. If it proves difficult, the bar cannot display any panel, which blocks this phase's completion criteria. It is therefore the component most worth building early and in isolation, with the remaining widgets following once it works.

**Known gap.** Multi-monitor behaviour is structured for but unverified, because only one monitor is attached. The pre-rewrite code had a latent bug here — two widgets disagreeing about a popup API's arity, such that one panel ignored its monitor entirely — which is invisible on a single monitor and wrong on a second. That class of bug is what multi-monitor verification would catch, and it remains uncaught here.
