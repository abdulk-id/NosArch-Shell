# 03: Smoke-test entrypoint for every widget and service

**What to build:** A single verification seam that instantiates every widget and service and fails on QML load errors — type errors, missing properties, unresolved bindings — without involving my live bar. Today nothing objects when a widget grows past a thousand lines or is left half-wired, because there is no verification step at all. This is the first verification artefact in this codebase.

**Blocked by:** 02 (launch, reload and fresh-vs-reload logging).

**Status:** ready-for-agent

- [ ] A smoke-test entrypoint instantiates every widget and every service in the shell.
- [ ] Type errors, missing properties and unresolved bindings surfaced by that instantiation cause a non-zero exit.
- [ ] The check runs without a live bar on screen, so a broken widget is caught before I rely on it.
- [ ] The project instructions no longer claim there is no verification step, and no longer claim syntax errors surface only at runtime — both statements are false once this lands.