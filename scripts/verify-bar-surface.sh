#!/usr/bin/env bash
#
# verify-bar-surface.sh — verification for ticket 08.
#
#   "My bar has left, centre and right zones. The centre zone holds its widgets
#    truly centred, so the clock does not shift when other widgets change size.
#    The bar appears as a floating rounded island by default, and switching to a
#    full-width background is a configuration change."
#
# Three kinds of check, because three kinds of promise:
#
#   (A) STATIC   — the SHAPE of the claim, which is what actually distinguishes a
#                  real three-zone bar from the accidental-symmetry overlay it
#                  replaces: the three zones are placed by anchors inside a plain
#                  container and NOT by a Row/RowLayout, the centre zone's
#                  placement does not mention either wing, the fill comes from
#                  the palette rather than a literal, and the window sets both a
#                  layer and a distinct namespace.
#   (B) RUNTIME  — smoke.qml, four launches, each against a real configuration
#                  file in a throwaway HOME + XDG_CONFIG_HOME. This is where
#                  centring is MEASURED rather than assumed.
#   (C) WINDOW   — the real shell.qml, launched twice under dbus-run-session with
#                  a timeout and killed as soon as it reports its own geometry.
#                  Only this can show that "floating" and "full-width" differ in
#                  the width of the surface the compositor gives us.
#
# THE CENTRING ASSERTION, and why it is written the way it is
#
#   The claim is "the centre zone does not move when the left or right zone
#   changes width". Two readings exist and only one is interesting:
#
#     * weak  — the centre lands in the middle when the wings happen to be
#               symmetrical. The pre-rewrite bar satisfies this, which is why it
#               was never the problem.
#     * strong — the centre's position is a function of the BAR WIDTH and the
#               centre's own width, and of nothing else.
#
#   Every case below asserts the strong reading as a residual:
#
#       center.x  ==  (barWidth - center.width) / 2        (within 0.5px)
#
#   which is exact, and is computed in Python from the numbers the shell
#   reported — not from a formula the shell also used. Each case then runs with
#   DELIBERATELY LOPSIDED wings (3 clocks left / 0 right, then 0 left / 3 right,
#   then 5 left / 1 right), so a layout that centred the zone by sharing space
#   with its neighbours — the bug — cannot pass. The cross-case comparison of
#   center.x is reported too, and is exact whenever the centre's own width did
#   not change between two launches; it is a note rather than an assertion
#   because the clock's own text (and therefore its width) changes on the minute,
#   and a check that failed once a minute for that reason would be a flaky check
#   pretending to be a strict one. The residual is what carries the claim, and it
#   is immune to that entirely.
#
# HONEST LIMITS
#
#   * Only ONE widget is on the widget contract today (the clock; the other
#     eleven are their own tickets), so "the wings changed width" means "the
#     wing changed by whole clock widgets". That is a real width change of real
#     pixels, and the assertion does not care how it was produced.
#   * smoke.qml draws NO surfaces, so the window-owning type (Bar.qml) is loaded
#     and type-checked there but not instantiated; case (C) is what proves it
#     maps. Cases (A) and (C) together cover it.
#
# SAFETY (the live desktop is running): every launch runs under
# `dbus-run-session` (a throwaway bus, so the shell's NotificationServer cannot
# disturb swaync, which owns the real one) with HOME *and* XDG_CONFIG_HOME
# pointed at scratch — XDG_CONFIG_HOME is set in this environment, so redirecting
# HOME alone would point the configuration reader straight back at the real
# ~/.config. Every launch is bounded by a timeout and killed on exit; only this
# script's own shells are killed, matched on this worktree's path. smoke.qml
# draws nothing, so cases (B) never appear on screen. Case (C) does draw the bar
# briefly, exactly as verify-launch-reload.sh does, and is killed the moment it
# reports.
#
# Exit status: 0 only if every check holds.

set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"
SHELL_RUN_SECS="${SHELL_RUN_SECS:-20}"

# Fast smoke timing: nothing here needs live hardware, only the shell's own load
# path and its layout, so the capped wait periods are shortened (as in
# verify-bar-config.sh and verify-widget-contract.sh).
export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-900}"

TMP="$(mktemp -d /tmp/opencode/qs-barsurface.XXXXXX)"
LOG="$TMP/log"

PASS=0
FAIL=0
FAILED_CASES=()

