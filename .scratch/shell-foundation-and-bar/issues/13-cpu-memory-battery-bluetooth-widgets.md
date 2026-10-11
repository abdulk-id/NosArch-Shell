# 13: CPU, memory, battery, and bluetooth widgets

**What to build:** A CPU usage indicator and a memory usage indicator, so I can tell when my machine is busy and how much memory is in use, each clickable to open a system monitor so I can investigate. A battery indicator showing charge percentage that changes colour when charge is low, so I notice without reading the number. A bluetooth indicator showing whether bluetooth is on and whether anything is connected.

All four report missing hardware gracefully — no battery, no bluetooth adapter — so a widget never shows nonsense, and the shell survives a service that is unavailable at startup so a late-starting service does not break the bar.

Battery presentation currently lives in the system information service as a glyph string; that moves into the widget.

**Blocked by:** 09 (per-widget options in configuration).

**Status:** ready-for-agent

- [ ] The CPU indicator shows usage, and clicking it opens a system monitor.
- [ ] The memory indicator shows usage, and clicking it opens a system monitor.
- [ ] The battery indicator shows charge percentage.
- [ ] The battery indicator changes colour when charge is low.
- [ ] The bluetooth indicator shows whether bluetooth is on and whether anything is connected.
- [ ] Absent hardware — no battery, no bluetooth adapter, no default audio device — is reported gracefully rather than showing nonsense.
- [ ] The shell survives a widget's underlying service being unavailable at startup, so a late-starting service does not break the bar.
- [ ] Battery and bluetooth presentation no longer lives in their services; the services report state and the widgets decide appearance.