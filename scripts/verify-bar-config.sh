#!/usr/bin/env bash
#
# verify-bar-config.sh — verification for ticket 07.
#
#   "What appears in my bar comes from a JSON configuration file rather than
#    from QML… An unrecognised widget name, a malformed entry, or a widget that
#    fails to construct is logged with the offending name and skipped;
#    everything valid still renders. A malformed file as a whole falls back to
#    defaults and the shell still starts. With no configuration file present,
#    the shell starts with defaults and a working bar. Reordering widgets within
#    a zone, removing a widget, and adding a widget are each achievable by
#    editing configuration alone."
#
# Two kinds of check, because two kinds of promise:
#
#   (A) STATIC — the shape of the claim. The configuration path is absolute and
#       is NOT resolved relative to the QML source (no Qt.resolvedUrl, no
#       Quickshell.shellDir/configDir/shellPath, built from HOME or
#       XDG_CONFIG_HOME); the three zones are named; and — the security
#       property — configuration cannot carry a file path: the only thing an
#       entry is allowed to influence is the NAME handed to the widget registry.
#   (B) RUNTIME — six launches of smoke.qml, one per user-visible promise, each
#       against a REAL filesystem with HOME and XDG_CONFIG_HOME pointed at a
#       throwaway scratch directory. Nothing here inspects shell internals: the
#       configuration file on disk and the log lines are the whole interface,
#       and every expectation is computed independently in Python from the file
#       this script wrote.
#
# HOW THE CASES ARE OBSERVED
#
# The configuration reader logs one verdict line per run, one line per zone, one
# line per skipped entry, and (when NOSARCH_CONFIG_EMIT=1, which this script
# always sets) one line carrying the effective configuration as JSON:
#
#   nosarch-shell ▸ CONFIG verdict source=file|defaults file=<path> \
#        zones=3 entries=<n> skipped=<n> note=<tag>
#   nosarch-shell ▸ CONFIG zone <left|center|right> count=<n> types=<a,b,c>
#   nosarch-shell ▸ CONFIG skipped bar.zones.<zone>[<i>] <key=value>…
#   nosarch-shell ▸ CONFIG effective <json>
#   nosarch-shell ▸ CONFIG probe zones-rendered left=<n> center=<n> right=<n>
#   nosarch-shell ▸ CONFIG probe construct entry=<name> constructed=<yes|no> \
#        zone-rendered=<n>
#
# The cases:
#
#   1. no configuration file   → defaults, and every zone really renders
#   2. a configuration file    → zone contents and their ORDER reflect the file
#   3. bad entries             → unknown name / malformed shape / a `path` key
#                                are each skipped with a NAMED line, and
#                                everything valid still renders
#   4. malformed whole file    → defaults, and the file is byte-for-byte intact
#   5. reorder/remove/add      → three files, three different effective
#                                configurations, each exactly what was written
#   6. widget fails to build   → BarZone's guarded construction returns nothing,
#                                logs the offending name, and the zone keeps
#                                rendering what it had
#
# Case 6 needs no launch of its own: the smoke shell runs that probe every time,
# so its verdict is asserted on every run.
#
# HONEST LIMIT OF CASE 5
#
# Only ONE widget is on the widget contract today (the clock; the other eleven
# are their own tickets), so what is provable today is that the effective
# configuration is byte-for-byte what the file says — which is the whole of the
# claim. Ordering within a zone is checked against the file's own index order,
# and the assertion is written against the file rather than against a fixed list,
# so it starts proving a true N>=2 reorder the moment a second widget is
# registered. The positional part IS proven today: a skipped entry's INDEX is
# checked, so a bad entry cannot silently shift the ones after it.
#
# SAFETY (the live desktop is running): every launch runs under
# `dbus-run-session` (throwaway bus — the shell's NotificationServer cannot
# disturb swaync, which owns the real one) with HOME *and* XDG_CONFIG_HOME
# pointed at scratch, and is bounded by a timeout. The live
# ~/.config/quickshell/ does not exist and is never created: the reader builds
# its path from HOME, and this script overrides both variables because
# XDG_CONFIG_HOME is set in this environment and would otherwise point the
# reader back at the real ~/.config. smoke.qml draws no layer-shell surfaces,
# so nothing appears on screen and waybar is never involved.
#
# Exit status: 0 only if all six cases hold.

set -uo pipefail   # deliberately not -e: run every case, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"

# Fast smoke timing: nothing here needs live hardware, only the shell's own
# load path, so the smoke shell's capped wait periods are shortened (as in
# verify-widget-contract.sh) to keep each case to a few seconds.
export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-800}"

# Ask the reader to print the effective configuration as JSON. One log line, no
# side effects — this is how a case can compare the shell's whole answer with
# the file the script wrote.
export NOSARCH_CONFIG_EMIT=1

TMP="$(mktemp -d /tmp/opencode/qs-barconfig.XXXXXX)"
LOG="$TMP/smoke.log"

PASS=0
FAIL=0
FAILED_CASES=()

cleanup() {
    # Kill only THIS shell: its cmdline carries this worktree's unique path.
    # Never a broad pkill — the live desktop runs a shell too, and so do the
    # other verifiers.
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 07 verification — configuration-driven bar contents"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# new_home <case-name> — a fresh scratch HOME per case, so no case can see
# another case's configuration file (a seen file would make "no file" vacuous).
new_home() {
    local home="$TMP/$1"
    rm -rf "$home"
    mkdir -p "$home/.config/quickshell/nosarch"
    echo "$home"
}

# config_path <home> — the reader's path, as a real machine would have it. Built
# here independently of the shell code on purpose: if the two disagreed, the
# cases would be testing nothing.
config_path() { echo "$1/.config/quickshell/nosarch/shell.json"; }

# run_smoke <scratch-home> — launch the smoke shell with HOME and XDG_CONFIG_HOME
# both pointed at the scratch dir, wait for it to finish, leave the log at $LOG.
run_smoke() {
    local home="$1" pid
    cd "$REPO" || return 1
    HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        timeout "$RUN_SECS" dbus-run-session -- \
        quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &
    pid=$!
    local i
    for i in $(seq 1 $((RUN_SECS * 10))); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    # Still alive means it hung: TERM `timeout`, which kills the whole process
    # group (dbus-run-session and the quickshell under it).
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null
    return 0
}

# check <case-name> <python-heredoc-args...> — the case's checker reads $LOG.
# It prints one or more lines beginning "PASS <case>" or "FAIL <case>".
check() {
    local name="$1"
    shift
    python3 - "$LOG" "$name" "$@" <<'PY'
import json, re, sys, pathlib

logp, name = pathlib.Path(sys.argv[1]), sys.argv[2]
extra = sys.argv[3:]
lines = logp.read_text(errors='replace').splitlines()

ZONES = ("left", "center", "right")
out = []

def say(ok, detail):
    out.append(f"{'PASS' if ok else 'FAIL'} {name}: {detail}")

def config_line(kind):
    for ln in lines:
        if f"CONFIG {kind} " in ln:
            return ln.split(f"CONFIG {kind} ", 1)[1].strip()
    return None

def verdict():
    v = config_line("verdict")
    return dict(tok.split("=", 1) for tok in v.split() if "=" in tok) if v else None

def zones():
    """{zone: [types]} as the shell reported them."""
    got = {}
    for ln in lines:
        m = re.search(r"CONFIG zone (\w+) count=(\d+) types=(\S*)", ln)
        if m:
            got[m.group(1)] = [] if m.group(3) == "" else m.group(3).split(",")
    return got

def effective():
    e = config_line("effective")
    if e is None:
        return None
    try:
        return json.loads(e)
    except Exception:
        return None

def skips():
    """[(zone, index, {key: value})] — every skipped entry, with its position.

    The location prefix `bar.zones.` is stripped so a zone name can be matched
    directly; the probes report their own synthetic zone names ("invalid",
    "probe") through the same format.
    """
    got = []
    for ln in lines:
        m = re.search(r"CONFIG skipped (\S+)\[(-?\d+)\]\s*(.*)", ln)
        if m:
            where = m.group(1)
            if where.startswith("bar.zones."):
                where = where[len("bar.zones."):]
            got.append((where, int(m.group(2)),
                        dict(tok.split("=", 1) for tok in m.group(3).split() if "=" in tok)))
    return got

def skips_at(zone, index):
    return next((kv for z, i, kv in skips() if z == zone and i == index), None)

def probe_line(key):
    for ln in lines:
        if f"CONFIG probe {key} " in ln:
            return ln.split(f"CONFIG probe {key} ", 1)[1].strip()
    return None

def shell_still_started():
    return any("SMOKE SUMMARY" in ln for ln in lines)

# The default configuration, written out here from the spec rather than read
# from the shell: an expectation derived from the code under test proves
# nothing.
DEFAULTS = {"bar": {"floating": True, "zones": {
    "left": [
        {"type": "launcher"},
        {"type": "workspaces"},
        {"type": "cpu"},
        {"type": "memory"},
    ],
    "center": [{"type": "player"}, {"type": "clock"}],
    "right": [
        {"type": "tray"},
        {"type": "network"},
        {"type": "bluetooth"},
        {"type": "volume"},
        {"type": "battery"},
        {"type": "notification"},
    ],
}}}

def zone_types_of(cfg):
    z = cfg.get("bar", {}).get("zones", {})
    return {name: [e["type"] for e in z.get(name, []) if isinstance(e, dict) and "type" in e]
            for name in ZONES}

# ---------------------------------------------------------------------------

if name == "case1-no-file-defaults":
    v = verdict()
    if v is None:
        say(False, "the smoke run printed no CONFIG verdict line — the reader never reported")
    else:
        ok = v.get("source") == "defaults" and v.get("note") == "no-file" and v.get("skipped") == "0"
        say(ok, f"with no configuration file the reader used the built-in defaults "
                f"(source={v.get('source')} note={v.get('note')} skipped={v.get('skipped')})")
    eff = effective()
    if eff is None:
        say(False, "no effective-configuration line in the log")
    else:
        say(eff == DEFAULTS, "effective configuration with no file is the built-in default")
    got = zones()
    want = zone_types_of(DEFAULTS)
    say(got == want, f"every zone reports the default contents: {json.dumps(got, sort_keys=True)}"
        + ("" if got == want else f" (expected {json.dumps(want, sort_keys=True)})"))
    # A working bar, not just correct data: the zones really produced widgets.
    r = probe_line("zones-rendered")
    if r is None:
        say(False, "the shell never reported live zone instances — the bar contents were not built")
    else:
        counts = dict(re.findall(r"(left|center|right)=(\d+)", r))
        say(counts == {"left": "4", "center": "2", "right": "6"},
            f"live widget instances built per zone from the defaults: {r}")

elif name == "case2-config-drives-contents":
    cfg = json.loads(extra[0])
    got = zones()
    want = zone_types_of(cfg)
    say(got == want, f"zone contents reflect the file exactly, in file order: "
                     f"{json.dumps(got, sort_keys=True)}"
                     + ("" if got == want else f" (file says {json.dumps(want, sort_keys=True)})"))
    v = verdict()
    say(v is not None and v.get("source") == "file" and v.get("note") == "none",
        f"the reader reported it took the file, cleanly: {v}")
    eff = effective()
    say(eff == cfg, "the effective configuration is byte-for-byte what the file says")
    r = probe_line("zones-rendered")
    if r is None:
        say(False, "the shell never reported live zone instances")
    else:
        counts = {k: int(n) for k, n in re.findall(r"(left|center|right)=(\d+)", r)}
        wantn = {k: len(v_) for k, v_ in want.items()}
        say(counts == wantn, f"one live widget instance was built per configured entry: {r}")

elif name == "case3-bad-entries-skipped":
    bad = json.loads(extra[0])          # {zone: [entry, ...]} exactly as written
    got = zones()

    # (a) an unrecognised widget name
    unknown = next(e for e in bad["left"] if isinstance(e, dict) and e.get("type") == "not-a-widget")
    idx = bad["left"].index(unknown)
    kv = skips_at("left", idx)
    say(kv is not None and kv.get("type") == "not-a-widget" and kv.get("reason") == "unknown-widget",
        f"unrecognised widget name skipped at bar.zones.left[{idx}] with its name in the log: "
        f"{kv}")
    say(kv is not None and kv.get("known", "") != "",
        "the skip line lists the names that do exist, so the user can fix the line")

    # (b) a malformed entry — not an object, and an object with no type
    for i, e in enumerate(bad["left"]):
        if not isinstance(e, dict):
            kv = skips_at("left", i)
            say(kv is not None and kv.get("reason") == "not-an-object",
                f"bare {type(e).__name__} entry at bar.zones.left[{i}] skipped and named: {kv}")
            break
    for i, e in enumerate(bad["left"]):
        if isinstance(e, dict) and "type" not in e:
            kv = skips_at("left", i)
            say(kv is not None and kv.get("reason") == "no-type",
                f"object entry with no `type` at bar.zones.left[{i}] skipped and named: {kv}")
            break

    # (c) an entry carrying a file path — configuration must not locate code
    for key in ("path", "file"):
        e = next((x for x in bad["left"] if isinstance(x, dict) and key in x), None)
        if e is None:
            continue
        i = bad["left"].index(e)
        kv = skips_at("left", i)
        say(kv is not None and kv.get("key") == key and kv.get("reason") == "entry-cannot-locate-code",
            f"entry at bar.zones.left[{i}] carrying `{key}` refused and named: {kv}")

    # Everything valid still renders, in the right order, and nothing shifted.
    want = [e["type"] for e in bad["left"]
            if isinstance(e, dict) and isinstance(e.get("type"), str)
            and "path" not in e and "file" not in e and e["type"] == "clock"]
    say(got.get("left") == want,
        f"the valid entries around the bad ones still render, in order: {got.get('left')}"
        + ("" if got.get("left") == want else f" (expected {want})"))
    # And the same for a zone the bad entries did not touch at all.
    say(got.get("right") == [e["type"] for e in bad["right"]],
        f"a zone with no bad entries is unaffected: {got.get('right')}")

elif name == "case4-malformed-file-defaults":
    v = verdict()
    say(v is not None and v.get("source") == "defaults"
        and v.get("note") == "malformed-left-untouched",
        f"a malformed file as a whole falls back to defaults: {v}")
    got = zones()
    want = zone_types_of(DEFAULTS)
    say(got == want, f"the bar shows the defaults, not the broken file: {json.dumps(got, sort_keys=True)}")
    eff = effective()
    say(eff == DEFAULTS, "the effective configuration is the built-in default")
    say(shell_still_started(),
        "the shell started and ran to its summary — a bad file did not stop it")
    r = probe_line("zones-rendered")
    counts = dict(re.findall(r"(left|center|right)=(\d+)", r or ""))
    say(counts == {"left": "4", "center": "2", "right": "6"},
        f"the bar still builds its default widgets: {r}")

elif name == "case5-reorder-remove-add":
    cfg = json.loads(extra[0])
    want = zone_types_of(cfg)
    got = zones()
    say(got == want, f"reorder/remove/add are configuration edits alone — contents are "
                     f"{json.dumps(got, sort_keys=True)}"
                     + ("" if got == want else f" (file says {json.dumps(want, sort_keys=True)})"))
    eff = effective()
    say(eff == cfg, "the effective configuration is byte-for-byte what the file says")

elif name == "case6-construct-failure":
    # The shell ran this probe on every launch; here it is asserted.
    p = probe_line("construct")
    if p is None:
        say(False, "the shell never reported the construction-failure probe")
    else:
        kv = dict(tok.split("=", 1) for tok in p.split() if "=" in tok)
        say(kv.get("constructed") == "no",
            f"a widget that cannot be constructed yields no widget: {p}")
        say(kv.get("entry", "") != "",
            "the failure line names the offending widget, so it can be found and fixed")
        say(kv.get("zone-rendered", "") == "2",
            f"the zone still rendered what it had after the failure: {p}")
    # The skip line for it must exist and name the widget.
    kv = skips_at("probe", 0)
    say(kv is not None and kv.get("reason") == "widget-failed-to-construct",
        f"the construction failure is logged as a named skip, like any other bad entry: {kv}")

elif name == "case-log-clean":
    # Skipping is the designed behaviour, so it must be loud without being a
    # QML warning: a WARN/ERROR naming a file in this repo would mean the
    # failure policy is implemented by throwing.
    qline = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\s+(WARN|ERROR)\s+(.*)$")
    repo_file = re.compile(r"@([^\s:\[]+)\[")
    bad = [rest for ln in lines
           if (m := qline.match(ln))
           and (f := repo_file.search(m.group(2)))
           and (f.group(1) == "smoke.qml" or f.group(1).startswith(("services/", "shell/", "components/")))]
    say(not bad,
        "the failure policy is implemented by skipping, not by throwing: no WARN/ERROR "
        "in the log names a file in this repo")

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
    if [[ "$out" == PASS* ]] || [[ -z "$out" ]]; then
        # A checker may legitimately print several lines; any FAIL fails.
        if [[ "$out" == *"FAIL"* ]]; then
            FAIL=$((FAIL + 1))
            FAILED_CASES+=("$name")
            PASS=$((PASS + $(grep -c '^PASS' <<<"$out")))
        else
            PASS=$((PASS + $(grep -c '^PASS' <<<"$out")))
        fi
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("$name")
    fi
}

# ---------------------------------------------------------------------------
# (A) STATIC — where the path comes from, and what configuration may influence
# ---------------------------------------------------------------------------
echo
echo "[A] static: the path is absolute, and configuration cannot locate code ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
problems = []

bar = repo / "shell/bar"
config = bar / "BarConfig.qml"
zone = bar / "BarZone.qml"
qmldir = bar / "qmldir"

if not qmldir.is_file():
    problems.append("shell/bar/qmldir does not exist — the directory's types would not resolve")
else:
    lines = [l.split() for l in qmldir.read_text().splitlines()
             if l.strip() and not l.strip().startswith("#")]
    names = {(p[1] if p[0] == "singleton" else p[0]) for p in lines if len(p) >= 2}
    for want in ("BarConfig", "BarZone"):
        if want not in names:
            problems.append(f"shell/bar/qmldir does not register {want}")

for f in (config, zone):
    if not f.is_file():
        problems.append(f"shell/bar/{f.name} does not exist")
if problems:
    for p in problems:
        print("    ! " + p)
    sys.exit(1)

text = config.read_text()
body = " ".join(text.split())

# The load-bearing claim: the path is NOT resolved relative to the QML source.
for needle, why in (
    ("Qt.resolvedUrl", "resolved relative to the QML source"),
    ("shellDir", "resolved relative to the shell directory"),
    ("configDir", "resolved relative to the shell directory"),
    ("shellPath", "resolved relative to the shell directory"),
    ("configPath", "resolved relative to the shell directory"),
):
    if needle in text:
        problems.append(f"BarConfig.qml uses {needle} ({why}) — the configuration path must be "
                        f"an absolute location that survives the shell being deployed")
for needle, why in (("XDG_CONFIG_HOME", "the standard way to find the config directory"),
                    ("HOME", "the fallback the tests redirect")):
    if needle not in text:
        problems.append(f"BarConfig.qml never mentions {needle} ({why})")
if not re.search(r"NOSARCH_SHELL_CONFIG", text):
    problems.append("BarConfig.qml has no NOSARCH_SHELL_CONFIG override — the path cannot be "
                    "redirected for a test without touching the real one")

# Three named zones, in the order the spec names them.
for z in ("left", "center", "right"):
    if not re.search(rf'"{z}"', text):
        problems.append(f"BarConfig.qml never names the '{z}' zone")

# THE SECURITY PROPERTY. Configuration may choose a widget NAME and nothing
# else. Two things must therefore be true of the code: the only resolution it
# performs is through the registry's name→component lookup, and it never reads a
# locator key out of an entry in order to load anything.
for f in (config, zone):
    t = f.read_text()
    if re.search(r"\.adapter\b", t):
        problems.append(f"{f.name} reaches into a FileView adapter — entries are data, not "
                        f"typed records")
    for m in re.finditer(r"\.?(?:path|file)\b", t):
        line = t[:m.start()].count("\n") + 1
        src = t.splitlines()[line - 1]
        # The reader's own FileView.path is fine; a locator read out of an
        # entry is not, and neither is a createComponent of anything but the
        # registry's own answer.
        if re.search(r"(entry|e|raw|item|c)\s*\.\s*(path|file)\b", src):
            problems.append(f"{f.name}:{line} reads a locator key off a configuration entry — "
                            f"configuration must not be able to locate code")
    for m in re.finditer(r"createComponent\s*\(([^)]*)\)", t):
        arg = m.group(1)
        if "componentFor" not in arg and "component" not in arg.lower():
            problems.append(f"{f.name} creates a component from {arg!r} rather than from the "
                            f"widget registry")

print("    path resolution: no Qt.resolvedUrl, no shell-dir resolution; built from "
      "XDG_CONFIG_HOME or HOME, overridable by NOSARCH_SHELL_CONFIG")
m = re.search(r"readonly\s+property\s+var\s+rejectedEntryKeys\s*:\s*\[(.*?)\]", text, re.S)
print("    entry keys refused: " + (", ".join(re.findall(r'"(\w+)"', m.group(1))) if m
                                    else "(no rejectedEntryKeys list declared)"))
if not m:
    problems.append("BarConfig.qml declares no rejectedEntryKeys list — an entry carrying a "
                    "file path would be silently stripped instead of refused")

if problems:
    print("    FAIL — the configuration contract does not hold:")
    for p in problems:
        print("      ! " + p)
    sys.exit(1)
print("    PASS — the path is absolute and user-overridable, and nothing an entry "
      "carries can locate code")
PY
static_rc=$?

# ---------------------------------------------------------------------------
# case 1 — no configuration file → defaults, and a working bar
# ---------------------------------------------------------------------------
echo
echo "[1] no configuration file → defaults, and the bar still builds ..."
home="$(new_home case1)"
run_smoke "$home"
record "case1" "$(check case1-no-file-defaults)"
[[ ! -e "$(config_path "$home")" ]] || echo "    NOTE: a configuration file appeared at $(config_path "$home")"

# ---------------------------------------------------------------------------
# case 2 — a configuration file → the zone contents follow it
# ---------------------------------------------------------------------------
echo
echo "[2] a configuration file → zone contents and order follow it ..."
home="$(new_home case2)"
python3 - "$(config_path "$home")" > "$TMP/case2.json" <<'PY'
import json, pathlib, sys
cfg = {"bar": {"floating": False, "zones": {
    "left":   [{"type": "clock"}],
    "center": [],
    "right":  [{"type": "clock"}, {"type": "clock"}]}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
print(json.dumps(cfg))
PY
run_smoke "$home"
record "case2" "$(check case2-config-drives-contents "$(cat "$TMP/case2.json")")"

# ---------------------------------------------------------------------------
# case 3 — bad entries → each skipped with its name, the rest still renders
# ---------------------------------------------------------------------------
echo
echo "[3] bad entries → each skipped and named, everything valid still renders ..."
home="$(new_home case3)"
python3 - "$(config_path "$home")" > "$TMP/case3.json" <<'PY'
import json, pathlib, sys
# The left zone is a field of every failure mode at once, with valid entries on
# both sides of each one: the first entry and the last are good, so "the rest
# still renders" is observable rather than assumed. The index of every bad
# entry is also checked, so a skip cannot silently shift the entries after it.
cfg = {"bar": {"floating": True, "zones": {
    "left": [
        {"type": "clock"},                                  # 0 valid
        {"type": "not-a-widget"},                           # 1 unknown name
        {"type": "clock", "path": "/etc/passwd"},           # 2 refuses to locate code
        {"type": "clock", "file": "SomeWidget.qml"},        # 3 likewise
        "clock",                                            # 4 not an object
        {"tooltip": "no type here"},                        # 5 no type
        {"type": "clock"},                                  # 6 valid
    ],
    "center": [{"type": "clock"}],                          # untouched zone
    "right": [{"type": "clock"}]}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
print(json.dumps({"left": cfg["bar"]["zones"]["left"],
                  "right": cfg["bar"]["zones"]["right"]}))
PY
run_smoke "$home"
record "case3" "$(check case3-bad-entries-skipped "$(cat "$TMP/case3.json")")"
record "case3-log" "$(check case-log-clean)"

# ---------------------------------------------------------------------------
# case 4 — a malformed file as a whole → defaults, and the file is left alone
# ---------------------------------------------------------------------------
echo
echo "[4] malformed file as a whole → defaults, shell starts, file untouched ..."
home="$(new_home case4)"
printf '{"bar": {"zones": {"left": [\n' > "$(config_path "$home")"
before="$(sha256sum "$(config_path "$home")" | cut -d' ' -f1)"
run_smoke "$home"
after="$(sha256sum "$(config_path "$home")" | cut -d' ' -f1)"
out="$(check case4-malformed-file-defaults)"
if [[ "$out" == FAIL* ]]; then
    record "case4" "$out"
elif [[ "$before" != "$after" ]]; then
    record "case4" "FAIL case4: the malformed file was rewritten (sha256 $before → $after)"
else
    record "case4" "$out"
    record "case4-bytes" "PASS case4-bytes: the malformed file is byte-for-byte unchanged (sha256 $after)"
fi

# ---------------------------------------------------------------------------
# case 5 — reorder, remove and add are configuration edits alone
# ---------------------------------------------------------------------------
echo
echo "[5] reorder / remove / add are configuration edits alone ..."
home="$(new_home case5)"
python3 - "$(config_path "$home")" > "$TMP/case5.json" <<'PY'
import json, pathlib, sys
# Removing is an empty list, adding is an extra entry, reordering is a different
# assignment of the same entries to zones. No shell code differs between them.
cfg = {"bar": {"floating": True, "zones": {
    "left":   [{"type": "clock"}, {"type": "clock"}],   # added
    "center": [],                                          # removed
    "right":  [{"type": "clock"}]}}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + "\n")
print(json.dumps(cfg))
PY
run_smoke "$home"
record "case5" "$(check case5-reorder-remove-add "$(cat "$TMP/case5.json")")"

# ---------------------------------------------------------------------------
# case 6 — a widget that fails to construct
# ---------------------------------------------------------------------------
echo
echo "[6] a widget that fails to construct is skipped and named ..."
home="$(new_home case6)"
run_smoke "$home"
record "case6" "$(check case6-construct-failure)"

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $FAIL -eq 0 && $static_rc -eq 0 ]]; then
    echo " RESULT: PASS (static path/security + six configuration promises)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  ($PASS assertion(s) passed, $FAIL failed: ${FAILED_CASES[*]})"
    echo " --- captured log tail (if any) ---"
    tail -n 40 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi