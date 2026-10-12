#!/usr/bin/env bash
#
# verify-real-shell-startup.sh — verification for ticket 18.
#
#   "A scripted run of the real shell fails on QML warnings, catching failures
#    that only appear once real services connect. The shell starts with no errors
#    in the log, including when the configuration file is absent."
#
# Three checks:
#   (A) STATIC  — BarConfig.defaultConfiguration names all twelve cutover widgets
#       in the same layout the pre-rewrite bar carried, and nothing outside the
#       registry.
#   (B) RUNTIME — the real shell.qml launches under an isolated bus with no
#       configuration file at all; the log must show a fresh start and a mapped bar.
#   (C) LOG     — any WARN/ERROR line naming a file in this repo fails the run
#       (same rule as verify-smoke.sh: Quickshell exits 0 even when bindings throw).
#
# SAFETY (the live desktop is running): the shell runs under `dbus-run-session`
# with HOME and XDG_CONFIG_HOME pointed at scratch directories so the reader
# never touches ~/.config. Layer-shell surfaces flash briefly; the process is
# killed once the bar reports. Only this script's shells are killed on exit.
#
# Exit status: 0 only if all three checks pass.
#
set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SHELL_QML="shell.qml"
RUN_SECS="${SHELL_RUN_SECS:-25}"
TMP="$(mktemp -d /tmp/opencode/qs-real-startup.XXXXXX)"
LOG="$TMP/run.log"

static_rc=1
runtime_rc=1
log_rc=1

cleanup() {
    pkill -f "quickshell.*${TMP}/shell/shell.qml" 2>/dev/null || true
    pkill -f "dbus-run-session.*${TMP}/shell/shell.qml" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 18 verification — real shell startup, twelve widgets, clean log"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC: built-in defaults carry the full twelve-widget bar
# ---------------------------------------------------------------------------
echo
echo "[A] static default configuration ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib

repo = pathlib.Path(sys.argv[1])
cfg_path = repo / "shell/bar/BarConfig.qml"
text = cfg_path.read_text(encoding="utf-8", errors="replace")

# Pull the defaultConfiguration object — it is a literal in one place only.
m = re.search(
    r"readonly property var defaultConfiguration:\s*\(\s*\{.*?\"zones\"\s*:\s*\{(.*?)\}\s*\}\s*\}\s*\)",
    text,
    re.S,
)
if not m:
    print("    FAIL — could not find defaultConfiguration zones in BarConfig.qml")
    sys.exit(1)
types = re.findall(r'"type"\s*:\s*"([^"]+)"', m.group(0))

want = {
    "launcher", "workspaces", "cpu", "memory", "player", "clock",
    "tray", "network", "bluetooth", "volume", "battery", "notification",
}
got = set(types)
problems = []
if len(types) != 12:
    problems.append(f"expected 12 widget entries in defaults, got {len(types)}: {types}")
if got != want:
    problems.append(f"defaults name {sorted(got)}; want {sorted(want)}")

reg = (repo / "shell/widgets/WidgetRegistry.qml").read_text(encoding="utf-8", errors="replace")
entries = set(re.findall(r'"([a-z0-9-]+)"\s*:\s*"[^"]+\.qml"', reg))
for t in types:
    if t not in entries:
        problems.append(f"default widget type {t!r} is not in WidgetRegistry.entries")

if problems:
    for p in problems:
        print("      !", p)
    print("    FAIL — built-in defaults are not the twelve-widget cutover layout")
    sys.exit(1)
print("    PASS — defaultConfiguration lists all twelve cutover widgets")
PY
static_rc=$?

# ---------------------------------------------------------------------------
# (B) RUNTIME: real shell, no configuration file
# ---------------------------------------------------------------------------
echo
echo "[B] runtime real shell (no config file, isolated bus, up to ${RUN_SECS}s) ..."

scratch_home="$TMP/home"
scratch_cfg_root="$scratch_home/.config"
mkdir -p "$scratch_cfg_root"
theme_dir="$scratch_home/.local/share/nosarch/current-theme"
mkdir -p "$theme_dir"
# Wallpaper.qml reads this path on every real-shell launch; an absent file is a
# WARN in the log, not a bar defect, but this check is whole-shell.
python3 - "$theme_dir/current-wallpaper" <<'PY'
import base64, pathlib, sys
# 1×1 PNG so Wallpaper.qml loads without a scene WARN on a scratch home.
pathlib.Path(sys.argv[1]).write_bytes(base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
))
PY
# Deliberately no quickshell/nosarch/shell.json — defaults must carry the bar.

rm -rf "$TMP/shell"
mkdir -p "$TMP/shell"
cp "$REPO/shell.qml" "$TMP/shell/shell.qml"
cp -r "$REPO/shell" "$TMP/shell/shell"
cp -r "$REPO/services" "$TMP/shell/services"
cp -r "$REPO/components" "$TMP/shell/components"

HOME="$scratch_home" XDG_CONFIG_HOME="$scratch_cfg_root" \
    timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$TMP/shell/shell.qml" >"$LOG" 2>&1 &
pid=$!

fresh_ok=false
bar_ok=false
for _ in $(seq 1 $((RUN_SECS * 10))); do
    grep -q "STARTED FRESH" "$LOG" 2>/dev/null && fresh_ok=true
    grep -qE "BAR surface .*width=[1-9][0-9]* " "$LOG" 2>/dev/null && bar_ok=true
    if [[ "$fresh_ok" == true && "$bar_ok" == true ]]; then
        break
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
wait "$pid" 2>/dev/null

runtime_rc=0
if [[ "$fresh_ok" != true ]]; then
    echo "    ERROR: no STARTED FRESH line within ${RUN_SECS}s"
    runtime_rc=1
fi
if [[ "$bar_ok" != true ]]; then
    echo "    ERROR: the bar never reported a mapped surface with non-zero width"
    runtime_rc=1
fi
if [[ $runtime_rc -eq 0 ]]; then
    echo "    PASS — real shell started fresh and mapped the bar with no config file"
fi

# ---------------------------------------------------------------------------
echo
echo "[C] log analysis — warnings and errors from this repo's QML ..."
python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()

qline = re.compile(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\s+(WARN|ERROR)\s+(.*)$')
repo_file = re.compile(r'@([^\s:\[]+)\[')

problems, ignored = [], []
for ln in lines:
    m = qline.match(ln)
    if not m:
        continue
    level, rest = m.group(1), m.group(2)
    f = repo_file.search(rest)
    attributed = bool(f) and (f.group(1) == 'shell.qml'
                              or f.group(1).startswith(('services/', 'shell/', 'components/')))
    if attributed:
        problems.append((level, rest))
    else:
        ignored.append(rest)

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
      f"({len(ignored)} unattributable third-party line(s) ignored)")
PY
log_rc=$?

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $runtime_rc -eq 0 && $log_rc -eq 0 ]]; then
    echo " RESULT: PASS (static + runtime + log)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  (static=$([[ $static_rc -eq 0 ]] && echo ok || echo FAIL), runtime=$([[ $runtime_rc -eq 0 ]] && echo ok || echo FAIL), log=$([[ $log_rc -eq 0 ]] && echo ok || echo FAIL))"
    echo " --- captured log tail (if any) ---"
    tail -n 50 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi
