# Services expose state, never presentation

Status: accepted. The decision is settled; the migration is in progress.

A service reports what is true about the machine and offers the actions that
change it. It never decides what any of that looks like: a glyph, a colour, a
label, or a string formatted for display belongs to the widget that draws it.
Anything looser lets a widget end up re-deriving presentation a service
half-owned, which is how the network widget reached roughly a thousand lines.

## Why this gets undone by accident

A reader tidying up a widget that visibly re-derives something will move the
derivation "back to where it belongs" — into the service. Four things make that
reflex wrong, and all four are quiet:

1. **The data is right there.** Computing an icon next to the flags it derives
   from looks DRY; computing it in a widget looks like duplication. The service
   is the only place that sees all of `isMuted`, `deviceFormFactor` and
   `defaultSink` at once, so it reads as the natural home — but knowing the
   inputs is not the same as owning the decision about the output.
2. **Moving it back changes nothing observable.** The service's glyph and the
   widget's version agree today, so the "fix" produces no failing test and no
   visible difference. There is nothing left to object with.
3. **The tidied-up version looks shorter.** A widget that picks an icon from
   three state flags looks worse than a service that already picked one, and
   shorter reads as cleaner.
4. **The service cannot actually answer the question.** A glyph needs to know
   the font, the theme, which icon slot to use, and what an absent device should
   look like. A service is told none of that, so it guesses and the widget
   overrides it — and now both hold a copy. Two copies of a display decision
   drift the moment the theme changes, and nothing records which one wins.

The rule that follows: a widget derives its own appearance from state properties,
and a service never imports the palette. No service imports `shell/ui` today,
which is the mechanical test for the boundary — keep it that way.

## Migration status: in progress

Presentation is still living in services. As of this record:

| Service | What it still publishes |
| --- | --- |
| `services/NetworkService.qml` | `textIcon`, plus a `wifiIcons` array indexed by signal strength |
| `services/AudioService.qml` | `textIcon` on the output object and again on the input object |
| `services/BluetoothService.qml` | `textIcon` covering adapter-enabled, discoverable and device-connected |
| `services/SystemInfo.qml` | battery `textIcon`, plus `defaultIcons` and `chargingIcons` arrays |

Thirteen call sites consume those glyphs today: seven under `shell/` (the
volume, network, bluetooth and battery widgets, plus the volume OSD — volume
and network each read theirs twice), three in `smoke.qml`, and three in the
`testing/` service readout. Tickets 11 (audio), 12 (network) and 13 (bluetooth
and battery) move them out, each onto the widget that draws them. Until those
land, the table above is the truth: do not read this record as evidence that the
services are presentation-free. `scripts/verify-docs.sh` fails if it ever claims
otherwise.

## Consequences

- Services hold no persistent-property state. Nothing survives a reload on
  Quickshell 0.3.2, so a service is a stateless view over framework APIs and
  cannot cache a glyph "for later" either.
- A widget that offers a panel keeps its panel content; a service never supplies
  panel content.
- If a service ever needs to grow a property, the first question is whether it is
  state or a decision about appearance. Only the first belongs there.
