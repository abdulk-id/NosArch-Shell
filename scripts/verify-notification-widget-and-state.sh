#!/usr/bin/env bash
#
# verify-notification-widget-and-state.sh — verification for ticket 16.
#
#   "A notification indicator shows whether anything is waiting, toggles
#    do-not-disturb on click, looks different while DND is on, and keeps DND
#    across a shell restart. State lives in the framework's per-shell state
#    directory; the indicator and notification behaviour read one source."
#
# Four checks:
#   (A) STATIC — NotificationWidget is on the contract and registered; ShellState
#       persists through Quickshell.statePath; no service holds PersistentProperties.
#   (B) RUNTIME — smoke constructs the widget and reports contract probes.
#   (C) PERSISTENCE — a first run with no state file writes DND when asked; a
#       second run from the same config path reads it back.
#   (D) SINGLE SOURCE — the widget's reported DND matches NotificationService.
#
# SAFETY: every launch runs under `dbus-run-session` with HOME redirected to a
# scratch directory (palette first-run). State files are keyed by config path;
# cases (C) log the path and remove only that file in cleanup.
#
# Exit status: 0 only if all checks pass.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"

export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-800}"

TMP="$(mktemp -d /tmp/opencode/qs-notif.XXXXXX)"
LOG="$TMP/smoke.log"
STATE_FILE=""

static_rc=1
runtime_rc=1
persist_rc=1
single_rc=1