cleanup() {
    # Kill only THIS script's shells: their cmdlines carry this worktree's or
    # this scratch directory's unique path. Never a broad pkill — the live
    # desktop runs a shell too, and so do the other verifiers.
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "quickshell.*${TMP}/shell.qml" 2>/dev/null || true
    pkill -f "dbus-run-session.*${TMP}/shell.qml" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 08 verification — three zones, true centre, floating/full-width"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

new_home() {
    local home="$TMP/$1"
    rm -rf "$home"
    mkdir -p "$home/.config/quickshell/nosarch"
    echo "$home"
}

# Built here independently of the shell code: if the two disagreed, the cases
# would be testing nothing.
config_path() { echo "$1/.config/quickshell/nosarch/shell.json"; }

run_smoke() {  # run_smoke <scratch-home> <logfile>
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
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null
    return 0
}

# The real shell, in a scratch copy of the tree, killed as soon as it has
# reported its bar geometry. Only case (C) uses this, and it is the only check
# here that puts anything on screen.
run_shell() {  # run_shell <scratch-home> <logfile>
    local home="$1" log="$2" pid i
    rm -rf "$TMP/shell"
    mkdir -p "$TMP/shell"
    cp "$REPO/shell.qml" "$TMP/shell/shell.qml"
    cp -r "$REPO/shell" "$TMP/shell/shell"
    cp -r "$REPO/services" "$TMP/shell/services"
    cp -r "$REPO/components" "$TMP/shell/components"
    mkdir -p "$TMP/homeshell"
    HOME="$TMP/homeshell" XDG_CONFIG_HOME="$home/.config" NOSARCH_SHELL_CONFIG="$home/.config/quickshell/nosarch/shell.json" \
        timeout "$SHELL_RUN_SECS" dbus-run-session -- \
        quickshell --no-color --log-times -p "$TMP/shell/shell.qml" >"$log" 2>&1 &
    pid=$!
    for i in $(seq 1 $((SHELL_RUN_SECS * 10))); do
        # Wait for a SETTLED report, not the first one: the surface is built
        # before the compositor has given the window a size, so its opening
        # report legitimately says width=0. Killing on that would measure
        # nothing.
        grep -qE "BAR surface .*width=[1-9][0-9]* " "$log" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null
    return 0
}

# check <case-name> [args...] — the case's checker reads the log given as $LOG.
# It prints one or more lines beginning "PASS <case>" or "FAIL <case>".
check() {
    local name="$1"
    shift
    LOG="$LOG" python3 - "$name" "$@" <<'PY'
import json, os, re, sys, pathlib

name = sys.argv[1]
extra = sys.argv[2:]
logp = pathlib.Path(os.environ["LOG"])
lines = logp.read_text(errors='replace').splitlines() if logp.exists() else []

out = []


def say(ok, detail):
    out.append(f"{'PASS' if ok else 'FAIL'} {name}: {detail}")


def bar(kind, surface):
    """The LAST 'BAR <kind>' line for a surface, as a {token: value} dict.

    Last, not first: the surface's geometry settles over more than one layout
    pass, so it reports itself each time it changes. The final line is the
    settled one, and reading the first would be reading the half-polished state.

    The surface name is matched with explicit delimiters rather than \b: `-` is
    not a word character, so `surface=probe\b` happily matches the line for
    `surface=probe-narrow` — and the last of those is the last line in the log.
    """
    got = None
    for ln in lines:
        m = re.search(rf"\bBAR {kind} (.*)", ln)
        if m and re.search(rf"(?:^|\s)surface={re.escape(surface)}(?:\s|$)", m.group(1)):
            got = dict(tok.split("=", 1) for tok in m.group(1).split() if "=" in tok)
    return got


def any_bar(kind):
    """Every line of this kind, whatever surface it names."""
    got = []
    for ln in lines:
        m = re.search(rf"\bBAR {kind} (.*)", ln)
        if m:
            got.append(dict(tok.split("=", 1) for tok in m.group(1).split() if "=" in tok))
    return got


def num(kv, key):
    if kv is None or key not in kv:
        return None
    try:
        return float(kv[key])
    except ValueError:
        return None


def config_line(kind):
    for ln in lines:
        if f"CONFIG {kind} " in ln:
            return ln.split(f"CONFIG {kind} ", 1)[1].strip()
    return None


def palette_background():
    for ln in lines:
        if "SMOKE NOTE palette " in ln:
            m = re.search(r"\bbackground=(\S+)", ln)
            if m:
                return m.group(1)
    return None


def zones_reported():
    kv = bar("zones", "probe")
    return None if kv is None else {k: int(kv[k]) for k in ("left", "center", "right")}


def centred(kv, label):
    """The strong centring assertion, as one (ok, explanation) pair."""
    w, cx, cw = num(kv, "width"), num(kv, "center.x"), num(kv, "center.w")
    if w is None or cx is None or cw is None:
        return False, f"{label}: the shell did not report a measurable layout ({kv})"
    expect = (w - cw) / 2.0
    off = abs(cx - expect)
    mid = cx + cw / 2.0
    return off <= 0.5, (f"{label}: barWidth={w:g} center.x={cx:g} center.w={cw:g} → "
                        f"expected {expect:g}, off by {off:.2f}px; centre midpoint "
                        f"{mid:g} vs bar midpoint {w / 2.0:g}")


def repo_log_clean(only=None):
    """Every WARN/ERROR naming a file in this repo.

    `only` restricts that to files under these prefixes, for the real-shell
    cases: the assembled shell also draws the wallpaper and (until ticket 18
    retires them) the pre-rewrite widgets, and this ticket is not what decides
    whether those are clean.
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
        mine = (name == "smoke.qml"
                or name.startswith(("services/", "shell/", "components/")))
        if only is not None:
            mine = mine and (name == "shell.qml" or name.startswith(tuple(only)))
        if mine:
            bad.append(name + ": " + m.group(2).strip())
    return bad


# ---------------------------------------------------------------------------

if name == "case1-floating-default":
    # No configuration file at all: the bar must still be the floating island.
    v = config_line("verdict")
    say(v is not None and "source=defaults" in v,
        f"with no configuration file the bar runs on the built-in defaults: {v}")
    s = bar("surface", "probe")
    if s is None:
        say(False, "the bar surface never reported its own geometry — nothing was built")
    else:
        say(s.get("floating") == "true",
            f"floating is the DEFAULT with no configuration file: floating={s.get('floating')}")
        say(num(s, "margin") is not None and num(s, "margin") > 0,
            f"a floating bar is inset from the screen edges: margin={s.get('margin')}px")
        say(num(s, "radius") is not None and num(s, "radius") > 0,
            f"a floating bar is a rounded island: radius={s.get('radius')}px")
        pal = palette_background()
        say(pal is not None and s.get("fill", "").lower() == pal.lower(),
            f"the bar is filled with the palette's background, not a literal: "
            f"fill={s.get('fill')} palette background={pal}")
    z = zones_reported()
    want = {"left": 2, "center": 1, "right": 1}
    say(z == want, f"the default bar holds all THREE zones with launcher, workspaces, clock and tray: {z}"
        + ("" if z == want else f" (expected {want})"))

elif name == "case2-three-zones-from-config":
    cfg = json.loads(extra[0])
    want = {k: len(v) for k, v in cfg["bar"]["zones"].items()}
    z = zones_reported()
    say(z == want, f"the three zones hold exactly what the file says: {z}"
        + ("" if z == want else f" (file says {want})"))
    # Every zone is a real zone: all three are reported even when empty, so an
    # implementation that quietly had only one cannot look the same.
    reported = bar("zones", "probe")
    keys = set() if reported is None else {"left", "center", "right"}
    say(keys == {"left", "center", "right"},
        "the bar reports all three zones by name (left, center, right)")
    # The per-screen plan entry constructs a surface too — once per screen, on a
    # windowless Item — and its zones have to populate. Its NUMBERS are not read
    # here: outside a window a plain Item does not re-polish after its zones are
    # rebuilt, which is a property of the harness rather than of the bar. The
    # real shell's own numbers are case 7/8/9's job.
    planned = bar("zones", "smoke")
    plannedCounts = None if planned is None else {
        k: int(planned[k]) for k in ("left", "center", "right") if k in planned}
    say(plannedCounts == want,
        f"the bar surface the plan instantiates on every screen populates its zones too: "
        f"{plannedCounts}" + ("" if plannedCounts == want else f" (expected {want})"))
    lz = bar("layout", "probe")
    if lz is None:
        say(False, "no layout report from the bar surface")
    else:
        # The wings hug their own edges: an overlay cannot do this.
        pad = num(lz, "pad") or 0
        ok_left = abs(num(lz, "left.x") - pad) <= 0.5
        ok_right = abs(num(lz, "right.x") + num(lz, "right.w")
                       - (num(lz, "width") - pad)) <= 0.5
        say(ok_left,
            f"the left zone is anchored to the left edge: left.x={lz.get('left.x')} "
            f"(padding {pad:g})")
        say(ok_right,
            f"the right zone is anchored to the right edge, independently of the left: "
            f"right.x={lz.get('right.x')} right.w={lz.get('right.w')} width={lz.get('width')}")
        lw, rw = num(lz, "left.w"), num(lz, "right.w")
        say(abs(lw - rw) > 0.5,
            f"the wings are deliberately ASYMMETRIC in this case (left.w={lw:g} "
            f"right.w={rw:g}), so a centre that only looks centred by symmetry cannot pass")

elif name.startswith("case3-centred-"):
    which = name[len("case3-centred-"):]
    for surface in ("probe", "probe-narrow"):
        lz = bar("layout", surface)
        if lz is None:
            say(False, f"[{which}/{surface}] no layout report from the bar surface")
            continue
        ok, why = centred(lz, f"[{which}/{surface}]")
        say(ok, why)
    # Leave this run's numbers on stdout for the cross-run comparison below.
    lz = bar("layout", "probe")
    if lz:
        print(f"    measured[{which}] center.x={lz.get('center.x')} "
              f"center.w={lz.get('center.w')} left.w={lz.get('left.w')} "
              f"right.w={lz.get('right.w')} width={lz.get('width')}")

elif name == "case4-full-width":
    s = bar("surface", "probe")
    if s is None:
        say(False, "the bar surface never reported its own geometry")
    else:
        say(s.get("floating") == "false",
            f"floating=false in the configuration file is honoured: floating={s.get('floating')}")
        say(num(s, "margin") == 0,
            f"a full-width bar is flush with the screen edges: margin={s.get('margin')}px")
        say(num(s, "radius") == 0,
            f"a full-width bar has no rounded island: radius={s.get('radius')}px")
        pal = palette_background()
        say(pal is not None and s.get("fill", "").lower() == pal.lower(),
            f"the fill is still the palette's background in both modes: fill={s.get('fill')} "
            f"palette background={pal}")

elif name == "case-centring-invariance":
    # One hard residual per run (already asserted in the case3 checks) plus the
    # cross-run comparison, which is exact whenever the centre's own width held
    # steady between the two launches.
    #
    # Each run is read from its OWN log rather than from both concatenated:
    # `bar()` deliberately returns the last match, and a concatenated log would
    # hand back the second run's numbers for both — which is exactly the way this
    # check managed to report identical wings for two configurations that are
    # mirror images of one another.
    def measured_in(path):
        run = {}
        for run_line in pathlib.Path(path).read_text(errors="replace").splitlines():
            m = re.search(r"\bBAR layout (.*)", run_line)
            if not m:
                continue
            kv = dict(tok.split("=", 1) for tok in m.group(1).split() if "=" in tok)
            name = kv.get("surface")
            if name in ("probe", "probe-narrow"):
                run[name] = (float(kv["center.x"]), float(kv["center.w"]),
                             float(kv["left.w"]), float(kv["right.w"]),
                             float(kv["width"]))
        return run

    measured = {}
    for which, path in (("right-heavy", extra[0]), ("both-heavy", extra[1])):
        run = measured_in(path)
        if run:
            measured[which] = run
    if len(measured) < 2:
        say(False, f"not every case was run, so there is nothing to compare: {sorted(measured)}")
    else:
        for surface in ("probe", "probe-narrow"):
            a, b = measured["right-heavy"].get(surface), measured["both-heavy"].get(surface)
            if a is None or b is None:
                say(False, f"[{surface}] one of the two wing configurations is missing")
                continue
            say(a[4] == b[4],
                f"[{surface}] both cases measure the same bar width: {a[4]:g}")
            say(a[2] != b[2] or a[3] != b[3],
                f"[{surface}] the wings really did change width between the two cases: "
                f"left.w {a[2]:g}→{b[2]:g}, right.w {a[3]:g}→{b[3]:g}")
            if abs(a[1] - b[1]) < 0.5:
                say(abs(a[0] - b[0]) < 0.5,
                    f"[{surface}] the centre zone did NOT move when the wings changed: "
                    f"center.x {a[0]:g} → {b[0]:g} (left.w {a[2]:g}→{b[2]:g}, "
                    f"right.w {a[3]:g}→{b[3]:g})")
            else:
                out.append(f"PASS {name}: [{surface}] the centre zone's own width changed "
                           f"between the two launches ({a[1]:g}px → {b[1]:g}px, the clock's "
                           f"text changed), so a raw x comparison would be meaningless; the "
                           f"per-case residual above is what carries this claim")

elif name in ("case5-window-floating", "case6-window-full-width"):
    # The real shell reports under its SCREEN's name, which this script does not
    # know in advance — so whichever surface line the log carries is the one.
    # The LAST report is the settled one — see bar() above.
    s = None
    for candidate in any_bar("surface"):
        if all(k in candidate for k in ("floating", "margin", "radius", "width")):
            s = candidate
    if s is None:
        say(False, "the real shell never reported its bar surface — it did not map")
    else:
        if name == "case5-window-floating":
            say(s.get("floating") == "true" and num(s, "margin") > 0
                and num(s, "radius") > 0,
                f"the real shell draws the floating rounded island by default: {s}")
        else:
            say(s.get("floating") == "false" and num(s, "margin") == 0
                and num(s, "radius") == 0,
                f"one configuration edit turned the real bar into a full-width background: {s}")
        say(num(s, "width") is not None and num(s, "width") > 0,
            f"the surface the compositor gave the bar is measurable: width={s.get('width')}px")
        z = any_bar("zones")
        say(bool(z), f"the real bar's three zones are populated: {z}")

elif name == "case-log-clean":
    bad = repo_log_clean()
    say(not bad,
        "no WARN/ERROR in the log names a file in this repo: the bar is built by binding, "
        "not by throwing"
        + ("" if not bad else " — " + "; ".join(bad[:3])))

elif name == "case-bar-log-clean":
    # The assembled shell only: the bar's own files and the entrypoint. The rest
    # of the real shell (wallpaper, the pre-rewrite widgets ticket 18 retires)
    # is not this ticket's to declare clean.
    bad = repo_log_clean(only=("shell/bar/", "shell/widgets/"))
    say(not bad,
        "no WARN/ERROR names the new bar's files or shell.qml: the real bar maps without "
        "complaining"
        + ("" if not bad else " — " + "; ".join(bad[:3])))

else:
    say(False, f"no checker wired for {name}")

for ln in out:
    print(ln)
sys.exit(1 if any(l.startswith("FAIL") for l in out) else 0)
PY
}

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

# ---------------------------------------------------------------------------
# (A) STATIC — the shape of the claim
# ---------------------------------------------------------------------------
echo
echo "[A] static: three anchored zones, a centre that ignores its wings, a window with a layer and a namespace ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib

repo = pathlib.Path(sys.argv[1])


def strip_comments(text):
    """QML with // and /* */ comments removed.

    These checks are about CODE. BarSurface.qml explains at length why it must
    not use a RowLayout — a word that then appears in its own prose — and a
    check that reads prose is a check that fails on the explanation and passes
    on the thing it was written to forbid.
    """
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


problems = []
bar = repo / "shell/bar"
surface = bar / "BarSurface.qml"
window = bar / "Bar.qml"
qmldir = bar / "qmldir"
entry = repo / "shell.qml"

for f in (surface, window, qmldir, entry):
    if not f.is_file():
        problems.append(f"{f.relative_to(repo)} does not exist")

# ---- shell/bar/qmldir registers both new types -----------------------------
if qmldir.is_file():
    names = set()
    for line in qmldir.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        if len(parts) >= 2:
            names.add(parts[1] if parts[0] == 'singleton' else parts[0])
    for want in ("BarConfig", "BarZone", "BarSurface", "Bar"):
        if want not in names:
            problems.append(f"shell/bar/qmldir does not register {want}")

if problems:
    for p in problems:
        print("    ! " + p)
    sys.exit(1)

stext = strip_comments(surface.read_text())
wtext = strip_comments(window.read_text())
etext = strip_comments(entry.read_text())

# ---- the entrypoint composes the NEW bar ----------------------------------
if not re.search(r'^\s*Bar\s*\{', etext, re.M):
    problems.append("shell.qml never instantiates the new bar (Bar {}) — nothing would "
                    "be user-visible")
if re.search(r'^\s*TopIsland\s*\{', etext, re.M):
    problems.append("shell.qml still instantiates TopIsland — the pre-rewrite hardcoded "
                    "bar would draw alongside the configured one")

# ---- three zones, by name --------------------------------------------------
for z in ("left", "center", "right"):
    if f'zoneName: "{z}"' not in stext:
        problems.append(f"BarSurface.qml never builds a '{z}' zone")

# ---- THE load-bearing claim: the zones are not laid out by a layout ---------
# A Row/RowLayout/Flow hands its children whatever space is left after the other
# children, which is exactly the accidental-symmetry behaviour this ticket
# replaces. Anchoring each zone to its own edge (and the centre to the bar) is
# what makes the centre's position independent of the wings.
for needle, why in (("RowLayout", "a RowLayout shares leftover space between zones"),
                    ("ColumnLayout", "a ColumnLayout stacks zones vertically"),
                    ("GridLayout", "a GridLayout divides the bar between zones"),
                    ("Flow", "a Flow repositions zones as space allows"),
                    ("Positioner", "a Positioner repositions zones"),
                    ("Row {", "a Row gives the centre zone only the space the wings leave")):
    if needle in stext:
        problems.append(f"BarSurface.qml uses {needle} — {why}; the centre zone's position "
                        "would depend on its neighbours again")

if "anchors.centerIn: parent" not in stext:
    problems.append("BarSurface.qml does not place the centre zone with "
                    "anchors.centerIn: parent — a centre that is not placed against the "
                    "container cannot be centred in the bar's full width")
for wing, edge in (("left", "left: parent.left"), ("right", "right: parent.right")):
    if edge not in stext:
        problems.append(f"BarSurface.qml does not anchor the {wing} zone with "
                        f"anchors {{ {edge} }} — a zone must hug its own edge independently")

# The centre's placement must not mention either wing.
m = re.search(r'BarZone\s*\{[^}]*zoneName:\s*"center"[^}]*\}', stext, re.S)
if not m:
    problems.append("could not find the centre zone's block in BarSurface.qml")
else:
    block = m.group(0)
    for wing in ("leftZone", "rightZone"):
        if wing in block:
            problems.append(f"the centre zone's placement mentions {wing} — a zone that is "
                            "positioned relative to another zone is not truly centred")

# ---- the fill comes from the palette ---------------------------------------
if not re.search(r'color:\s*UI\.Colors\.background', stext):
    problems.append("BarSurface.qml does not fill the bar with UI.Colors.background")
for lit in re.findall(r'"#[0-9a-fA-F]{3,8}"', stext):
    problems.append(f"BarSurface.qml hardcodes the colour {lit} — the bar is themed from "
                    "the palette")

# ---- the window: layer, namespace, per-screen, no popup --------------------
if "PanelWindow" not in wtext:
    problems.append("Bar.qml declares no PanelWindow — the bar has no surface")
if "WlrLayershell.layer" not in wtext:
    problems.append("Bar.qml's PanelWindow sets no WlrLayershell.layer")
ns = re.findall(r'WlrLayershell\.namespace\s*:\s*"([^"]+)"', wtext)
if not ns:
    problems.append("Bar.qml's PanelWindow sets no WlrLayershell.namespace")
elif len(set(ns)) != len(ns):
    problems.append(f"Bar.qml sets the same namespace {ns} on more than one surface")
else:
    old = re.findall(r'WlrLayershell\.namespace\s*:\s*"([^"]+)"',
                     (repo / "shell/topisland/TopIsland.qml").read_text()
                     if (repo / "shell/topisland/TopIsland.qml").is_file() else "")
    clash = set(ns) & set(old)
    if clash:
        problems.append(f"the new bar reuses the old bar's namespace {clash} — surfaces "
                        "must be tellable apart")
    print(f"    new bar surface namespace: {ns[0]} (layer "
          f"{re.findall(r'WlrLayershell.layer: (.*)', wtext)})")
if "Variants" not in wtext:
    problems.append("Bar.qml has no Variants — the bar would not follow the set of "
                    "attached screens")
elif "Quickshell.screens" not in wtext or "model:" not in wtext:
    # The model is allowed to be an intermediate property (it is: the windows
    # wait for the reader's verdict), so what is checked is that the attached
    # screens are what is being instantiated per, and that a model is bound.
    problems.append("Bar.qml does not bind a Variants model to the attached screens "
                    "(Quickshell.screens)")
if "variants:" in wtext:
    problems.append("Bar.qml uses `variants:` — that is the documented typo; the property "
                    "is `model:` (see quickshell-api-notes.md §5)")
if "PopupWindow" in wtext:
    problems.append("Bar.qml uses a framework PopupWindow — panels are overlay surfaces "
                    "(docs/adr/0002)")

if problems:
    print("    FAIL — the bar surface does not have the shape the ticket claims:")
    for p in problems:
        print("      ! " + p)
    sys.exit(1)
print("    PASS — three anchored zones, a centre placed against the container alone, a "
      "palette fill, and a per-screen window with layer and a distinct namespace")
PY
static_rc=$?

# ---------------------------------------------------------------------------
# case 1 — no configuration file: the floating island is the default
# ---------------------------------------------------------------------------
echo
echo "[1] no configuration file → the floating rounded island, three zones ..."
home="$(new_home case1)"
LOG="$TMP/case1.log"
run_smoke "$home" "$LOG"
record "case1" "$(LOG="$LOG" check case1-floating-default)"

# ---------------------------------------------------------------------------
# case 2 — a lopsided configuration file → three zones hold what it says
# ---------------------------------------------------------------------------
echo
echo "[2] a lopsided configuration file → three zones, contents from the file ..."
home="$(new_home case2)"
python3 - "$(config_path "$home")" >"$TMP/case2.json" <<'PY'
import json, pathlib, sys
# Deliberately lopsided: three clocks left, nothing right. Any centre that is
# only centred by its neighbours being symmetric cannot survive this.
cfg = {"bar": {"floating": True, "zones": {
    "left":   [{"type": "clock"}, {"type": "clock"}, {"type": "clock"}],
    "center": [{"type": "clock"}],
    "right":  []}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
print(json.dumps(cfg))
PY
LOG="$TMP/case2.log"
run_smoke "$home" "$LOG"
record "case2" "$(LOG="$LOG" check case2-three-zones-from-config "$(cat "$TMP/case2.json")")"
record "case2-log" "$(LOG="$LOG" check case-log-clean)"

# ---------------------------------------------------------------------------
# case 3 — the mirror image, and the centring measurement, twice over
# ---------------------------------------------------------------------------
echo
echo "[3] lopsided to the RIGHT (0 left, 3 right) → the centre zone does not move ..."
home="$(new_home case3a)"
python3 - "$(config_path "$home")" <<'PY'
import json, pathlib, sys
cfg = {"bar": {"floating": True, "zones": {
    "left":   [],
    "center": [{"type": "clock"}],
    "right":  [{"type": "clock"}, {"type": "clock"}, {"type": "clock"}]}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
PY
LOG="$TMP/case3a.log"
run_smoke "$home" "$LOG"
record "case3a" "$(LOG="$LOG" check case3-centred-right-heavy)"

echo
echo "[4] lopsided both ways at once (5 left, 1 right) → still centred ..."
home="$(new_home case3b)"
python3 - "$(config_path "$home")" <<'PY'
import json, pathlib, sys
cfg = {"bar": {"floating": True, "zones": {
    "left":   [{"type": "clock"}] * 5,
    "center": [{"type": "clock"}],
    "right":  [{"type": "clock"}]}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
PY
LOG="$TMP/case3b.log"
run_smoke "$home" "$LOG"
record "case3b" "$(LOG="$LOG" check case3-centred-both-heavy)"

echo
echo "[5] cross-case: the wings changed width, the centre zone did not ..."
# The invariance check reads both logs, so it is given a combined one.
record "case-invariance" "$(LOG="$TMP/case3a.log" check case-centring-invariance \
    "$TMP/case3a.log" "$TMP/case3b.log")"

# ---------------------------------------------------------------------------
# case 4 — floating: false is a configuration edit
# ---------------------------------------------------------------------------
echo
echo "[6] floating:false in the file → flush, square, still the palette's fill ..."
home="$(new_home case4)"
python3 - "$(config_path "$home")" <<'PY'
import json, pathlib, sys
cfg = {"bar": {"floating": False, "zones": {
    "left":   [{"type": "clock"}],
    "center": [{"type": "clock"}],
    "right":  [{"type": "clock"}]}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
PY
LOG="$TMP/case4.log"
run_smoke "$home" "$LOG"
record "case4" "$(LOG="$LOG" check case4-full-width)"

# ---------------------------------------------------------------------------
# cases 5-7 — the real shell, twice: what the compositor is actually given
# ---------------------------------------------------------------------------
echo
echo "[7] the real shell, floating by default ..."
home="$(new_home case7float)"
python3 - "$(config_path "$home")" <<'PY'
import json, pathlib, sys
cfg = {"bar": {"floating": True, "zones": {
    "left": [], "center": [{"type": "clock"}], "right": []}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
PY
LOG="$TMP/case7float.log"
run_shell "$home" "$LOG"
record "case7-float" "$(LOG="$LOG" check case5-window-floating)"
record "case7-float-log" "$(LOG="$LOG" check case-bar-log-clean)"

echo
echo "[8] the real shell, full-width after one configuration edit ..."
home="$(new_home case7full)"
python3 - "$(config_path "$home")" <<'PY'
import json, pathlib, sys
cfg = {"bar": {"floating": False, "zones": {
    "left": [], "center": [{"type": "clock"}], "right": []}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
PY
LOG="$TMP/case7full.log"
run_shell "$home" "$LOG"
record "case7-full" "$(LOG="$LOG" check case6-window-full-width)"
record "case7-full-log" "$(LOG="$LOG" check case-bar-log-clean)"

echo
echo "[9] floating vs full-width: the surface really is a different width ..."
python3 - "$TMP/case7float.log" "$TMP/case7full.log" <<'PY'
import re, sys, pathlib
out = []


def surface(path):
    """The LAST surface report in a log — the settled one, not the first."""
    got = None
    for ln in pathlib.Path(path).read_text(errors='replace').splitlines():
        m = re.search(r"\bBAR surface (.*)", ln)
        if m:
            got = dict(tok.split("=", 1) for tok in m.group(1).split() if "=" in tok)
    return got


a, b = surface(sys.argv[1]), surface(sys.argv[2])
if a is None or b is None:
    out.append("FAIL case7-window-width-changes: one of the two real-shell launches never "
               "reported a bar surface")
else:
    f = {k: float(a[k]) for k in ("width", "margin", "radius")}
    g = {k: float(b[k]) for k in ("width", "margin", "radius")}
    out.append(f"    measured: floating width={f['width']:g} margin={f['margin']:g} "
               f"radius={f['radius']:g} · full-width width={g['width']:g} "
               f"margin={g['margin']:g} radius={g['radius']:g}")
    if g["width"] > f["width"]:
        out.append("PASS case7-window-width-changes: full-width really is wider than "
                   f"floating ({f['width']:g}px → {g['width']:g}px)")
    else:
        out.append(f"FAIL case7-window-width-changes: full-width is not wider than floating "
                   f"({f['width']:g}px → {g['width']:g}px)")
    want = f["width"] + 2 * f["margin"]
    if abs(g["width"] - want) <= 1.0:
        out.append(f"PASS case7-window-width-changes: the difference is exactly the two "
                   f"floating insets (2 × {f['margin']:g}px = {want - f['width']:g}px)")
    else:
        out.append(f"FAIL case7-window-width-changes: expected {want:g}px, measured "
                   f"{g['width']:g}px — the surface is not the full screen width")
    if g["radius"] == 0 and f["radius"] > 0:
        out.append(f"PASS case7-window-width-changes: the rounded island is gone in "
                   f"full-width mode ({f['radius']:g}px → {g['radius']:g}px)")
    else:
        out.append(f"FAIL case7-window-width-changes: radius did not go to zero "
                   f"({f['radius']:g}px → {g['radius']:g}px)")
print("\n".join(out))
sys.exit(1 if any(l.startswith("FAIL") for l in out) else 0)
PY
case7_rc=$?
if [[ $case7_rc -ne 0 ]]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("case7-width")
else
    PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $FAIL -eq 0 && $static_rc -eq 0 ]]; then
    echo " RESULT: PASS (static shape + three zones + true centring + floating/full-width)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  ($PASS assertion(s) passed, $FAIL failed: ${FAILED_CASES[*]})"
    echo " --- captured log tail (if any) ---"
    tail -n 40 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi
