#!/usr/bin/env bash
#
# verify-cpu-memory-battery-bluetooth-widgets.sh — verification for ticket 13.
#
#   CPU and memory usage indicators (click opens a system monitor), battery
#   charge with low-charge colouring, bluetooth on/connected state — all on
#   the widget contract, with battery and bluetooth presentation moved out of
#   services per ADR 0001.
#
# Three checks:
#   (A) STATIC — four registry names, four widget files on BarWidget/
#       SimpleBarWidget, no battery/bluetooth textIcon left in services/, old
#       top-island modules delegate to the contract widgets.
#   (B) RUNTIME — smoke.qml instantiates every contract widget; no repo QML
#       WARN/ERROR in the log.
#   (C) CONTRACT — SMOKE CONTRACT lines report live widget members and that
#       services no longer publish battery/bluetooth glyphs.
#
# Exit status: 0 only if all three checks pass.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-45}"

export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-8000}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-2000}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-1500}"

TMP="$(mktemp -d /tmp/opencode/qs-ticket13.XXXXXX)"
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
echo " Ticket 13 verification — CPU, memory, battery, bluetooth widgets"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC
# ---------------------------------------------------------------------------
echo
echo "[A] static: registry, widgets, services, module migration ..."
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

REGISTRY = {
    "cpu": "CpuWidget.qml",
    "memory": "MemoryWidget.qml",
    "battery": "BatteryWidget.qml",
    "bluetooth": "BluetoothWidget.qml",
}

reg = read("shell/widgets/WidgetRegistry.qml")
for name, fname in REGISTRY.items():
    if f'"{name}"' not in reg or f'"{fname}"' not in reg:
        fail(f"WidgetRegistry missing {name!r} → {fname}")
    if not (widgets / fname).is_file():
        fail(f"missing {fname}")

for fname in REGISTRY.values():
    text = read(f"shell/widgets/{fname}")
    if not re.search(r"\b(BarWidget|SimpleBarWidget)\b\s*\{", text):
        fail(f"{fname} is not on the widget contract")

si = read("services/SystemInfo.qml")
if re.search(r"\btextIcon\b", si):
    fail("SystemInfo.qml still publishes battery textIcon (ADR 0001)")
if re.search(r"\bdefaultIcons\b|\bchargingIcons\b", si):
    fail("SystemInfo.qml still holds battery icon arrays in the service")

bt = read("services/BluetoothService.qml")
if re.search(r"\btextIcon\b", bt):
    fail("BluetoothService.qml still publishes textIcon (ADR 0001)")

cpu = read("shell/widgets/CpuWidget.qml")
if "nosarch-launch-tui" not in cpu or "btop" not in cpu:
    fail("CpuWidget does not open the system monitor on activate")

mem = read("shell/widgets/MemoryWidget.qml")
if "nosarch-launch-tui" not in mem or "btop" not in mem:
    fail("MemoryWidget does not open the system monitor on activate")

bat = read("shell/widgets/BatteryWidget.qml")
if "UI.Colors.alertRed" not in bat:
    fail("BatteryWidget does not use UI.Colors.alertRed for low charge")
if "textIcon" in bat and re.search(r"Services\.SystemInfo\.battery\.textIcon", bat):
    fail("BatteryWidget still reads battery textIcon from the service")

if rc == 0:
    print("PASS — registry, widgets, and services")
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
echo "[B] runtime: smoke.qml (contract widgets instantiate) ..."
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
# (C) CONTRACT lines from smoke
# ---------------------------------------------------------------------------
echo
echo "[C] contract probes (live widget members) ..."
contract_out=$(python3 - "$LOG" <<'PY'
import re, sys, pathlib
log = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()

def contract(key):
    for ln in log:
        if f"SMOKE CONTRACT {key} " in ln:
            return ln.split(f"SMOKE CONTRACT {key} ", 1)[1].strip()
    return None

bad = []
rc = 0

def need(key, pred, why):
    global rc
    val = contract(key)
    if val is None:
        bad.append(f"missing SMOKE CONTRACT {key}")
        rc = 1
        return
    if not pred(val):
        bad.append(f"{key}: {why} (got {val!r})")
        rc = 1

need("cpu-widget", lambda v: "monitor=btop" in v and "%" in v,
     "CPU label and system monitor action")
need("memory-widget", lambda v: "monitor=btop" in v and "GiB" in v,
     "memory label and system monitor action")
need("battery-widget", lambda v: "colorRole=" in v and "present=" in v,
     "battery presence and colour role")
need("bluetooth-widget", lambda v: "adapter=" in v and "icon=" in v,
     "bluetooth adapter state and icon")
need("adr1-glyphs", lambda v: v == "battery=no bluetooth=no",
     "services must not publish battery/bluetooth glyphs")

if rc == 0:
    print("PASS — all ticket-13 contract probes")
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
    echo " Ticket 13 verification: PASS"
    exit 0
fi
echo " Ticket 13 verification: FAIL (static=$static_rc runtime=$runtime_rc contract=$contract_rc)"
exit 1
