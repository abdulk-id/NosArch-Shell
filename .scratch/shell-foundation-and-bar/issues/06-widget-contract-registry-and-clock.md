# 06: Widget contract, widget registry, and the clock widget

**What to build:** Every bar widget satisfies one uniform contract by extending a single base class, declaring the same required interface: content for the bar, a click action, a tooltip, and optionally panel content. A widget that offers a panel supplies it; a widget that does not, does not pretend to with an empty one. A simplified base for trivial label-plus-click widgets exists so simple widgets are not forced to declare absent capabilities. A widget name in configuration resolves through a map from name to file held in the shell code — there is no runtime plugin registry, and configuration never carries file paths, because a user-owned config file that named arbitrary code locations would be a code-execution surface. The clock is the first widget on the contract, and every widget dims when hovered and brightens, so I can tell which ones are interactive. Adding a widget now means writing one file and adding one entry.

**Blocked by:** 03 (smoke-test entrypoint), 04 (theme-driven palette and fonts).

**Status:** ready-for-agent

- [ ] One base class declares a uniform required interface: bar content, click action, tooltip, and optional panel content.
- [ ] A widget offering a panel supplies panel content; a widget offering none supplies nothing rather than an empty one.
- [ ] A simplified base exists for trivial label-plus-click widgets so they are not forced to declare absent capabilities.
- [ ] A widget name resolves through a map from name to file held in the shell code; configuration never carries a file path.
- [ ] Widgets live in a single predictable directory, and adding one means copying a file and adding one entry.
- [ ] The clock widget is migrated onto the contract, showing time and date and updating every minute so it never shows a stale time.
- [ ] Widgets dim when not hovered and brighten on hover, so interactive widgets are distinguishable.
- [ ] Hovering shows a tooltip where the widget has one.
- [ ] The base contract carries the hover affordance rather than each widget reimplementing it.