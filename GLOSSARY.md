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
clicking anywhere else. At most one is open at a time.
_Avoid_: popup, popover, dialog, menu, dropdown, flyout

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
change it, and nothing about how any of it looks.
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
_RETIRED_ — do not use it for anything new. It names three unrelated things at
once: the bar widgets, the base class they were meant to share, and QML's own
sense of a directory of types, which `services/` and `components/` genuinely are.
Naming the abstraction alongside its instances let that base class reach exactly
one widget of twelve; the other eleven ignore it.
_Avoid_: widget, service, component, base class, contract — and, for a directory
that declares a `qmldir`, QML's own word for it
