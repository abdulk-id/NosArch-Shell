# 04: Theme-driven palette and fonts

**What to build:** The shell reads its colours from a palette file in the existing NosArch theme directory — which today holds wallpapers only and has no palette of any kind — and falls back to a known-good default palette when none exists, so a fresh install still renders correctly. On first run it writes those defaults out so I have something to edit. It never overwrites an existing file, and a file I was midway through editing is left completely alone if it turns out to be malformed. Fonts are configured in one place so a font change applies everywhere. No colour is hardcoded in any widget.

**Blocked by:** 02 (launch, reload and fresh-vs-reload logging).

**Status:** ready-for-agent

- [ ] Colours come from a palette file read from the NosArch theme directory.
- [ ] With no palette file present, the shell renders using a known-good default palette.
- [ ] On first run with no palette file, the shell writes the defaults out so there is something to edit.
- [ ] An existing palette file is never overwritten.
- [ ] A malformed palette file falls back to defaults and leaves the file itself untouched.
- [ ] Fonts are configured in a single place and a change there applies everywhere.
- [ ] No widget hardcodes a colour or a font property.
- [ ] Accent, background, foreground and alert colours are named consistently, so widgets do not invent their own names for the same colour.