cleanup() {
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    if [[ -n "${STATE_FILE:-}" && -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
    fi
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 16 verification — notification widget and persisted DND state"
echo " repo: $REPO"
echo "======================================================================"

run_smoke() {
    local home="$1"
    local extra_env=("${@:2}")
    cd "$REPO" || return 1
    env HOME="$home" "${extra_env[@]}" timeout "$RUN_SECS" dbus-run-session -- \
        quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &
    local pid=$!
    local i
    for i in $(seq 1 $((RUN_SECS * 10))); do
        kill -0 "$pid" 2>/dev/null || break
        grep -q "SMOKE SUMMARY" "$LOG" 2>/dev/null && break
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# (A) STATIC
# ---------------------------------------------------------------------------
echo
echo "[A] static widget, state seam, and no persistent properties in services ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
problems = []

widgets_dir = repo / "shell/widgets"
notif = widgets_dir / "NotificationWidget.qml"
if not notif.is_file():
    problems.append("shell/widgets/NotificationWidget.qml missing")
else:
    text = notif.read_text(encoding="utf-8", errors="replace")
    if not re.search(r"\bBarWidget\b\s*\{", text):
        problems.append("NotificationWidget.qml does not extend BarWidget")

reg = (widgets_dir / "WidgetRegistry.qml").read_text(encoding="utf-8", errors="replace")
if '"notification"' not in reg or "NotificationWidget.qml" not in reg:
    problems.append("WidgetRegistry has no notification → NotificationWidget.qml entry")

shell_state = repo / "shell/state/ShellState.qml"
if not shell_state.is_file():
    problems.append("shell/state/ShellState.qml missing")
else:
    st = shell_state.read_text(encoding="utf-8", errors="replace")
    if "Quickshell.statePath" not in st:
        problems.append("ShellState does not use Quickshell.statePath")
    if "PersistentProperties" in st:
        problems.append("ShellState uses PersistentProperties — disk is the seam")

for svc in (repo / "services").glob("*.qml"):
    body = svc.read_text(encoding="utf-8", errors="replace")
    if "PersistentProperties" in body:
        problems.append(f"{svc.name} uses PersistentProperties")

ns = repo / "services/NotificationService.qml"
if ns.is_file():
    nst = ns.read_text(encoding="utf-8", errors="replace")
    if re.search(r"property\s+bool\s+doNotDisturb\s*:\s*false\s*$", nst, re.M):
        problems.append("NotificationService still owns doNotDisturb as a local default "
                        "instead of ShellState")

if problems:
    print("    FAIL —")
    for p in problems:
        print("      !", p)
    sys.exit(1)
print("    PASS — NotificationWidget on contract, ShellState on statePath, "
      "services hold no PersistentProperties")
PY
static_rc=$?

# ---------------------------------------------------------------------------
# (B) RUNTIME — smoke + contract probes
# ---------------------------------------------------------------------------
echo
echo "[B] runtime smoke and notification contract probes ..."
HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR"
run_smoke "$HOME_DIR"
LOG_B="$TMP/smoke-b.log"
cp "$LOG" "$LOG_B"

if ! grep -q "SMOKE SUMMARY" "$LOG" 2>/dev/null; then
    echo "    ERROR: no SMOKE SUMMARY"
    tail -n 25 "$LOG" 2>/dev/null
    runtime_rc=1
else
    python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
problems = []

if not any("SMOKE PASS widget NotificationWidget.qml" in ln for ln in lines):
    problems.append("NotificationWidget did not PASS in smoke")

contract = {}
for ln in lines:
    m = re.search(r"SMOKE CONTRACT (\S+) (.+)$", ln)
    if m:
        contract[m.group(1)] = m.group(2)

for key in ("notification-dnd-visual", "notification-waiting", "notification-source"):
    if key not in contract:
        problems.append(f"missing SMOKE CONTRACT {key}")

if problems:
    print("    FAIL —")
    for p in problems:
        print("      !", p)
    sys.exit(1)
print("    PASS — widget instantiated and contract probes present")
PY
    runtime_rc=$?
fi

# ---------------------------------------------------------------------------
# (C) PERSISTENCE — write on first run, read on second
# ---------------------------------------------------------------------------
echo
echo "[C] persisted do-not-disturb across two launches ..."
HOME_DIR="$TMP/home-persist"
mkdir -p "$HOME_DIR"

run_smoke "$HOME_DIR" NOSARCH_SMOKE_DND=enable
path_line=$(grep -m1 "nosarch-shell ▸ STATE verdict" "$LOG" || true)
if [[ -z "$path_line" ]]; then
    echo "    FAIL — no STATE verdict line in first run"
    persist_rc=1
else
    STATE_FILE=$(echo "$path_line" | sed -n 's/.* path=\([^ ]*\).*/\1/p')
    if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
        echo "    FAIL — state file not written on first run (path=$STATE_FILE)"
        persist_rc=1
    elif ! grep -q '"doNotDisturb"[[:space:]]*:[[:space:]]*true' "$STATE_FILE"; then
        echo "    FAIL — state file does not record doNotDisturb=true"
        echo "    --- file ---"; cat "$STATE_FILE"
        persist_rc=1
    else
        run_smoke "$HOME_DIR"
        if grep -q "nosarch-shell ▸ STATE verdict.* doNotDisturb=true" "$LOG"; then
            echo "    PASS — second launch read doNotDisturb=true from disk"
            persist_rc=0
        else
            echo "    FAIL — second launch did not report doNotDisturb=true"
            grep "STATE verdict" "$LOG" || true
            persist_rc=1
        fi
    fi
fi

# ---------------------------------------------------------------------------
# (D) SINGLE SOURCE — service and widget agree in the probe line
# ---------------------------------------------------------------------------
echo
echo "[D] indicator and NotificationService share one do-not-disturb value ..."
if [[ "$runtime_rc" -ne 0 ]]; then
    echo "    SKIP — runtime check failed"
    single_rc=1
else
    python3 - "$LOG_B" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
src = next((ln for ln in lines if "SMOKE CONTRACT notification-source" in ln), "")
if not src:
    print("    FAIL — no notification-source contract line")
    sys.exit(1)
m = re.search(r"service=(true|false).*widget=(true|false)", src)
if not m or m.group(1) != m.group(2):
    print("    FAIL — service and widget disagree:", src.strip())
    sys.exit(1)
print("    PASS — service and widget report the same doNotDisturb")
PY
    single_rc=$?
fi

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $runtime_rc -eq 0 && $persist_rc -eq 0 && $single_rc -eq 0 ]]; then
    echo " PASS — ticket 16 (notification widget and persisted DND state)"
    exit 0
fi
echo " FAIL — static=$static_rc runtime=$runtime_rc persist=$persist_rc single=$single_rc"
exit 1
