#!/usr/bin/env bash
#
# verify-smoke.sh — verification for ticket 03.
#
#   "Nothing objects when a widget breaks: Quickshell prints QML errors and
#    still exits 0. This is the first verification artefact in the codebase —
#    one seam that instantiates every widget, service and shared component and
#    fails on type errors, missing properties and unresolved bindings."
#
# Three checks:
#   (A) STATIC — the smoke plan covers the whole tree: every singleton and type
#       in services/qmldir, every module in shell/topisland/modules/, every
#       contract widget in shell/widgets/qmldir and every component in
#       components/qmldir must be planned by smoke.qml. A widget that exists but
#       is never instantiated is a silent gap, so the plan is checked against
#       the tree rather than trusted.
#   (B) RUNTIME — smoke.qml is launched and every planned item must report
#       PASS, by name.
#   (C) LOG — the log is scanned for what the exit code cannot show. Quickshell
#       exits 0 even when every binding throws, so WARN/ERROR lines are the
#       only signal: any WARN or ERROR that names a file in this repo fails the
#       run. Warnings with no repo file attached (xdg-desktop-portal, Qt
#       platform services, the Hyprland IPC service noticing a mid-session
#       attach) are third-party noise and do not fail it.
#
# Why (C) is not over-strict: in Quickshell a type error, a missing property
# and an unresolved binding all surface as WARN lines naming the file at
# fault, so failing only on the process exit code would pass a shell where
# every widget throws — the exact failure this ticket exists to catch. The
# check can afford strictness because smoke.qml lets services populate before
# instantiating anything, so the transient "property of null" churn while
# hardware comes up never appears in the log at all.
#
# SAFETY (the live desktop is running): the smoke shell runs under
# `dbus-run-session`, so its NotificationServer owns
# org.freedesktop.Notifications on a throwaway private bus and cannot disturb
# swaync, which owns the real one. smoke.qml creates NO layer-shell surfaces
# (every instantiated object is parented to plain in-memory Items), so nothing
# is drawn and waybar / hyprpaper / swayosd are never involved. Nothing is
# written to ~/.config or any installed location. HOME is redirected to a
# scratch directory because the file-backed palette (ticket 04) writes
# ~/.local/share/nosarch/current-theme/palette.json on first run — the path
# is resolved from HOME, so the write lands in the scratch home and the live
# theme directory is never touched.
#
# Exit status: 0 only if all three checks pass.
#
set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"
TMP="$(mktemp -d /tmp/opencode/qs-smoke.XXXXXX)"
LOG="$TMP/smoke.log"

static_rc=1
runtime_rc=1
log_rc=1

cleanup() {
    # Kill only THIS smoke shell: its cmdline carries this worktree's unique
    # path. Never a broad pkill — other shells and verifiers run on this
    # machine and must not be hit.
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 03 verification — smoke-test entrypoint (every widget/service)"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC: the plan in smoke.qml covers everything that exists
# ---------------------------------------------------------------------------
echo
echo "[A] static plan coverage ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])

def qmldir_names(relpath):
    """Registered names from a qmldir (singleton or plain type)."""
    names = []
    for line in (repo / relpath).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('module '):
            continue
        parts = line.split()
        if len(parts) >= 2:
            names.append(parts[1] if parts[0] == 'singleton' else parts[0])
    return names

smoke = (repo / 'smoke.qml').read_text()

def planned(block_name):
    m = re.search(block_name + r':\s*\[(.*?)\]', smoke, re.S)
    if not m:
        return set()
    return {n.removesuffix('.qml') for n in re.findall(r'name:\s*"([^"]+)"', m.group(1))}

sources = (
    ("services/qmldir", set(qmldir_names('services/qmldir')), planned('servicePlan')),
    ("shell/topisland/modules/", {f.stem for f in (repo / 'shell/topisland/modules').glob('*.qml')}, planned('widgetPlan')),
    # The contract widgets (ticket 06) live in their own directory with their
    # own qmldir, and are planned in their own plan block. They are widgets
    # like any other, so they get the same both-directions coverage.
    ("shell/widgets/qmldir", set(qmldir_names('shell/widgets/qmldir')), planned('contractWidgetPlan')),
    # The bar's own directory (ticket 07): the configuration reader and one
    # zone. Same rule — a type that exists but is never instantiated is a
    # silent gap, and a plan entry with no type is a test that stopped testing
    # anything.
    ("shell/bar/qmldir", set(qmldir_names('shell/bar/qmldir')), planned('configPlan')),
    ("components/qmldir", set(qmldir_names('components/qmldir')), planned('componentPlan')),
)

problems = []
for label, expected, actual in sources:
    print(f"    {label}: {len(expected)} exist, {len(actual)} planned")
    missing = sorted(expected - actual)
    if missing:
        problems.append(f"{label} exists but is NOT in the smoke plan: {', '.join(missing)}")
    stale = sorted(actual - expected)
    if stale:
        problems.append(f"{label} is planned but no longer exists: {', '.join(stale)}")

if problems:
    print("    FAIL — plan does not cover the shell:")
    for p in problems:
        print("      !", p)
    sys.exit(1)
print("    PASS — every service, widget and component is in the smoke plan")
PY
static_rc=$?

# ---------------------------------------------------------------------------
# (B) RUNTIME: launch smoke.qml and collect its per-item report
# ---------------------------------------------------------------------------
echo
echo "[B] runtime instantiation (isolated bus, up to ${RUN_SECS}s) ..."

# Run from the repo root. smoke.qml's component paths and the modules' own
# imports are directory-relative, and Quickshell only loads files at or below
# the config root (the -p file's directory) — hence smoke.qml at the root.
#
# HOME is pointed at a scratch dir: the palette resolves its file from HOME
# and writes it on first run, so this keeps the live theme directory out of
# the run (see the SAFETY note above).
mkdir -p "$TMP/home"
cd "$REPO" || exit 1
HOME="$TMP/home" timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &

# Wait for the summary line the smoke shell prints before it quits.
summary_ok=false
for _ in $(seq 1 $((RUN_SECS * 10))); do
    grep -q "SMOKE SUMMARY" "$LOG" 2>/dev/null && { summary_ok=true; break; }
    sleep 0.1
done
if [[ "$summary_ok" != true ]]; then
    echo "    ERROR: no SMOKE SUMMARY line within ${RUN_SECS}s"
    runtime_rc=1
fi

echo
echo "[B] per-item report ..."
python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()

def smoke_tokens(ln):
    """'... INFO qml: SMOKE PASS widget Clock.qml — detail' -> ['PASS','widget','Clock.qml', ...]"""
    i = ln.find('SMOKE ')
    return ln[i + 6:].split() if i != -1 else []

plan, passed, failed = [], [], []
for ln in lines:
    t = smoke_tokens(ln)
    if not t or t[0] not in ('PLAN', 'PASS', 'FAIL'):
        continue
    kind, name = (t[1], t[2]) if len(t) > 2 else ('?', '?')
    if t[0] == 'PLAN':
        plan.append((kind, name))
    elif t[0] == 'PASS':
        passed.append((kind, name))
    else:
        failed.append((kind, name, ' '.join(t[3:])))

rc = 0
for kind in ("service", "widget", "component", "config"):
    names = [n for k, n in plan if k == kind]
    if not names:
        continue
    print(f"    {kind}s ({len(names)} planned):")
    for name in names:
        detail = next((d for k, n, d in failed if n == name), None)
        if detail:
            print(f"      FAIL {name}: {detail}")
            rc = 1
        elif any(n == name for _, n in passed):
            print(f"      pass {name}")
        else:
            print(f"      MISS {name}: no PASS line in the log")
            rc = 1

summary = next((l for l in lines if "SMOKE SUMMARY" in l), None)
if summary:
    print("    " + summary.split("INFO qml:", 1)[-1].strip())
if rc == 0 and plan:
    print("    PASS — every planned item reported PASS")
elif rc == 0:
    print("    FAIL — no SMOKE PLAN lines; the smoke shell never ran")
    rc = 1
else:
    print("    FAIL — instantiation did not succeed for every planned item")
sys.exit(rc)
PY
runtime_rc=$?

# ---------------------------------------------------------------------------
echo
echo "[C] log analysis — warnings and errors from this repo's QML ..."
python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()

# Quickshell's own log lines look like:
#   "<ts>  WARN|ERROR <source>: @<file>[line:col]: message"
# A line naming a file inside this repo is a defect in this repo's QML.
qline = re.compile(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\s+(WARN|ERROR)\s+(.*)$')
repo_file = re.compile(r'@([^\s:\[]+)\[')

problems, ignored = [], []
for ln in lines:
    m = qline.match(ln)
    if not m:
        continue                                  # third-party noise (portal/dbus/glib)
    level, rest = m.group(1), m.group(2)
    f = repo_file.search(rest)
    attributed = bool(f) and (f.group(1) == 'smoke.qml'
                              or f.group(1).startswith(('services/', 'shell/', 'components/')))
    if attributed:
        problems.append((level, rest))
    else:
        ignored.append(rest)                      # attributable to no repo file

fatal = [l.strip() for l in lines if any(s in l for s in (
    "Failed to load configuration", "is not a type", "Component is not ready"))]

for level, rest in problems:
    print(f"    ! {level} {rest}")
for f in fatal:
    print(f"    ! FATAL {f}")

if problems or fatal:
    print(f"    FAIL — {len(problems)} repo QML warning(s)/error(s), {len(fatal)} fatal line(s)")
    sys.exit(1)
print(f"    PASS — no WARN/ERROR naming a repo QML file "
      f"({len(ignored)} unattributable third-party line(s) ignored: portal/platform noise)")
PY
log_rc=$?

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $runtime_rc -eq 0 && $log_rc -eq 0 ]]; then
    echo " RESULT: PASS (plan coverage + runtime + log)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  (static=$([[ $static_rc -eq 0 ]] && echo ok || echo FAIL), runtime=$([[ $runtime_rc -eq 0 ]] && echo ok || echo FAIL), log=$([[ $log_rc -eq 0 ]] && echo ok || echo FAIL))"
    echo " --- captured log tail (if any) ---"
    tail -n 40 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi
