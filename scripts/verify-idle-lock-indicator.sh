#!/usr/bin/env bash
#
# verify-idle-lock-indicator.sh — verification for ticket 17.
#
#   An idle-lock indicator on the widget contract: shows whether the machine
#   will lock when idle, toggles through the NosArch session helper only, and
#   documents the helper's inverted semantics at the point of use.
#
# Three checks:
#   (A) STATIC — registry name idle-lock → IdleLockWidget.qml on
#       SimpleBarWidget; reads/writes only nosarch-session idle-lock commands;
#       inversion documented in the widget file.
#   (B) RUNTIME — smoke.qml instantiates the contract widget; no repo QML
#       WARN/ERROR in the log.
#   (C) CONTRACT — SMOKE CONTRACT idle-lock-widget matches the helper's live
#       status inverted (willLock == helper status is not true).
#
# Exit status: 0 only if all three checks pass.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-45}"
HELPER="${NOSARCH_SESSION_HELPER:-/usr/local/bin/nosarch/nosarch-session}"

export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-8000}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-2000}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-1500}"

TMP="$(mktemp -d /tmp/opencode/qs-ticket17.XXXXXX)"
LOG="$TMP/smoke.log"
HOME_DIR="$TMP/home"

static_rc=1
runtime_rc=1
contract_rc=1

cleanup() {
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 17 verification — idle-lock indicator"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC
# ---------------------------------------------------------------------------
echo
echo "[A] static: registry, widget, session helper only ..."
static_out=$(python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
widgets = repo / "shell/widgets"
bad = []
rc = 0

def fail(msg):
    global rc
    bad.append(msg)
    rc = 1

def read(rel):
    p = repo / rel
    return p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""

reg = read("shell/widgets/WidgetRegistry.qml")
if '"idle-lock"' not in reg or '"IdleLockWidget.qml"' not in reg:
    fail("WidgetRegistry missing idle-lock → IdleLockWidget.qml")

path = widgets / "IdleLockWidget.qml"
if not path.is_file():
    fail("missing IdleLockWidget.qml")
    print("FAIL — " + "; ".join(bad))
    sys.exit(rc)

text = read("shell/widgets/IdleLockWidget.qml")
if not re.search(r"\bSimpleBarWidget\b\s*\{", text):
    fail("IdleLockWidget is not on SimpleBarWidget")

if "/usr/local/bin/nosarch/nosarch-session" not in text:
    fail("IdleLockWidget does not name the NosArch session helper path")

if '"idle-lock"' not in text or '"status"' not in text:
    fail("IdleLockWidget does not read idle-lock status through the helper")
if '"idle-lock"' not in text or '"toggle"' not in text:
    fail("IdleLockWidget does not toggle through the helper")

without_comments = re.sub(r"//[^\n]*", "", text)
if re.search(r"\bsystemctl\b", without_comments):
    fail("IdleLockWidget reads systemctl directly — must use the session helper only")

low = text.lower()
if not re.search(r"will not lock|will \*not\* lock|not lock when idle", text, re.I):
    fail("IdleLockWidget does not document that helper true/enabled means locking will NOT happen")
if "inhibit" not in low:
    fail("IdleLockWidget does not document that the helper names the inhibit")

qmldir = read("shell/widgets/qmldir")
if "IdleLockWidget" not in qmldir:
    fail("shell/widgets/qmldir missing IdleLockWidget")

if rc == 0:
    print("PASS — registry, widget, and helper-only seam")
else:
    print("FAIL — " + "; ".join(bad))
sys.exit(rc)
PY
)
static_rc=$?
echo "$static_out" | sed 's/^/    /'

# ---------------------------------------------------------------------------
# (B) RUNTIME — smoke launch
# ---------------------------------------------------------------------------
echo
echo "[B] runtime: smoke.qml (IdleLockWidget instantiates) ..."
mkdir -p "$HOME_DIR/.config/quickshell/nosarch"
runtime_rc=1
cd "$REPO" || exit 1
HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 1 $((RUN_SECS * 10))); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
wait "$pid" 2>/dev/null || true

python3 - "$LOG" "$REPO" <<'PY'
import re, sys, pathlib
log, repo = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
problems = []
for ln in log.read_text(errors="replace").splitlines():
    m = re.search(r"(?:WARN|ERROR)\s+(?:qml:)?\s*qs?:?/?(\S+?):\d+", ln)
    if not m:
        continue
    if str(repo) in ln or ln.strip().startswith("qs:" + str(repo)):
        problems.append(ln.strip())
if problems:
    print("    FAIL — repo QML warnings/errors:")
    for p in problems[:8]:
        print(f"       {p}")
    sys.exit(1)
if "SMOKE SUMMARY" not in log.read_text(errors="replace"):
    print("    FAIL — smoke did not reach SMOKE SUMMARY")
    sys.exit(1)
print("    PASS — smoke finished with a clean repo QML log")
sys.exit(0)
PY
runtime_rc=$?

# ---------------------------------------------------------------------------
# (C) CONTRACT — widget matches helper (inverted)
# ---------------------------------------------------------------------------
echo
echo "[C] contract: idle-lock-widget vs session helper status ..."
contract_out=$(python3 - "$LOG" "$HELPER" <<'PY'
import re, subprocess, sys, pathlib

log_path = pathlib.Path(sys.argv[1])
helper = pathlib.Path(sys.argv[2])
log = log_path.read_text(errors="replace").splitlines()

def contract_val():
    for ln in log:
        if "SMOKE CONTRACT idle-lock-widget " in ln:
            return ln.split("SMOKE CONTRACT idle-lock-widget ", 1)[1].strip()
    return None

bad = []
rc = 0
val = contract_val()
if val is None:
    bad.append("missing SMOKE CONTRACT idle-lock-widget")
    rc = 1
elif "ERROR=" in val:
    bad.append(f"idle-lock probe failed: {val}")
    rc = 1
else:
    m = re.search(r"\bwillLock=(true|false)\b", val)
    if not m:
        bad.append(f"idle-lock-widget line has no willLock=: {val!r}")
        rc = 1
    elif not helper.is_file():
        print("    SKIP — no session helper to compare (willLock reported as "
              + m.group(1) + " only)")
        sys.exit(0)
    else:
        try:
            out = subprocess.run(
                [str(helper), "idle-lock", "status"],
                capture_output=True, text=True, timeout=10, check=True,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as e:
            bad.append(f"could not run helper idle-lock status: {e}")
            rc = 1
        else:
            inhibit = out.stdout.strip().lower() == "true"
            expected_will_lock = "false" if inhibit else "true"
            if m.group(1) != expected_will_lock:
                bad.append(
                    f"widget willLock={m.group(1)} but helper status={out.stdout.strip()!r} "
                    f"(inhibit running={inhibit}) — indicator disagrees with reality"
                )
                rc = 1
            if "toggle=idle-lock/toggle" not in val:
                bad.append("idle-lock-widget line does not record toggle=idle-lock/toggle")
                rc = 1

if rc == 0:
    print("PASS — idle-lock indicator matches the helper (inverted)")
else:
    print("FAIL — " + "; ".join(bad))
sys.exit(rc)
PY
)
contract_rc=$?
echo "$contract_out" | sed 's/^/    /'

echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $runtime_rc -eq 0 && $contract_rc -eq 0 ]]; then
    echo " Ticket 17 verification: PASS"
    exit 0
fi
echo " Ticket 17 verification: FAIL (static=$static_rc runtime=$runtime_rc contract=$contract_rc)"
exit 1
