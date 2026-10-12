# NosArch Shell

The vocabulary of the Quickshell bar shell: what the user sees, what the shell is
made of, and what the shell asks the machine about. Each entry gives the one word
this codebase means by a concept and the words to stop using for it.

These are definitions, not design notes. The decisions behind the terms live in
`docs/adr/`; the conventions a maintainer has to follow live in `AGENTS.md`.

## Language

### What the user sees

**Bar**:
The single always-drawn surface along one screen edge of every monitor, holding the
zones and their widgets. Drawn at the top edge; no other edge is implemented.
_Avoid_: TopIsland, top island, dock, panel, statusbar

**Zone**:
One of the three ordered groups a bar's width is divided into — left, centre,
right — each holding an ordered list of widgets.
_Avoid_: section, group, column, cluster, gutter

**Widget**:
One entry in a zone: the piece of the bar that shows one fact about the machine
and answers one click.
_Avoid_: module, component, plugin, icon, element, tile

**Panel**:
The larger surface a widget opens beneath itself to show detail, dismissed by
clicking anywhere else. At most one is open at a time. A full-screen layer-shell
overlay with the card drawn inside it — never a framework popup window.
_Avoid_: popup, popover, dialog, menu, dropdown, flyout

**Panel card**:
The visible part of an open panel: the framed box a widget's `panelContent` is
drawn into. Distinguished from the panel because it is the part that holds focus
and takes clicks; the panel is the surface and the dismissal around it.
_Avoid_: popup window, dialog body, panel window

**Dismissal surface**:
The transparent, click-to-close area of a panel's surface, covering everything
except the card and the bar's own strip. Its region mask is what keeps bar
widgets clickable while a panel is open.
_Avoid_: overlay, backdrop, scrim, curtain, dimmer

**Dismissal twin**:
The transparent surface a panel puts on every OTHER monitor, so a click there
dismisses it. Pointer input is hit-tested per output, so the panel's own
full-screen surface cannot see clicks elsewhere.
_Avoid_: mirror, ghost surface, secondary panel, replica

**Focus prime**:
The moment at open when a panel's surface holds EXCLUSIVE keyboard focus before
dropping to on-demand. It is what makes a panel typeable the instant it opens;
holding exclusive focus for longer would route every pointer event on every
output to it.
_Avoid_: focus grab, focus steal, keyboard grab

**Logical open state**:
Whether a panel is open, as distinct from whether it is currently drawn. Focus
and click ownership follow this, so a panel that has logically closed gives the
desktop back immediately rather than after its closing animation.
_Avoid_: visibility, shown, open-ness, live state

**Idle-lock inhibit**:
A running session-helper unit that keeps the machine from locking itself for as
long as it runs. The helper names the unit, not the locking: its `enable` and
`status` words mean *the inhibit is running*, which means the machine will **not**
lock when idle.
_Avoid_: idle-lock enabled (read at face value), idlelock, autosuspend,
screensaver, sleep

### What the shell is made of

**Service**:
A singleton that reports what is true of the machine and offers the actions that
change it, and nothing about how any of it looks. A shared component may turn
that state into a display decision; a service may not.
_Avoid_: backend, adapter, provider, manager, controller, module

**Widget registry**:
The hand-maintained map from a configuration widget name to the widget file that
serves it. It is data in the shell code rather than something discovered at
runtime, and configuration never names a file.
_Avoid_: plugin registry, loader, index, manifest, catalogue

**Palette**:
The single set of named colours the shell renders from, read from a file in the
NosArch theme directory and backed by built-in defaults.
_Avoid_: theme, colours, colourscheme, style, css, skin

### Retired

**Module**:
_RETIRED_ — do not use it for anything new. It once meant the deleted
`shell/topisland/modules/` widgets, the unused `TopIslandModule` base, or a QML
`qmldir` directory; bar widgets now live on the contract in `shell/widgets/`.
_Avoid_: widget, service, component, base class, contract — and, for a directory
that declares a `qmldir`, QML's own word for it
