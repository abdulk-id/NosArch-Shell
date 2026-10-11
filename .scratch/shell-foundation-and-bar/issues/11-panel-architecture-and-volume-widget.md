# 11: Panels as full-screen overlay surfaces, with the volume widget

**What to build:** A panel opens when I click its widget, positioned under the widget that opened it, within screen bounds. It closes when I click elsewhere, when I press Escape, and when I click on another monitor. It accepts keyboard input the instant it opens, and interactive elements inside it take keyboard focus, so I can use a panel without a mouse. It does not vanish when my mouse moves away from it, and a dismissing overlay never swallows my clicks on the controls inside it. Only one panel is open at a time, so panels never overlap. Clicking a different widget switches panels in one click.

This replaces framework popup windows, chosen after establishing that interactive popups do not receive keyboard focus until clicked or hovered, which makes them unusable for panels that should be summonable and typed into immediately. Keyboard focus grabbing is not used, and the recursive focus-clearing workaround for it is deleted rather than ported. The recursive property-walking that existed only to stop popup dismissal eating clicks on a volume slider goes with it — the volume slider is the interaction that proves it.

This ticket is deliberately the largest and comes early, in isolation. If it proves difficult, no widget can display a panel, which blocks this phase's completion.

**Known limits, recorded rather than claimed:** panel positioning is top-bar only; left, right and bottom positions are not implemented. Pixel geometry — including whether a panel appears under the widget that was clicked — remains a manual visual check, because framework limits make position assertions impractical. Multi-monitor behaviour is structured for but unverified on one monitor.

**Blocked by:** 08 (three zones, true centre, floating or full-width bar), 10 (bar on every monitor, surviving monitor add/remove).

**Status:** ready-for-agent

- [ ] A panel opens on click, positioned under the widget that opened it, and stays within screen bounds.
- [ ] A panel closes on Escape.
- [ ] A panel closes on an outside click, including a click on another monitor.
- [ ] A panel accepts keyboard input the instant it opens, without an intervening click or hover.
- [ ] Interactive elements inside a panel take keyboard focus, so the panel is usable without a mouse.
- [ ] A panel stays interactive while my mouse moves away from it.
- [ ] Panel contents stay clickable while the panel is open — a dismissing overlay never swallows my clicks.
- [ ] Only one panel is open at a time; panels never overlap.
- [ ] Clicking a different widget switches panels in one click, without closing the incumbent first.
- [ ] A panel reopens correctly if closed while animating away, so rapid clicking does not leave it stuck.
- [ ] Keyboard focus and click ownership are released as soon as the panel logically closes, not after its close animation.
- [ ] Each panel's window is individually named, so cross-monitor dismissal can tell panels apart.
- [ ] Panels are full-screen layer-shell surfaces with the card positioned inside, with a brief exclusive-focus prime that then drops to on-demand — exclusive alone would route every pointer event on every output to the panel and break clicks on other monitors.
- [ ] The framework popup implementation and its recursive focus-clearing and property-walking workarounds are deleted rather than ported.
- [ ] The volume widget is delivered on this panel architecture, with a slider I can drag without the panel closing under me.
- [ ] The volume indicator distinguishes headphones, handsets and speakers so the icon matches my hardware, and shows muted state distinctly.
- [ ] Volume presentation no longer lives in the audio service: the service reports what is true, the widget decides what it looks like.
- [ ] Top-bar-only positioning is recorded as the current scope, along with the Hyprland-only focus dependency and the unverified multi-monitor behaviour.