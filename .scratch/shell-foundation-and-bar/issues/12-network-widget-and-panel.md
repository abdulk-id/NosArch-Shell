# 12: Network widget and its panel

**What to build:** A network indicator reflecting whether I am online, distinguishing a captive portal from a normal connection so I know when a login page is blocking me. Clicking it opens a panel listing available connections with signal strength so I can pick the best one, and showing throughput so I can tell what is using bandwidth.

This is where panel switching gets verified against a second panel-bearing widget: one click moves from the volume panel to the network panel and back.

The network service currently publishes a glyph string as a first-class property, which is why its widget must re-derive half its own presentation. That presentation moves out of the service and into the widget. This is the thousand-line widget's cause being removed rather than its symptom.

**Blocked by:** 09 (per-widget options in configuration), 11 (panels as full-screen overlay surfaces, with the volume widget).

**Status:** ready-for-agent

- [ ] The network indicator reflects connection state.
- [ ] The indicator distinguishes a captive portal from a normal connection.
- [ ] The network panel lists available connections with signal strength.
- [ ] The network panel shows throughput, so I can tell what is using bandwidth.
- [ ] Switching between the volume panel and the network panel takes one click, in both directions.
- [ ] Network presentation — glyphs and anything rendered for display — no longer lives in the service; the service reports state and the widget decides appearance.
- [ ] Missing network hardware is reported gracefully rather than showing nonsense.