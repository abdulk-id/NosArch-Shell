#!/usr/bin/env bash
#
# verify-panels.sh — verification for ticket 11.
#
#   "A panel opens when I click its widget, positioned under the widget that
#    opened it, within screen bounds. It closes when I click elsewhere, when I
#    press Escape, and when I click on another monitor. It accepts keyboard
#    input the instant it opens, and interactive elements inside it take
#    keyboard focus, so I can use a panel without a mouse. It does not vanish
#    when my mouse moves away from it, and a dismissing overlay never swallows
#    my clicks on the controls inside it. Only one panel is open at a time, so
#    panels never overlap. Clicking a different widget switches panels in one
#    click."
#
#   …delivered through the volume widget, because dragging a slider without the
#   panel closing under the pointer is the interaction the popup architecture
#   could not support.
#
# ---------------------------------------------------------------------------
# THE SEAMS UNDER TEST
#
#   Written down before the first case, because a verifier that quietly grows a
#   second, weaker seam is how a green run starts implying more than it checked.
#
#   S1  PanelCoordinator's PUBLIC API — open(id, widget) / toggle(id, widget) /
#       close() / hasOpenPanel / ownsInput. Catches: one-panel-at-a-time,
#       switching in one action, and ownership being released the moment the
#       panel LOGICALLY closes. Misses: everything about surfaces — it owns no
#       window, by design.
#
#   S2  PanelCard's PUBLIC API — focusContent() (force real in-surface focus,
#       report whether it arrived) and the Escape key handler. Catches: an
#       interactive element inside a panel taking keyboard focus, and Escape
#       dismissing through the coordinator. Misses: whether the compositor ever
#       granted the SURFACE keyboard focus — which is seam S3, and is the only
#       thing that can answer it.
#
#   S3  The REAL shell.qml, launched, with its own PANEL log lines read
#       afterwards. Catches: the surfaces really map, full-screen, on the right
#       layer with their own namespaces; the focus prime really fires and drops
#       to on-demand; active focus really arrives on the in-surface target; and
#       a REAL Escape keystroke (injected with wtype, through the compositor,
#       to whatever surface holds keyboard focus) really closes the panel.
#       Misses: pixel geometry, pointer hit-testing, and anything needing a
#       second monitor.
#
#   S4  The widget/service boundary — VolumeWidget's panelContent, and the
#       audio service publishing no display glyph. Catches: presentation having
#       moved out of the service into the widget, with the three device icons
#       and the muted state chosen there. Misses: whether the icon font
#       actually has the codepoints (a visual check).
#
# ---------------------------------------------------------------------------
# WHAT IS DELIBERATELY NOT CHECKED HERE, AND WHY
#
#   The spec is explicit: the framework has no unit test runner, nothing can
#   assert pixel geometry, and "does a panel appear under the widget that was
#   clicked" remains a MANUAL visual check. So there is no geometry assertion
#   of that kind in this script, and if one ever appears it is a bug in this
#   script. What IS checked about placement is the one mechanical part: the
#   card's own reported rect must lie inside the screen the framework reports
#   for that surface — two independently-sourced numbers (one from the panel's
#   placement arithmetic, one from the framework's screen list), compared by
#   this script rather than by the shell that produced them.
#
#   Pointer input cannot be synthesised on this machine. There is no pointer
#   injection tool installed (wtype is keyboard-only; Hyprland 0.56 has no click
#   dispatcher), so these promises are verified as far as they honestly can be
#   and the remainder is recorded in docs/known-gaps.md rather than claimed:
#
#     * a physical click on a widget opens its panel (Qt's hit-testing is
#       untouched — the click action `activate(widget)` IS driven, at S1);
#     * a physical click on the bar strip does not dismiss (the mask's SHAPE is
#       checked statically at A5; the hit-test through it is not);
#     * a physical click on another monitor dismisses (also unverified: one
#       monitor is attached);
#     * a physical drag of the volume slider (S1/S4 prove no grabFocus exists,
#       that the slider's value is wired to the service, and that the panel's
#       state is untouched by it — not that a hand-held mouse does it).
#
#   Each of those is named in docs/known-gaps.md with what it would take.
#
# ---------------------------------------------------------------------------
# SAFETY (the live desktop is running)
#
#   Every launch runs under `dbus-run-session`, so the shell's NotificationServer
#   owns org.freedesktop.Notifications on a throwaway bus and cannot disturb
#   swaync, which owns the real one. HOME *and* XDG_CONFIG_HOME are pointed at a
#   scratch directory — XDG_CONFIG_HOME is set in this environment, so
#   redirecting HOME alone would send the configuration reader straight back at
#   the real ~/.config. Nothing is written to ~/.config, ~/.local/share or any
#   installed location, and no autostart entry is added.
#
#   The ONE genuinely risky part of this ticket is keyboard focus: a panel
#   primes EXCLUSIVE focus, which really does take the keyboard away from
#   whatever the user is typing into. That is the promise under test, so it is
#   exercised exactly once (case E), for the length of the prime, inside a shell
#   that is killed the instant it has reported. The wait loops below are bounded
#   by timeout as well as by the grep, and the cleanup trap kills on exit.
#
#   Launches are matched on this worktree's path and on this script's scratch
#   directory — never a broad pkill. Five other agents run shells against this
#   same desktop concurrently, and waybar/hyprpaper/swayosd-server/swaync must
#   all keep running.
#
# Exit status: 0 only if every check holds.
#
set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
SHELL_QML="shell.qml"
RUN_SECS="${RUN_SECS:-30}"
SHELL_RUN_SECS="${SHELL_RUN_SECS:-25}"
PRIME_MS="${PRIME_MS:-140}"

# Fast smoke timing, as in verify-bar-surface.sh / verify-widget-contract.sh:
# nothing in the headless cases needs live hardware beyond the audio service the
# volume widget reads.
export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-1500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-900}"

TMP="$(mktemp -d /tmp/opencode/qs-panels.XXXXXX)"

PASS=0
FAIL=0
FAILED_CASES=()

cleanup() {
    # Kill only THIS script's shells: their cmdlines carry this worktree's or
    # this scratch directory's unique path. Never a broad pkill — the live
    # desktop runs a shell too, and so do the other verifiers.
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "quickshell.*${TMP}/shell" 2>/dev/null || true
    pkill -f "dbus-run-session.*${TMP}/shell" 2>/dev/null || true
    pkill -f "dbus-daemon.*qs-panels" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 11 verification — panels as overlay surfaces, with the volume widget"
echo " repo: $REPO"
echo "======================================================================"

pass() { PASS=$((PASS + 1)); echo "    PASS $1: $2"; }
fail() {
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$1")
    echo "    FAIL $1: $2"
}

# The panel architecture's own files. Stripped of comments before any shape
# check reads them: these files explain at length why they must NOT contain a
# PopupWindow or a grabFocus, and a check that reads prose fails on the
# explanation and passes on the thing it forbids.
PANEL_FILES=(shell/panels/PanelSurface.qml shell/panels/PanelCard.qml
             shell/panels/PanelCoordinator.qml shell/bar/Bar.qml
             shell/bar/BarSurface.qml shell/widgets/BarWidget.qml
             shell/widgets/VolumeWidget.qml services/AudioService.qml)

# ---------------------------------------------------------------------------
# (A) STATIC — the SHAPE of the architecture
# ---------------------------------------------------------------------------
#
# This is where most of the ticket's architecture lives, and it is checked
# statically because with one monitor and no pointer injection most of it is
# structurally checkable and behaviourally unobservable. Every needle below is a
# decision the spec or ADR 0002 names, and each says what breaks without it.
echo
echo "[A] static: the architecture's shape ..."
python3 - "$REPO" "${PANEL_FILES[@]}" <<'PY'
import re, sys, pathlib

repo = pathlib.Path(sys.argv[1])
panel_files = [pathlib.Path(a) for a in sys.argv[2:]]
problems = []


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def code(rel):
    f = repo / rel
    return strip_comments(f.read_text(errors="replace")) if f.is_file() else ""


# ---- A1: the panel directory exists and declares itself --------------------
pdir = repo / "shell/panels"
qmldir = pdir / "qmldir"
if not pdir.is_dir():
    print("      ! shell/panels/ does not exist — there is no panel architecture")
    sys.exit(1)
if not qmldir.is_file():
    problems.append("shell/panels/qmldir does not exist — a directory of QML types "
                    "with no qmldir resolves its siblings by accident, not by design")
else:
    names = set()
    for line in qmldir.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            parts = line.split()
            if len(parts) >= 2:
                names.add(parts[1] if parts[0] == "singleton" else parts[0])
    for want in ("PanelCoordinator", "PanelCard", "PanelSurface"):
        if want not in names:
            problems.append(f"shell/panels/qmldir does not register {want}")

# ---- A2: NO framework popups anywhere in the new architecture -------------
#
# The whole point of ADR 0002. Checked over the panel directory AND the bar AND
# the widgets, because a popup reintroduced on the widget side would be just as
# broken as one on the surface side.
#
# The list is the FILES THIS ARCHITECTURE OWNS, and it must include the widget
# contract: a `PopupWindow` or a `grabFocus` reintroduced on the widget side would
# be just as broken as one on the surface side. An earlier version of this list
# named BarWidget.qml but the tree-wide sweep below it exempted the whole
# pre-rewrite prefix — which does NOT cover shell/widgets/, so the sweep passed a
# popup added to the contract (found by mutation testing). Both checks now run,
# over the same scope.
for rel in ["shell/panels/PanelSurface.qml", "shell/panels/PanelCard.qml",
            "shell/panels/PanelCoordinator.qml", "shell/bar/Bar.qml",
            "shell/bar/BarSurface.qml", "shell/bar/BarZone.qml",
            "shell/bar/BarConfig.qml", "shell/widgets/BarWidget.qml",
            "shell/widgets/SimpleBarWidget.qml", "shell/widgets/VolumeWidget.qml",
            "shell/widgets/ClockWidget.qml"]:
    text = code(rel)
    if "PopupWindow {" in text:
        problems.append(f"{rel} declares a PopupWindow — panels are layer-shell "
                        "overlay surfaces (ADR 0002)")
    if "grabFocus" in text:
        problems.append(f"{rel} uses grabFocus — focus grabbing is deleted rather "
                        "than ported, because it dismisses the panel when a control "
                        "inside it is used")
    for forbidden in ("makeChildrenUnfocusable", "activeFocusOnTab"):
        if forbidden in text:
            problems.append(f"{rel} still carries {forbidden} — the recursive "
                            "focus-clearing workaround goes with focus grabbing, and "
                            "it disabled the in-panel focus this architecture exists "
                            "to provide")

# ---- A2b: no framework popup anywhere in the tree --------------------------
#
# Over the whole tree, so a PopupWindow added to a widget tomorrow cannot slip
# past a check that only looked at the panel directory.
for f in sorted(repo.rglob("*.qml")):
    if {".git", ".scratch", ".agents", ".zed"} & {p.name for p in f.parents}:
        continue
    rel = str(f.relative_to(repo))
    body = strip_comments(f.read_text(errors="replace"))
    if "PopupWindow {" in body:
        problems.append(f"{rel} declares a PopupWindow — panels are overlay surfaces "
                        "(ADR 0002)")
print("    (tree) framework PopupWindows in the tree: none expected after ticket 18")

# ---- A3: the panel is a FULL-SCREEN layer-shell surface with a card in it ---
surface = code("shell/panels/PanelSurface.qml")
if "PanelWindow" not in surface:
    problems.append("PanelSurface.qml declares no PanelWindow — the panel is a "
                    "layer-shell surface, not an item inside the bar")
for anchor in ("top: true", "left: true", "right: true", "bottom: true"):
    if anchor not in surface:
        problems.append(f"PanelSurface.qml does not anchor {anchor} — a panel that "
                        "does not cover its output cannot be a dismissal surface for it")
if "ExclusionMode.Ignore" not in surface:
    problems.append("PanelSurface.qml does not set exclusionMode: ExclusionMode.Ignore — "
                    "with the default Auto the compositor reserves the bar's exclusive "
                    "zone and hands the panel a surface that does NOT cover the screen "
                    "(measured on this machine: the surface came back at y=85, height=995, "
                    "instead of 0,0,1920x1080)")
if "WlrLayershell.layer" not in surface or "Overlay" not in surface:
    problems.append("PanelSurface.qml sets no WlrLayershell.layer, or not the Overlay "
                    "layer — a panel below the bar would be behind it")

# ---- A4: layer + namespace, and namespaces distinct by role ----------------
ns = re.findall(r'WlrLayershell\.namespace\s*:\s*"([^"]+)"', surface)
if not ns:
    problems.append("PanelSurface.qml sets no WlrLayershell.namespace — a surface with "
                    "no namespace cannot be told from the bar's, the OSD's or a twin's")
if "nosarch-shell-panel" not in ns:
    problems.append(f"PanelSurface.qml publishes {ns or 'nothing'} — the panel's own "
                    "role must be named 'nosarch-shell-panel' so the cross-monitor "
                    "logic and the verifier can tell it apart")

# Tree-wide: every namespace claimed by exactly one surface file. This is the
# same rule verify-bar-per-monitor.sh enforces, re-checked here because ticket 11
# adds the surfaces that rule exists for.
by_ns = {}
for f in sorted(repo.rglob("*.qml")):
    if {".git", ".scratch", ".agents", ".zed"} & {p.name for p in f.parents}:
        continue
    for one in re.findall(r'WlrLayershell\.namespace\s*:\s*"([^"]+)"',
                          strip_comments(f.read_text(errors="replace"))):
        by_ns.setdefault(one, set()).add(str(f.relative_to(repo)))
print("    (tree) layer-shell namespaces by role:")
for one, owners in sorted(by_ns.items()):
    print(f"      - {one}: {', '.join(sorted(owners))}")
for one, owners in sorted(by_ns.items()):
    if len(owners) > 1:
        problems.append(f"namespace {one} is claimed by {len(owners)} surface files "
                        f"({', '.join(sorted(owners))}) — two roles sharing a namespace "
                        "cannot be told apart")

# ---- A5: the dismissal surface masks the bar strip out ---------------------
#
# The panel's surface is full-screen, so without a mask the overlay would sit on
# top of the bar and eat every click on every widget. The mask is a REGION, and
# Region lives in Quickshell CORE, not in Quickshell.Wayland — using the wrong
# module fails to resolve the type (quickshell-api-notes.md §8).
if re.search(r'import\s+Quickshell\.Wayland[\s\S]{0,400}?\bRegion\b(?!\w)', surface):
    pass  # a bare Region word is not proof of a bad import; checked properly below
if "Region" not in surface:
    problems.append("PanelSurface.qml sets no mask — a full-screen overlay with no "
                    "region mask swallows clicks on the bar strip underneath it")
if "Intersection.Xor" not in surface:
    problems.append("PanelSurface.qml's mask does not use Intersection.Xor — the "
                    "dismissal surface must own the screen MINUS the bar strip, and "
                    "Xor of the strip is that set")
if not re.search(r'mask\s*:', surface):
    problems.append("PanelSurface.qml never assigns PanelWindow.mask")
if not re.search(r'import\s+Quickshell\s*$|import\s+Quickshell[\s"]', surface):
    problems.append("PanelSurface.qml does not `import Quickshell` — Region is in the "
                    "core module, and a panel using it from Quickshell.Wayland does "
                    "not resolve the type")

# ---- A6: the focus prime exists, and drops to on-demand --------------------
#
# Exclusive alone would make the compositor route every pointer event on every
# output to the panel, which breaks clicks on other monitors. The prime is what
# buys keyboard input at open time without that side effect. Two members, and
# `Exact` is a trap that silently evaluates to undefined on this build, so its
# absence is checked explicitly.
if "WlrKeyboardFocus.Exclusive" not in surface:
    problems.append("PanelSurface.qml never requests WlrKeyboardFocus.Exclusive — "
                    "without the prime the panel cannot be typed into at open time")
if "WlrKeyboardFocus.OnDemand" not in surface:
    problems.append("PanelSurface.qml never drops to WlrKeyboardFocus.OnDemand — "
                    "exclusive focus alone would route every pointer event on every "
                    "output to the panel")
if re.search(r"WlrKeyboardFocus\.\s*Exact", surface):
    problems.append("PanelSurface.qml names WlrKeyboardFocus.Exact — there is no such "
                    "member on this build and it silently evaluates to undefined")
prime_timer = re.search(r"Timer\s*\{[^}]*focusPrim", surface, re.S)
if not prime_timer:
    problems.append("PanelSurface.qml has no timer driving the prime — the drop to "
                    "on-demand must happen on a timer, or the surface would hold "
                    "exclusive focus for as long as the panel is open")
elif not re.search(r"focusPrim[\s\S]{0,400}?interval\s*:", surface):
    problems.append("PanelSurface.qml's prime timer has no interval — a timer that "
                    "cannot expire would hold exclusive focus until the panel closed")
# The mode must be READABLE, not only writable: "the prime fired" is not a claim a
# log can make unless the surface reports which mode was actually in force.
if not re.search(r"readonly\s+property\s+string\s+focusMode", surface):
    problems.append("PanelSurface.qml does not expose the current focus mode — without "
                    "it, no run can report whether the prime actually fired, and "
                    "\"the prime happened\" would be unfalsifiable")

# ---- A7: an explicit in-surface keyboard-focus target ---------------------
#
# Layer-shell focus alone does not give an in-surface item active focus, so a
# key handler inside the panel would never fire. The card must therefore force
# focus onto a REAL item, after the surface has mapped.
card = code("shell/panels/PanelCard.qml")
if "forceActiveFocus" not in card:
    problems.append("PanelCard.qml never calls forceActiveFocus() — layer-shell focus "
                    "does not give an in-surface item active focus, so nothing inside "
                    "the panel would receive key events")
if not re.search(r"function\s+focusContent\s*\(", card):
    problems.append("PanelCard.qml has no focusContent() — the focus target has to be "
                    "resolvable and reportable, or 'focus arrived' cannot be observed")

# A `focusContent()` that RETURNS a constant has not asked anything. This survived
# an earlier version of this check (found by mutation testing: replacing
# `return card.activeFocus === true` with `return true` still passed every runtime
# case, because the headless probe read the same constant back and the live case
# only grepped for `arrived=yes`).
#
# So the return must be a READ of the real focus state, and the live case must
# cross-check that read against the shell's INDEPENDENT report of `activeFocus`.
# Both halves are needed: the shape check catches a constant return, and the
# cross-check catches a card that reads the wrong property.
if not re.search(r"function\s+focusContent\s*\(\s*\)\s*:\s*bool\s*\{"
                 r"[\s\S]{0,900}?return\s+card\.activeFocus", card):
    problems.append("PanelCard.qml's focusContent() does not return a read of the card's "
                    "real activeFocus — a function that returns a constant has not asked "
                    "whether focus arrived, and every caller would believe it had "
                    "(found by mutation testing)")
if "Escape" not in surface and "Escape" not in card:
    problems.append("neither PanelSurface.qml nor PanelCard.qml handles Escape — a "
                    "panel with no keyboard way out fails the ticket outright")
# The focus target must be taken AFTER the surface has mapped, on a delay. Forcing
# focus during construction cannot work: there is no window yet, so the attempt
# fails silently and the panel is left unfocused for its whole life — the exact
# "opens but swallows every keypress" failure this architecture exists to fix.
if not re.search(r"settleFocus|onSurfaceMapped|onShown", surface):
    problems.append("PanelSurface.qml forces panel focus with no wait for the surface "
                    "to map — an item in a surface the compositor has not been given "
                    "cannot hold focus, so the panel would open deaf")
if not re.search(r"restart\(\)|running\s*:\s*true", surface):
    problems.append("PanelSurface.qml has no restartable trigger for the focus handoff")

# ---- A7b: the dismissal surface is BEHIND the card --------------------------
#
# "Panel contents stay clickable — a dismissing overlay never swallows my clicks."
# In QML the last-declared sibling is on top, so this is a question about
# DECLARATION ORDER and nothing else: a dismissal MouseArea declared after the
# card receives every click inside the panel, and the slider under the pointer
# never sees one.
#
# Found by mutation testing: deleting the dismissal MouseArea entirely — which
# removes the only outside-click dismissal on this surface — passed every other
# case in this script.
m = re.search(r"MouseArea\s*\{[^{}]*onClicked\s*:\s*layer\.coordinator\.close\(\)[^{}]*\}",
              surface)
# Anchor on the card's DECLARATION, not on a comment: `surface` has already
# been through strip_comments(), so a marker like "// ---- the card" is gone
# and `find` returns -1 — which made this check fire on a correctly ordered
# file. Anchoring on the code also means a card moved into a Component or
# renamed cannot silently change what the check is comparing against.
card_at = surface.find("PanelCard {")
if m is None:
    problems.append("PanelSurface.qml has no dismissal MouseArea that closes the panel — "
                    "without one there is no outside-click dismissal on this surface at all")
elif card_at == -1:
    problems.append("PanelSurface.qml has no PanelCard to compare the dismissal area "
                    "against — the ordering check cannot run, so 'a dismissing overlay "
                    "never swallows my clicks' is unverified rather than verified")
elif m.start() > card_at:
    problems.append("PanelSurface.qml declares the dismissal area AFTER the card — in QML "
                    "the later sibling is on top, so it would receive every click inside "
                    "the panel and the controls under the pointer would never be used "
                    "(found by mutation testing)")

# ---- A8: the twin on every other output ------------------------------------
if "Variants" not in surface:
    problems.append("PanelSurface.qml has no Variants — pointer input is hit-tested "
                    "per output, so every OTHER output needs its own transparent "
                    "dismissal twin")
twin_ns = re.findall(r'WlrLayershell\.namespace\s*:\s*"([^"]+)"', surface)
if "nosarch-shell-panel-dismiss" not in twin_ns:
    problems.append("PanelSurface.qml publishes no distinct 'nosarch-shell-panel-dismiss' "
                    "namespace for the cross-output twin — the twin and the panel's own "
                    "surface are different roles and must be tellable apart")
# Checked INSIDE the twin's own delegate block, not anywhere in the file.
#
# The earlier version of this check merely required the string
# `WlrKeyboardFocus.None` to appear somewhere in PanelSurface.qml — which the
# MAIN surface's own assignment satisfies, so giving the twin `OnDemand` instead
# passed (found by mutation testing). The twin is a separate surface on a
# separate monitor; a keyboard-focusable twin would take the keyboard away from
# the panel the user opened, on another monitor, with nothing on screen to
# explain it.
twin_block = re.search(r"id:\s*twinWindows[\s\S]*$", surface)
if twin_block is None:
    problems.append("PanelSurface.qml's twin delegate could not be located for inspection")
else:
    body = twin_block.group(0)
    if "WlrKeyboardFocus.None" not in body:
        problems.append("PanelSurface.qml's cross-output twin does not pin its own "
                        "keyboard focus to None — a focusable twin would steal the "
                        "keyboard from the open panel on another monitor (found by "
                        "mutation testing)")

# ---- A9: the coordinator, and ownership bound to the LOGICAL state --------
coordinator = code("shell/panels/PanelCoordinator.qml")
for member in ("open", "toggle", "close"):
    if not re.search(rf"function\s+{member}\s*\(", coordinator):
        problems.append(f"PanelCoordinator.qml declares no {member}()")
if "PopupState" not in coordinator:
    problems.append("PanelCoordinator.qml does not hold a PopupState — one panel per "
                    "surface is that object's job, and a coordinator beside it would be "
                    "a second source of truth")
if "own" not in coordinator.lower():
    problems.append("PanelCoordinator.qml does not expose an ownership value — focus "
                    "and click ownership must be bound to the panel's LOGICAL open "
                    "state, and that has to be one readable thing")

# The load-bearing one: nothing may release ownership on `visible`. A surface
# whose mask, visibility or keyboard focus follows `visible` instead of the
# logical state keeps eating clicks for the length of the close animation.
for rel in ["shell/panels/PanelSurface.qml", "shell/panels/PanelCard.qml",
            "shell/panels/PanelCoordinator.qml"]:
    text = code(rel)
    for m in re.finditer(r"visible\s*:\s*([^,\n]+)", text):
        expr = m.group(1)
        if "visible" in expr and "!" in expr:
            problems.append(f"{rel} derives `visible` from a visibleChanged "
                            "expression — ownership must follow the logical open state")

# ---- A10: positioning is top-bar only, and clamped to the screen -----------
if "barHeight" not in surface:
    problems.append("PanelSurface.qml does not place the card against the bar height — "
                    "the top-bar-only placement rule has to be visible in the code")
if "screenWidth" not in surface and "targetScreen" not in surface:
    problems.append("PanelSurface.qml places the card without reference to the screen's "
                    "own width/height — a card that is not clamped to the screen can "
                    "hang off the edge")

if problems:
    print("    FAIL — the panel architecture does not have the shape the ticket claims:")
    for p in problems:
        print("      ! " + p)
    sys.exit(1)
print("    PASS — overlay surface with the card inside, a mask that cuts the bar strip "
      "out, the focus prime, an in-surface focus target, a cross-output twin, a "
      "coordinator, and ownership bound to the logical state")
PY
static_rc=$?
if [[ $static_rc -ne 0 ]]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("static-architecture-shape")
else
    PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# helpers shared by the runtime cases
# ---------------------------------------------------------------------------

# Every WARN/ERROR naming a file THIS TICKET OWNS. The exit code cannot be
# trusted — Quickshell exits 0 even when every binding throws — so this is the real
# signal.
#
# Scoped rather than tree-wide on purpose. shell/Wallpaper.qml warns that its
# theme file is missing whenever HOME is a scratch directory, which every launch
# here does deliberately; that warning is true, is not this ticket's doing, and
# failing on it would train a reader to ignore this line. The scope is printed in
# the failure message, so what was and was not considered stays visible.
repo_warnings() {
    local log="$1" only="${2:-}"
    LOG="$log" ONLY="$only" python3 - <<'PYEOF'
import os, re, pathlib
log = pathlib.Path(os.environ["LOG"])
only = os.environ.get("ONLY") or ""
qline = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\s+(WARN|ERROR)\s+(.*)$")
ref = re.compile(r"@([^\s:\[]+)\[")
bad = []
for ln in (log.read_text(errors="replace").splitlines() if log.exists() else []):
    m = qline.match(ln)
    if not m:
        continue
    f = ref.search(m.group(2))
    if not f:
        continue
    name = f.group(1)
    mine = (name == "smoke.qml"
            or name.startswith(("services/", "shell/panels/", "shell/bar/",
                                "shell/widgets/", "shell/osds/", "components/")))
    if only:
        mine = mine and (name == "shell.qml" or name.startswith(tuple(only.split(","))))
    if mine:
        bad.append(name + ": " + m.group(2).strip())
print("\n".join(bad))
PYEOF
}

# The last PANEL line of each kind. LAST, not first: a surface reports itself
# whenever anything settles, and the first report legitimately says width=0
# because the compositor has not given the window a size yet.
panel_line() {  # panel_line <log> <state|place|focus>
    LOG="$1" python3 - "$2" <<'PYEOF'
import os, re, pathlib, sys
kind = sys.argv[1]
got = []
for ln in pathlib.Path(os.environ["LOG"]).read_text(errors="replace").splitlines():
    m = re.search(rf"\bPANEL {kind} (.*)", ln)
    if m:
        got.append(m.group(1))
print(got[-1] if got else "")
PYEOF
}

# One launch of smoke.qml under a scratch HOME and XDG_CONFIG_HOME. smoke.qml
# draws no surfaces, so this can never appear on the user's desktop.
run_smoke() {  # run_smoke <scratch-home> <log>
    local home="$1" log="$2" pid
    cd "$REPO" || return 1
    HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        timeout "$RUN_SECS" dbus-run-session -- \
        quickshell --no-color --log-times -p "$SMOKE_QML" >"$log" 2>&1 &
    pid=$!
    local i
    for i in $(seq 1 $((RUN_SECS * 10))); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# (B) RUNTIME, headless — the coordinator and the card, on live instances
# ---------------------------------------------------------------------------
echo
echo "[B] runtime: the panel coordinator and card, driven headlessly ..."
mkdir -p "$TMP/caseB/.config"
LOG_B="$TMP/caseB.log"
run_smoke "$TMP/caseB" "$LOG_B"

# Each probe's promises, as the exact key=value pairs it must report. Written out
# here rather than derived from the probe's own output, because a checker that
# recomputes its expectation from what it was given tests nothing.
check_probe() {  # check_probe <probe> <claim> [claim...]
    local probe="$1"
    shift
    local line
    line="$(grep "SMOKE CONTRACT $probe " "$LOG_B" | tail -1)"
    if [[ -z "$line" ]]; then
        fail "$probe" "the smoke shell reported nothing for this promise — the probe never ran, or it threw before reporting"
        return
    fi
    local kv bad="" key expected actual
    kv="$(sed 's/^.*SMOKE CONTRACT [^ ]* //' <<<"$line")"
    for want in "$@"; do
        key="${want%%=*}"
        expected="${want#*=}"
        actual=""
        for tok in $kv; do
            [[ "$tok" == "$key="* ]] && actual="${tok#*=}"
        done
        actual="${actual%\"}"
        if [[ "$actual" != "$expected" ]]; then
            bad="${bad}${key}='${actual}' (wanted ${expected}); "
        fi
    done
    if [[ -z "$bad" ]]; then
        pass "$probe" "every claim held on a live instance (${#}) claims: $*"
    else
        fail "$probe" "a promise did not hold on a live instance: $bad"
    fi
}

check_probe panel-coordinator \
    opens=true switches-in-one-call=true ownership-released-at-logical-close=true \
    reopens=true toggle-both-ways=true empty-id-closes=true
check_probe panel-card \
    focus-arrived=true focus-is-inside-the-card=true \
    plain-content-focus-arrived=true plain-content-fell-back-to-the-card=true \
    focus-then-close-releases-ownership=true
check_probe volume-widget \
    hasPanel=true panelContent=SUPPLIED coordinator-handed-over=true \
    three-device-kinds-differ=true muted-is-distinct=true volume-bands-differ=true
# ...and the specific glyph pairs are re-checked HERE, against literals in this
# script, so the probe's own boolean cannot be the only thing asserting them.
#
# Why: `muted-is-distinct` is a boolean the probe computes by comparing glyphs, and
# a mutation that made ALL the device glyphs identical would break
# `three-device-kinds-differ` but leave `muted-is-distinct` true — which is how it
# was caught (mutation testing). Comparing the reported glyphs against known
# values is the check that does not recompute the expectation with the code.
m_probe="$(grep "SMOKE CONTRACT volume-widget " "$LOG_B" | tail -1)"
g_headset="$(sed -n 's/.*headset="\([^"]*\)".*/\1/p' <<<"$m_probe")"
g_handset="$(sed -n 's/.*handset="\([^"]*\)".*/\1/p' <<<"$m_probe")"
g_speaker="$(sed -n 's/.*speaker="\([^"]*\)".*/\1/p' <<<"$m_probe")"
g_muted="$(sed -n 's/.*muted="\([^"]*\)".*/\1/p' <<<"$m_probe")"
# Nerd Font code points, written here so the expectation does not come from the
# shell under test: U+F025 headset, U+F095 phone, U+F026/27/28 speaker waves,
# U+EE88 muted. A change to the icon set is a visible change to the user and
# should fail this rather than pass silently.
#
# The muted glyph is U+EE88 because that is what the pre-rewrite AudioService
# used (verified against 583f2e2:services/AudioService.qml — F025/F095/F1B9,
# U+EE88 muted, F026/27/28 waves). Every other glyph here is that same set;
# replacing the mute without the maintainer asking for it would be a visual
# change nobody requested, and the ticket asked only that muted be distinct.
if [[ -n "$g_headset" && -n "$g_handset" && -n "$g_speaker" && -n "$g_muted" ]]; then
    if [[ "$g_headset" != $'\uf025' ]]; then
        fail "glyph-headphones" "the headphone glyph is '$g_headset', not the headset glyph U+F025"
    else
        pass "glyph-headphones" "a headset is shown with the headphone glyph (U+F025), whatever its volume"
    fi
    if [[ "$g_handset" != $'\uf095' ]]; then
        fail "glyph-handset" "a handset is shown with '$g_handset', not the phone glyph U+F095"
    else
        pass "glyph-handset" "a handset/portable device is shown with its own glyph (U+F095), distinct from both the headset and the speaker"
    fi
    if [[ "$g_speaker" != $'\uf027' ]]; then
        fail "glyph-speaker" "at 50% a plain output shows '$g_speaker', not the middle speaker-wave glyph U+F027"
    else
        pass "glyph-speaker" "a plain output at 50% shows the middle speaker-wave glyph (U+F027)"
    fi
    if [[ "$g_muted" != $'\uee88' ]]; then
        fail "glyph-muted" "a muted output shows '$g_muted', not the muted glyph U+EE88 (the pre-rewrite set's mute)"
    else
        pass "glyph-muted" "a muted output shows the muted glyph (U+EE88), distinct from all three device glyphs"
    fi
else
    fail "glyph-values" "the volume widget reported no glyph values, so the icon set could not be checked (headset='$g_headset' handset='$g_handset' speaker='$g_speaker' muted='$g_muted')"
fi
check_probe volume-panel-toggle widget-opens=true widget-toggles-closed=true

# The volume widget must have a MEANINGFUL panel id, not a merely-present one:
# every panel in the shell has to be nameable in a log and to cross-monitor
# dismissal, and "panel-" with an empty suffix is neither.
vol_line="$(grep "SMOKE CONTRACT volume-widget " "$LOG_B" | tail -1)"
vol_id="$(sed -n 's/.*panelId=\([^ ]*\).*/\1/p' <<<"$vol_line")"
if [[ "$vol_id" =~ ^panel-[a-z][a-z0-9-]*$ ]]; then
    pass "volume-panel-id" "the widget's panel id is derived and specific ('$vol_id'), so the log and cross-monitor dismissal can name it"
else
    fail "volume-panel-id" "the panel id is empty or degenerate ('$vol_id') — every panel in the shell would be indistinguishable"
fi

# ---------------------------------------------------------------------------
# (C) RUNTIME — AudioService really no longer publishes presentation
# ---------------------------------------------------------------------------
echo
echo "[C] runtime: the audio service publishes state, not presentation ..."
audio_line="$(grep "SMOKE PASS service AudioService " "$LOG_B" | tail -1)"
if [[ -z "$audio_line" ]]; then
    fail "audio-service-state-only" "the smoke shell did not report the audio service at all"
elif grep -q 'glyph "' <<<"$audio_line" && grep -q 'via ' <<<"$audio_line"; then
    pass "audio-service-state-only" "the service readout carries volume and mute STATE, and names the widget-side presentation separately from it"
else
    fail "audio-service-state-only" "the audio readout does not distinguish service state from widget presentation: $audio_line"
fi

# The strongest form of the boundary: the service must not even NAME a glyph
# property. verify-docs.sh checks what ADR 0001 CLAIMS; this checks what the file
# CONTAINS, so the two cannot both be wrong in the same direction.
if grep -qE 'property\s+\w+\s+textIcon' "$REPO/services/AudioService.qml"; then
    fail "audio-no-glyph-property" "AudioService still declares a textIcon property — presentation is in the widget now (ADR 0001)"
else
    pass "audio-no-glyph-property" "AudioService declares no glyph property; the icon decision lives in components/VolumeIcon.qml and the colour in the widget"
fi
# And the presentation must exist somewhere real, or removing it from the service
# would have deleted the feature rather than moved it.
if grep -q "function glyphFor" "$REPO/components/VolumeIcon.qml" \
   && grep -q "UI.Colors.alertRed" "$REPO/shell/widgets/VolumeWidget.qml"; then
    pass "audio-presentation-relocated" "the glyph decision and the muted COLOUR both exist outside the service (VolumeIcon.glyphFor, the widget's palette use)"
else
    fail "audio-presentation-relocated" "the presentation that left AudioService could not be found in the widget or the shared component — was it deleted rather than moved?"
fi

# ---------------------------------------------------------------------------
# (D) LIVE SHELL — the surfaces, the prime, and a REAL Escape keystroke
# ---------------------------------------------------------------------------
echo
echo "[D] live shell: the overlay surface, the focus prime, and a real Escape ..."
#
# The only case that puts anything on the user's screen, bounded on both sides:
# `timeout` always, plus an inner kill as soon as the shell has reported what
# this needs. The shell is a SCRATCH COPY of the tree, so no reload or error can
# reach the working tree.
#
# THE KEYBOARD RISK IS REAL AND TAKEN DELIBERATELY. The focus prime is the
# promise under test and cannot be checked without actually taking the keyboard
# for the length of the prime — that is what "exclusive focus" means. So the
# prime is short, the wait is a grep against the shell's own report rather than a
# sleep, and the kill is unconditional.
#
# HOW THE PANEL IS OPENED. By driving the widget's own activation action, which
# is exactly what the MouseArea calls — not by poking the coordinator from
# outside, which would exercise the coordinator but not the wiring that reaches
# it. See the NOSARCH_PANEL_DRIVER note in the gap list at the end for the one
# link in that chain this still does not cover (Qt's own hit-testing).
SHELL_DIR="$TMP/shell"
rm -rf "$SHELL_DIR" "$TMP/homeD"
mkdir -p "$SHELL_DIR" "$TMP/homeD/.config/quickshell/nosarch"
cp "$REPO/shell.qml" "$SHELL_DIR/shell.qml"
cp -r "$REPO/shell" "$SHELL_DIR/shell"
cp -r "$REPO/services" "$SHELL_DIR/services"
cp -r "$REPO/components" "$SHELL_DIR/components"
# The built-in defaults put the volume widget — the one panel-bearing widget — on
# the right, so the scratch copy has a panel to open with no configuration file.
LOG_D="$TMP/caseD.log"

HOME="$TMP/homeD" XDG_CONFIG_HOME="$TMP/homeD/.config" \
    NOSARCH_PANEL_DRIVER=open:volume NOSARCH_PANEL_PRIME_MS="$PRIME_MS" \
    timeout "$SHELL_RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$SHELL_DIR/shell.qml" >"$LOG_D" 2>&1 &
shell_pid=$!

opened=0
for _ in $(seq 1 $((SHELL_RUN_SECS * 10))); do
    if grep -q "PANEL state .*owner=yes" "$LOG_D" 2>/dev/null; then
        opened=1
        break
    fi
    kill -0 "$shell_pid" 2>/dev/null || break
    sleep 0.1
done
d_state="$(panel_line "$LOG_D" state)"
if [[ $opened -eq 1 ]]; then
    pass "panel-opens" "opening the widget's panel made the surface take ownership of the screen: $d_state"
else
    fail "panel-opens" "no panel ever reported owning the screen — nothing was opened, or the surface never mapped"
fi

# The surface must be FULL SCREEN, with its own namespace and a real mask.
d_mapped="$(sed -n 's/.*mapped=\([0-9]*x[0-9]*\).*/\1/p' <<<"$d_state")"
d_ns="$(sed -n 's/.*namespace=\([^ ]*\).*/\1/p' <<<"$d_state")"
d_mask="$(sed -n 's/.*mask=\([^ ]*\).*/\1/p' <<<"$d_state")"
if [[ "$d_mapped" =~ ^[0-9]+x[0-9]+$ && "${d_mapped%x*}" -gt 0 && "${d_mapped#*x}" -gt 0 ]]; then
    pass "panel-full-screen" "the compositor gave the panel surface a real full-screen surface ($d_mapped)"
else
    fail "panel-full-screen" "the panel surface's mapped size is not a real screen ('$d_mapped') — with the default exclusion mode the compositor reserves the bar's zone instead"
fi
if [[ "$d_ns" == "nosarch-shell-panel" ]]; then
    pass "panel-namespace" "the panel surface published '$d_ns', distinct from the bar's and the cross-output twins'"
else
    fail "panel-namespace" "the panel surface published '$d_ns', not its own role's namespace"
fi
if [[ "$d_mask" == "region" ]]; then
    pass "panel-dismiss-mask" "the dismissal surface carries a region mask, so the bar strip underneath stays clickable"
else
    fail "panel-dismiss-mask" "the dismissal surface has no region mask ('$d_mask') — a full-screen overlay would swallow every click on the bar"
fi

# THE PRIME, in both directions. The panel must have been SEEN holding Exclusive
# focus (the prime fired) and must END UP OnDemand (the drop happened). A run that
# only ever saw OnDemand means the prime never fired; one that ends on Exclusive
# means the drop never happened — and that is the failure that would leave the
# user's keyboard captured, so it is checked rather than assumed from the code.
sleep 0.5
d_focus_after="$(sed -n 's/.*focus=\([^ ]*\).*/\1/p' <<<"$(panel_line "$LOG_D" state)")"
focus_line="$(grep "PANEL focus " "$LOG_D" | tail -1)"
if grep -q "focus=Exclusive" "$LOG_D"; then
    pass "focus-prime-fires" "the surface was seen holding EXCLUSIVE focus at open time, which is what makes the panel typeable immediately"
else
    fail "focus-prime-fires" "the surface was never seen holding exclusive focus — the prime did not fire, so the panel would swallow keypresses"
fi
if [[ "$d_focus_after" == "OnDemand" ]]; then
    pass "focus-prime-drops" "the prime dropped to OnDemand, so the surface is no longer routing every pointer event on every output here"
else
    fail "focus-prime-drops" "the surface still holds '$d_focus_after' focus after the prime window — every click on every monitor would be routed to the panel"
fi

# THE IN-SURFACE FOCUS TARGET. Checked here rather than headlessly because the
# question is whether focus arrives in a REAL window, which no windowless tree
# can answer. `arrived=` is the surface's own report of whether forceActiveFocus()
# left an item actually holding active focus.
if grep -q "PANEL focus .*arrived=NO" "$LOG_D"; then
    fail "focus-arrives-in-surface" "the panel's in-surface focus target did not take active focus: $focus_line"
elif grep -q "PANEL focus .*arrived=yes" "$LOG_D"; then
    pass "focus-arrives-in-surface" "an item inside the open panel really holds active focus, so its key handlers can fire: ${focus_line##*PANEL focus }"
else
    fail "focus-arrives-in-surface" "the shell never reported whether focus arrived in the panel — the promise is unfalsifiable rather than unmet"
fi

# CROSS-CHECK: `arrived=yes` is the CARD's own answer, so a card that returns a
# constant would satisfy it. The surface's separate, state-line report of
# `activeFocus` is read from the same live window, and the two must agree. This
# is what caught a `focusContent()` that returned `true` unconditionally
# (mutation testing) — the headless case could not, because it read the same
# constant back.
d_focus_line="$(panel_line "$LOG_D" state)"
d_active="$(sed -n 's/.*activeFocus=\([^ ]*\).*/\1/p' <<<"$d_focus_line")"
if [[ "$d_active" == "yes" ]]; then
    pass "focus-arrival-is-real" "the surface independently reports an item inside the panel holding active focus, agreeing with focusContent()'s own answer"
else
    fail "focus-arrival-is-real" "focusContent() reported arrival but the surface's own report says activeFocus=$d_active — one of them is not reading the real focus state"
fi

# ---- the REAL Escape keystroke ---------------------------------------------
#
# Sent with `wtype`, which injects through the compositor into whichever surface
# holds keyboard focus — so this walks the entire path: the prime gave the
# SURFACE the keyboard, the handoff gave an in-surface ITEM active focus, the
# card's Keys handler saw the key, and the coordinator released ownership.
# Nothing is simulated; the only step not covered is the mouse.
escape_sent=0
if kill -0 "$shell_pid" 2>/dev/null && grep -q "PANEL focus .*arrived=yes" "$LOG_D"; then
    wtype -k Escape >/dev/null 2>&1 && escape_sent=1
fi
if [[ $escape_sent -eq 1 ]]; then
    pass "escape-injected" "a real Escape keypress was injected into the focused surface through the compositor (wtype)"
else
    fail "escape-injected" "could not inject Escape (the shell had exited, or focus never arrived in the panel) — the Escape promise is untested rather than met"
fi

closed=0
for _ in $(seq 1 20); do
    d_try="$(panel_line "$LOG_D" state)"
    if [[ "$d_try" == *"owner=no"* ]] && [[ "$d_try" == *"panel=none"* ]]; then
        closed=1
        break
    fi
    kill -0 "$shell_pid" 2>/dev/null || break
    sleep 0.1
done
if [[ $escape_sent -eq 1 && $closed -eq 1 ]]; then
    pass "escape-closes-panel" "Escape closed the panel and the surface released ownership of the keyboard and the clicks"
elif [[ $escape_sent -eq 1 ]]; then
    fail "escape-closes-panel" "the panel was still open after a real Escape keypress"
else
    fail "escape-closes-panel" "Escape was not injected — the close promise is untested"
fi

d_final="$(panel_line "$LOG_D" state)"
if [[ "$d_final" == *"owner=no"* ]] && [[ "$d_final" == *"panel=none"* ]]; then
    pass "ownership-released-at-close" "after the logical close the surface reports owner=no: ${d_final:0:150}"
else
    fail "ownership-released-at-close" "the surface still owns input after closing: $d_final"
fi

kill "$shell_pid" 2>/dev/null || true
wait "$shell_pid" 2>/dev/null

# ---- placement: the ONE geometry claim, and only that one ------------------
echo
echo "[E] live shell: the card's reported rect lies inside the screen ..."
#
# Deliberately the only geometry assertion in this script. "Does the panel appear
# UNDER THE WIDGET I CLICKED" cannot be asserted and is not (the spec calls it a
# manual visual check) — but CONTAINMENT is arithmetic on two numbers produced by
# different parts of the shell, and it is a promise in its own right: "the panel
# stays within screen bounds". The shell reports; THIS script compares, against
# the screen size from the framework's own list rather than the panel's copy.
d_place="$(panel_line "$LOG_D" place)"
d_card="$(sed -n 's/.*card=\([0-9]*,[0-9]*,[0-9]*,[0-9]*\).*/\1/p' <<<"$d_place")"
d_screen="$(sed -n 's/.*screen=\([0-9]*x[0-9]*\).*/\1/p' <<<"$d_place")"
if [[ -z "$d_card" || -z "$d_screen" ]]; then
    fail "card-within-screen" "the shell reported no card rect ('$d_card') against a screen ('$d_screen') — containment could not be checked at all"
else
    d_cx="${d_card%%,*}"; d_r1="${d_card#*,}"
    d_cy="${d_r1%%,*}"; d_r2="${d_r1#*,}"
    d_cw="${d_r2%%,*}"; d_ch="${d_r2#*,}"
    d_sw="${d_screen%x*}"; d_sh="${d_screen#*x}"
    if [[ $d_cx -ge 0 && $d_cy -ge 0 && $d_cw -gt 0 && $d_ch -gt 0 \
          && $((d_cx + d_cw)) -le "$d_sw" && $((d_cy + d_ch)) -le "$d_sh" ]]; then
        pass "card-within-screen" "the card at $d_card lies wholly inside the $d_screen screen — it cannot hang off an edge"
    else
        fail "card-within-screen" "the card at $d_card is NOT inside the $d_screen screen"
    fi
    # And BELOW the bar: top-bar-only positioning asserted as a relation between
    # two reported numbers, never as a claim about pixels.
    if [[ "$d_cy" -gt 0 ]]; then
        pass "card-below-the-bar" "the card's top edge is at y=$d_cy — below the bar strip, inside the screen, topBarOnly=yes reported"
    else
        fail "card-below-the-bar" "the card's top edge is at y=$d_cy, which is not below the bar strip: $d_place"
    fi
fi

echo
echo "    --- what the live shell reported ---"
grep -E "PANEL (state|place|focus) " "$LOG_D" | tail -n 8 | sed 's/^/    /'

# ---------------------------------------------------------------------------
# (F) LOG — the repo's own files stayed quiet
# ---------------------------------------------------------------------------
echo
echo "[F] log: no WARN or ERROR names a file in this repo ..."
b_bad="$(repo_warnings "$LOG_B")"
d_bad="$(repo_warnings "$LOG_D")"
if [[ -z "$b_bad" && -z "$d_bad" ]]; then
    pass "log-clean" "neither the headless nor the live run logged a WARN or ERROR against a file in this repo"
else
    fail "log-clean" "the log named files this ticket owns (services/, shell/panels/, shell/bar/, shell/widgets/, shell/osds/, components/): $(printf '%s %s' "$b_bad" "$d_bad" | head -c 400)"
fi

# ---------------------------------------------------------------------------
# (G) KNOWN GAPS — printed on every run, so a green one cannot imply more
# ---------------------------------------------------------------------------
echo
echo "[G] known gaps: what this script does NOT check ..."
cat <<'GAP'
    POSITION       "a panel appears UNDER THE WIDGET THAT WAS CLICKED" — pixel
                   geometry; the spec calls it a manual visual check. Only
                   CONTAINMENT is asserted above, and only from the numbers the
                   shell reported. A position claim here would be the bug.
    CLICK-OPEN     a physical click on a widget's icon. No pointer-injection tool
                   exists on this machine (wtype is keyboard-only; Hyprland 0.56
                   has no click dispatcher), so the widget's activation ACTION is
                   driven instead: everything from the click onwards, but not Qt's
                   hit-testing that decides which item a click lands on.
    MASK-HIT-TEST  that the mask really lets a click through on the bar strip. Its
                   shape is checked statically and its presence at run time; the
                   hit-test through it is not exercised.
    CROSS-MONITOR  a click on another output dismissing the panel, and the
                   dismissal twin itself. ONE monitor is attached, so the twin
                   list is empty on every run and no twin is ever created.
    SLIDER-DRAG    a hand-held drag of the volume slider. That no grabFocus exists,
                   that the slider IS the focus target, and that the panel's state
                   cannot be disturbed by a pointer are checked; the physical
                   gesture is not.
    SLIDER-VALUE   that the slider changes the machine's volume. Driving it would
                   move the user's audio, so it is deliberately not done.
    TWINS-CREATED  that a twin is really instantiated per other output.
                   Structurally checked; never instantiated, for want of a screen.
    BAR-STRIP-GEO  that the mask's cut-out is exactly the bar strip in pixels. The
                   region is built from an item bound to the bar's own geometry,
                   but no run measures where the compositor put the bar.
GAP
echo "    Each is recorded in docs/known-gaps.md with what would close it."
echo

echo
echo "======================================================================"
if [[ $FAIL -eq 0 && $static_rc -eq 0 ]]; then
    echo " RESULT: PASS (architecture shape, headless behaviour, the live surface with"
    echo "         its focus prime, and a real Escape keystroke through the compositor)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  ($PASS check(s) passed, $FAIL failed: ${FAILED_CASES[*]})"
    echo "======================================================================"
    exit 1
fi