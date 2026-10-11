# 14: Media player widget and the MediaService rename

**What to build:** A media indicator showing what is playing, so I can see what is making noise, with a click to play or pause so I can control playback without opening anything.

The media service is renamed to `MediaService`, matching the `*Service` naming of its siblings — a small consistency change made while the widget is being built, not as a separate sweeping edit.

**Blocked by:** 09 (per-widget options in configuration).

**Status:** ready-for-agent

- [ ] The media indicator shows what is currently playing.
- [ ] Clicking the media indicator toggles play and pause.
- [ ] The media service is renamed to `MediaService`, matching its siblings.
- [ ] No other module is left referring to the old name.