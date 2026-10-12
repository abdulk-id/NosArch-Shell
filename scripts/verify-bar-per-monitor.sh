#!/usr/bin/env bash
#
# verify-bar-per-monitor.sh — verification for ticket 10.
#
#   "My bar appears on every attached monitor, and appears or disappears as I
#    plug monitors in and out at runtime, without restarting the shell. Every
#    monitor gets the same layout. The different-arity popup-state calls that
#    let the network panel ignore its monitor are gone."
#
# FOUR kinds of check, because four kinds of promise:
#
#   (A) STATIC — the SHAPE of per-monitor. One PanelWindow per Variants entry;
#               the model is the LIVE attached-screen list and never a snapshot
#               of it; each delegate pins its window to its own screen; the
#               bar listens to the signal a hot-plug arrives on; and every
#               layer-shell surface in the tree publishes a namespace no other
#               surface role shares.
#   (B) STATIC — the popup-state ARITY split is gone. No popup-state member
#               anywhere takes a screen, no call site passes one, and the state
#               object is instantiated INSIDE the per-screen delegate rather
#               than once globally.
#   (C) RUNTIME — the real shell, launched under a private bus, reporting what
#               the compositor actually gave it: the attached-screen count from
#               the framework, the live bar-window count from the bar's own
#               Variants, the screens those windows are pinned to, and the
#               namespace they published. Then the pairing each surface against
#               ITS screen, so "one bar per monitor" is a measurement.
#   (D) SCOPE — the multi-monitor KNOWN GAP, reported rather than papered over.
#               The script states how many screens it actually saw, and refuses
#               to pass at all if it cannot determine that number. A check that
#               silently succeeds because there happens to be one monitor is
#               worse than no check, so this one is loud in both directions.
#
# WHAT IS DELIBERATELY NOT CLAIMED
#
#   Hot-plug itself is NOT exercised: attaching and detaching an output would
#   mean reconfiguring the live desktop's monitors, which is exactly what this
#   work is forbidden to do. What IS checked is everything leading up to it —
#   the model is the live list, the shell is connected to screensChanged, and
#   surface count tracks screen count — and the residue is recorded in
#   AGENTS.md ("Multi-monitor is structured for, unverified") and in
#   docs/known-gaps.md. See section (D) for how the gap is reported at runtime.
#
# SAFETY (the live desktop is running): the only launch is under
# `dbus-run-session`, so the shell's NotificationServer cannot take
# org.freedesktop.Notifications away from the real swaync. HOME *and*
# XDG_CONFIG_HOME are both pointed at scratch directories — XDG_CONFIG_HOME is
# set in this environment, so redirecting HOME alone would point the
# configuration reader straight back at the real ~/.config. Every launch is
# bounded by a timeout and killed; only this script's own shells are killed,
# matched on this scratch directory's unique path. The bar DOES flash on screen
# briefly during case (C), exactly as verify-bar-surface.sh does.
#
# Exit status: 0 only if every check holds.

set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

RUN_SECS="${RUN_SECS:-30}"
TMP="$(mktemp -d /tmp/opencode/qs-permonitor.XXXXXX)"
LOG="$TMP/shell.log"
SHELL="$TMP/shell"

PASS=0
FAIL=0
FAILED_CASES=()

cleanup() {
    # Kill only THIS script's shell: its cmdline carries this scratch path.
    pkill -f "quickshell.*${SHELL}/shell.qml" 2>/dev/null || true
    pkill -f "dbus-run-session.*${SHELL}/shell.qml" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 10 verification — one bar per attached monitor, per-screen"
echo "                          surfaces, and no popup-state arity split"
echo " repo: $REPO"
echo "======================================================================"

record() {  # record <case-name> <checker-output>
    local name="$1" out="$2"
    echo "$out" | sed 's/^/    /'
    if [[ "$out" == *"FAIL"* ]]; then
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("$name")
        PASS=$((PASS + $(grep -c '^PASS' <<<"$out")))
    else
        PASS=$((PASS + $(grep -c '^PASS' <<<"$out")))
    fi
}

check() {  # check <case-name> [args...] — reads $LOG
    local name="$1"
    shift
    LOG="$LOG" python3 - "$name" "$@" <<'PY'
import os, re, sys, pathlib

name = sys.argv[1]
extra = sys.argv[2:]
logp = pathlib.Path(os.environ["LOG"])
lines = logp.read_text(errors="replace").splitlines() if logp.exists() else []
out = []


def say(ok, detail):
    out.append(f"{'PASS' if ok else 'FAIL'} {name}: {detail}")


def tokens(line, kind):
    m = re.search(rf"\bBAR {kind} (.*)", line)
    if not m:
        return None
    return dict(t.split("=", 1) for t in m.group(1).split() if "=" in t)


def reports(kind):
    """Every BAR <kind> line, as dicts, in order."""
    got = []
    for ln in lines:
        kv = tokens(ln, kind)
        if kv:
            got.append(kv)
    return got


def num(kv, key):
    if kv is None or key not in kv:
        return None
    try:
        return float(kv[key])
    except ValueError:
        return None


def repo_log_clean():
    """Every WARN/ERROR naming a file in this repo, bar files and entrypoint only.

    The assembled shell also draws the wallpaper and the pre-rewrite widgets that
    ticket 18 retires; this ticket does not decide whether those are clean.
    """
    qline = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\s+(WARN|ERROR)\s+(.*)$")
    repo_file = re.compile(r"@([^\s:\[]+)\[")
    bad = []
    for ln in lines:
        m = qline.match(ln)
        if not m:
            continue
        f = repo_file.search(m.group(2))
        if not f:
            continue
        name = f.group(1)
        if name == "shell.qml" or name.startswith(("shell/bar/", "shell/widgets/")):
            bad.append(name + ": " + m.group(2).strip())
    return bad


# ---------------------------------------------------------------------------

if name == "caseC-per-screen-surfaces":
    scr = reports("screens")
    if not scr:
        say(False, "the shell never reported the attached screens — there is nothing to "
                   "compare the bar against, and a check that cannot see them must not pass")
        for ln in out:
            print(ln)
        sys.exit(1)

    # The LAST report is the settled one; the count settles over more than one pass.
    s = scr[-1]
    attached = num(s, "attached")
    alive = num(s, "windows")
    named = [p for p in (s.get("names") or "").split(",") if p]

    say(attached is not None and attached > 0,
        f"the shell reports the framework's own attached-screen count: attached={s.get('attached')} "
        f"({', '.join(n.split('/')[0] for n in named) or 'none named'})")
    say(alive is not None and alive == attached,
        f"one bar window per attached screen: windows={s.get('windows')} "
        f"attached={s.get('attached')}"
        + ("" if alive == attached else " — a monitor with no bar, or a bar with no monitor"))
    say(len(named) == len(set(n.split("/")[0] for n in named)),
        f"each live window is pinned to a DISTINCT screen: {s.get('names')}")

    # Each window's own geometry must be a real screen's geometry, read off the
    # ShellScreen the window is bound to. A window that did not follow its
    # delegate would report the wrong name or nothing at all. Parsed STRICTLY:
    # an entry that does not parse is a FAILURE, never a skip — a skip here
    # would leave the per-monitor claim unchecked while the run still reported
    # success, which is the failure mode this whole script exists to avoid.
    parsed = []
    for n in named:
        m = re.fullmatch(r"([^\s/]+)/(\d+)x(\d+)([+-]\d+)([+-]\d+)@([^\s@]+)", n)
        if m is None:
            say(False, f"a live-window entry is malformed, so it cannot be checked against "
                       f"a screen at all: {n}")
            continue
        parsed.append(m)
    say(len(parsed) == len(named),
        f"every live window's entry parses as name/WxH+X+Y@namespace: {s.get('names')}")

    # The namespace every bar window published. One role, one namespace: that is
    # what makes per-monitor surfaces tellable apart from panels and from the
    # cross-monitor dismissal twins ticket 11 is about to add.
    ns = {n.rsplit("@", 1)[1] for n in named if "@" in n}
    say(len(ns) == 1,
        f"every bar surface publishes ONE namespace, so the surface class is "
        f"identifiable: {sorted(ns)}")
    say(bool(ns) and not ns & {"nosarch-shell-top-island"},
        f"the new bar does not reuse the pre-rewrite bar's namespace: {sorted(ns)}")

    # ---- pair every reported surface against its own screen ----------------
    surf = {}
    for kv in reports("surface"):
        if "surface" in kv:
            surf[kv["surface"]] = kv          # last report per surface = settled
    say(bool(surf),
        f"the bar reported its own surface geometry for "
        f"{len(surf)} surface(s): {sorted(surf)}")
    for m in parsed:
        sname = m.group(1)
        sw, sh = float(m.group(2)), float(m.group(3))
        sx, sy = m.group(4), m.group(5)
        kv = surf.get(sname)
        if kv is None:
            say(False, f"no bar surface was reported for screen {sname}")
            continue
        got_w = num(kv, "width")
        margin = num(kv, "margin")
        # 0.5px, not 1px: the compositor hands out integer surface widths and
        # the insets are integer pixels, so this arithmetic is exact and a real
        # mismatch is at least a whole pixel. A 1px tolerance was measured
        # swallowing a deliberate 1px error during a mutation check.
        say(got_w is not None and margin is not None
            and abs(got_w - (sw - 2 * margin)) <= 0.5,
            f"[{sname}] the surface the compositor gave the bar is THIS screen's width less "
            f"the two floating insets: {got_w:g}px measured = {sw:g}x{sh:g} at {sx},{sy} "
            f"- 2×{margin:g}px")
        got_h = num(kv, "height")
        say(got_h is not None and got_h > 0,
            f"[{sname}] the surface has a real height: {got_h:g}px")

    bad = repo_log_clean()
    say(not bad,
        "no WARN/ERROR names the bar's files or shell.qml while the bar is mapped on a real "
        "screen" + ("" if not bad else " — " + "; ".join(bad[:3])))

elif name == "caseD-known-gap":
    scr = reports("screens")
    s = scr[-1] if scr else None
    attached = num(s, "attached") if s else None
    if attached is None:
        say(False, "the number of attached screens could not be determined from the log — "
                   "this script will not report a multi-monitor result it does not have")
    elif attached < 1:
        say(False, f"no screen was attached during the run (attached={attached:g}); the "
                   "per-screen claims above could not be checked at all")
    elif attached == 1:
        say(True,
            f"KNOWN GAP (recorded, not closed): this run saw exactly ONE screen "
            f"({attached:g} attached), so NOTHING here exercised a second monitor. "
            f"What was verified is the leading half of hot-plug — the model is the live "
            f"attached-screen list, the shell is connected to screensChanged, and the "
            f"surface count tracks the screen count. The other half — a bar actually "
            f"appearing and disappearing as an output is attached and detached — is "
            f"UNVERIFIED and is recorded in AGENTS.md and docs/known-gaps.md. "
            f"Closing it needs a machine with two monitors.")
    else:
        say(True,
            f"attached={attached:g} screens — this run DID cover more than one monitor, "
            f"which the recorded known gap says was not possible on the development machine")

for ln in out:
    print(ln)
sys.exit(1 if any(l.startswith("FAIL") for l in out) else 0)
PY
}

# ---------------------------------------------------------------------------
# (A) STATIC — the shape of per-monitor
# ---------------------------------------------------------------------------
echo
echo "[A] static: one window per attached screen, modeled on the LIVE screen list ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib

repo = pathlib.Path(sys.argv[1])
problems = []


def strip_comments(text):
    """QML with // and /* */ comments removed — these checks are about CODE."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


barpath = repo / "shell/bar/Bar.qml"
if not barpath.is_file():
    print("    FAIL — shell/bar/Bar.qml does not exist")
    sys.exit(1)
bar = strip_comments(barpath.read_text())

# ---- a window per entry, from Variants, bound to its own screen -------------
if "Variants" not in bar:
    problems.append("Bar.qml has no Variants — the bar would not follow the set of attached "
                    "screens, so it would appear on one monitor only and never change")
if not re.search(r'model\s*:\s*[^\n]*', bar):
    problems.append("Bar.qml binds no model to its Variants")
if "PanelWindow" not in bar:
    problems.append("Bar.qml declares no PanelWindow — the bar has no surface")
if not re.search(r'screen\s*:\s*modelData\b', bar):
    problems.append("Bar.qml does not bind each window to its own delegate's screen "
                    "(screen: modelData) — a window that does not follow its model entry "
                    "would be drawn on the wrong monitor")

# ---- the model must be the LIVE list, never a snapshot of it ---------------
#
# The single most important static claim here. `Quickshell.screens.slice(0)` or
# `[...Quickshell.screens]` produces exactly the same bar on every machine and
# on every hot-plug — the snapshot is taken once at startup and never follows
# an output arriving. Nothing at run time could tell the difference with one
# monitor attached, which is exactly why it is checked here and not in the log.
if "Quickshell.screens" not in bar:
    problems.append("Bar.qml never mentions Quickshell.screens — the model is not the "
                    "attached-screen list")
for needle, why in (
    ("Quickshell.screens.slice", "a .slice() of the screen list is a snapshot taken once"),
    ("[...Quickshell.screens", "a spread of the screen list is a snapshot taken once"),
    ("Array.from(Quickshell.screens", "Array.from() of the screen list is a snapshot"),
    ("Object.keys(Quickshell.screens", "Object.keys() of the screen list is a snapshot"),
):
    if needle in bar:
        problems.append(f"Bar.qml takes a SNAPSHOT of the attached screens ({needle}) — "
                        f"{why}; plugging a monitor in would change nothing")

# ---- the shell is connected to the signal hot-plug arrives on --------------
if not re.search(r"onScreensChanged", bar):
    problems.append("Bar.qml has no handler on Quickshell's screensChanged — the shell "
                    "would not notice an output arriving or leaving even though its model "
                    "would follow one")

# ---- namespace discipline, tree-wide --------------------------------------
#
# Under the panel architecture (ticket 11) per-monitor surfaces, panel surfaces
# and the cross-monitor dismissal twins all have to be tellable apart. A
# surface with no namespace cannot be told from anything, and two surface roles
# sharing one cannot either. So: every namespace in the tree is collected and
# each must be claimed by exactly one surface role.
by_ns = {}
for f in sorted(repo.rglob("*.qml")):
    if {".git", ".scratch", ".agents", ".zed"} & {p.name for p in f.parents}:
        continue
    text = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
    for ns in re.findall(r'WlrLayershell\.namespace\s*:\s*"([^"]+)"', text):
        by_ns.setdefault(ns, []).append(str(f.relative_to(repo)))

print("    layer-shell namespaces in the tree:")
for ns, owners in sorted(by_ns.items()):
    print(f"      - {ns}: {', '.join(owners)}")
dupes = {ns: o for ns, o in by_ns.items() if len(o) > 1}
if dupes:
    for ns, owners in sorted(dupes.items()):
        problems.append(f"namespace {ns} is published by more than one surface file "
                        f"({', '.join(owners)}) — surfaces in different roles must be "
                        f"tellable apart")
if not by_ns:
    problems.append("no surface in the tree publishes a namespace at all")

if problems:
    print("    FAIL — the bar does not have the per-monitor shape the ticket claims:")
    for p in problems:
        print("      ! " + p)
    sys.exit(1)
print("    PASS — one PanelWindow per Variants entry, bound to its own screen, modeled on "
      "the live attached-screen list, with every surface role publishing a distinct namespace")
PY
static_a=$?
if [[ $static_a -ne 0 ]]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("static-per-monitor-shape")
fi

# ---------------------------------------------------------------------------
# (B) STATIC — the popup-state arity split is gone
# ---------------------------------------------------------------------------
echo
echo "[B] static: no popup-state object takes a screen, and the state is per-surface ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib

repo = pathlib.Path(sys.argv[1])
problems = []


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def qml_files():
    for f in sorted(repo.rglob("*.qml")):
        if {".git", ".scratch", ".agents", ".zed"} & {p.name for p in f.parents}:
            continue
        yield f


# The mechanism the ticket names: a SINGLE global object keyed on monitor-name
# strings, with an `isActive(id, screen)` that silently treats a missing screen
# as "any screen". That one branch is the bug — one widget calling with two
# arguments and another with one cannot disagree loudly, so they disagree
# quietly, and the widget that passes none shows its panel on every monitor.
for f in qml_files():
    text = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
    rel = str(f.relative_to(repo))
    if "activeScreen" in text:
        problems.append(f"{rel} stores a screen NAME in its popup state (activeScreen) — "
                        f"popup state keyed on a monitor-name string is what let one widget "
                        f"ignore its monitor")
    if re.search(r"function\s+isActive\s*\(\s*\w+\s*,", text):
        problems.append(f"{rel} declares isActive(id, <second argument>) — the arity split "
                        f"is still here: a caller may omit the screen and be answered "
                        f"'active on any screen'")
    if re.search(r"function\s+set\s*\(\s*\w+\s*,", text) and "PopupState" not in f.name:
        problems.append(f"{rel} declares set(id, <second argument>) — a popup-state setter "
                        f"that takes a screen is the arity split")
    # Any call site that passes a screen to the popup state.
    for m in re.finditer(r"popupState\w*\.(\w+)\s*\(([^)]*)\)", text):
        args = [a for a in m.group(2).split(",") if a.strip()]
        if len(args) > 1:
            problems.append(f"{rel} calls popupState.{m.group(1)}() with {len(args)} arguments "
                            f"({m.group(2).strip()}) — the screen must not be a per-widget "
                            f"argument, or two widgets can disagree about it")
    # And the branch that made an omitted screen mean "any screen".
    if re.search(r"screen\s*===\s*undefined", text):
        problems.append(f"{rel} still branches on a missing screen argument — an omitted "
                        f"screen must be impossible, not silently widened to every monitor")

if "popupStateManager" in strip_comments((repo / "shell/topisland/TopIsland.qml").read_text()):
    problems.append("shell/topisland/TopIsland.qml still declares one global popupStateManager "
                    "— one object shared by every monitor's bar is the mechanism the ticket "
                    "replaces; the state belongs to a surface")

# ---- and the replacement must exist, and be per-surface --------------------
state = repo / "components/PopupState.qml"
if not state.is_file():
    problems.append("components/PopupState.qml does not exist — there is no per-surface "
                    "popup state for the mechanism to have been replaced by")
else:
    text = strip_comments(state.read_text())
    for member in ("toggle", "isActive", "close"):
        m = re.search(rf"function\s+{member}\s*\(([^)]*)\)", text)
        if not m:
            problems.append(f"PopupState.qml declares no {member}()")
            continue
        args = [a for a in m.group(1).split(",") if a.strip()]
        if member == "close":
            if args:
                problems.append(f"PopupState.close() takes {len(args)} argument(s); it takes none")
        elif len(args) != 1:
            problems.append(f"PopupState.{member}() takes {len(args)} argument(s); it takes "
                            f"exactly one (the panel's id), so no caller can supply or omit "
                            f"a screen")
    if "screen" in text:
        problems.append("PopupState.qml mentions a screen at all — the whole point is that "
                        "the surface it lives in IS the monitor, so there is nothing to pass")
    qmldir = (repo / "components/qmldir").read_text()
    if not re.search(r"^PopupState\s", qmldir, re.M):
        problems.append("components/qmldir does not register PopupState — a directory with a "
                        "qmldir hides any type it does not list")

    # Per-surface means per-surface: the state must be instantiated inside the
    # per-screen delegate, not once beside the Variants.
    top = repo / "shell/topisland/TopIsland.qml"
    if top.is_file():
        ttext = strip_comments(top.read_text())
        m = re.search(r"Variants\s*\{", ttext)
        if not m:
            problems.append("shell/topisland/TopIsland.qml has no Variants to scope the state to")
        else:
            delegate = ttext[m.start():]
            if not re.search(r"PopupState\s*\{", delegate):
                problems.append("no PopupState is created inside the per-screen delegate — "
                                "state held once outside the Variants is shared by every "
                                "monitor, which is the bug being replaced")

if problems:
    print("    FAIL — the popup-state arity split is still in the tree:")
    for p in problems:
        print("      ! " + p)
    sys.exit(1)
print("    PASS — popup state carries no screen, no call site passes one, and each surface "
      "holds its own")
PY
static_b=$?
if [[ $static_b -ne 0 ]]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("static-popup-arity")
fi

# ---------------------------------------------------------------------------
# (C) RUNTIME — the real shell on a real screen
# ---------------------------------------------------------------------------
echo
echo "[C] runtime: the real shell, one window per attached screen (isolated bus) ..."
rm -rf "$SHELL"
mkdir -p "$SHELL" "$TMP/home/.config"
cp "$REPO/shell.qml" "$SHELL/shell.qml"
cp -r "$REPO/shell" "$SHELL/shell"
cp -r "$REPO/services" "$SHELL/services"
cp -r "$REPO/components" "$SHELL/components"

HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" \
    timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$SHELL/shell.qml" >"$LOG" 2>&1 &
shell_pid=$!
for _ in $(seq 1 $((RUN_SECS * 10))); do
    # Wait for a SETTLED report with a non-zero window count: the bar is built
    # before the compositor has given its window a size, and the window count
    # settles a pass or two after the surface set does. Killing on the first
    # line would measure a half-built shell.
    grep -qE "BAR screens .*attached=[0-9]+ windows=[1-9][0-9]* " "$LOG" 2>/dev/null && break
    kill -0 "$shell_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$shell_pid" 2>/dev/null; then kill "$shell_pid" 2>/dev/null || true; fi
wait "$shell_pid" 2>/dev/null

if [[ ! -s "$LOG" ]]; then
    echo "    FAIL — the real shell produced no log at all"
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("runtime-no-log")
else
    record "caseC" "$(check caseC-per-screen-surfaces)"
    record "caseD" "$(check caseD-known-gap)"
    echo
    echo "    --- what the shell said about its screens ---"
    grep -E "BAR screens |BAR surface " "$LOG" | tail -n 8 | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $FAIL -eq 0 && $static_a -eq 0 && $static_b -eq 0 ]]; then
    echo " RESULT: PASS (one window per attached screen, live screen model, per-surface"
    echo "         popup state, distinct namespaces) — with the single-monitor known gap"
    echo "         reported above and recorded in AGENTS.md / docs/known-gaps.md"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  ($PASS assertion(s) passed, $FAIL failed: ${FAILED_CASES[*]})"
    echo " --- captured log tail (if any) ---"
    tail -n 30 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi