#!/usr/bin/env bash
#
# verify-workspaces-tray-launcher-widgets.sh — verification for ticket 15.
#
#   Workspace indicators (existence, focus, dim empty, click to switch),
#   system tray (icons, three-button handling and menu anchoring carried
#   forward), and a launcher icon that opens nosarch-launcher.
#
# Three checks:
#   (A) STATIC — the three widgets live on the contract in shell/widgets/,
#       the registry names workspaces, tray and launcher, and the tray and
#       launcher sources still carry the behaviours the pre-rewrite modules
#       had (three mouse buttons, QsMenuAnchor, nosarch-launcher).
#   (B) RUNTIME — smoke.qml instantiates every contract widget and reports PASS.
#   (C) RESOLUTION — smoke CONTRACT lines read the widgets' promises off live
#       instances (content handles its own clicks, workspace dim colours,
#       launcher command, tray button mask).
#
# SAFETY (the live desktop is running): smoke.qml runs under `dbus-run-session`
# with HOME redirected to a scratch directory. No layer-shell surfaces.
#
# Exit status: 0 only if all three checks pass.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"

export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-800}"

TMP="$(mktemp -d /tmp/opencode/qs-wtl.XXXXXX)"
LOG="$TMP/smoke.log"
HOME_DIR="$TMP/home"

static_rc=1
runtime_rc=1
resolve_rc=1

cleanup() {
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 15 verification — workspaces, tray, and launcher widgets"
echo " repo: $REPO"
echo "======================================================================"

echo
echo "[A] static registry + migrated behaviours ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
widgets = repo / "shell/widgets"
problems = []

def read(p):
    return p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""

reg = read(widgets / "WidgetRegistry.qml")
entries = dict(re.findall(r'["\']([^"\']+)["\']\s*:\s*["\']([^"\']+)["\']',
                          re.search(r"entries\s*:\s*\(?\{(.*?)\}\)?", reg, re.S).group(1)
                          if reg and re.search(r"entries\s*:\s*\(?\{(.*?)\}\)?", reg, re.S) else ""))

required = {
    "workspaces": "Workspaces.qml",
    "tray": "Tray.qml",
    "launcher": "Launcher.qml",
}
for name, fname in required.items():
    if entries.get(name) != fname:
        problems.append(f"registry must map {name!r} → {fname!r}, got {entries.get(name)!r}")
    if not (widgets / fname).is_file():
        problems.append(f"missing {fname}")

ws = read(widgets / "Workspaces.qml")
if ws:
    if not re.search(r"\bBarWidget\b\s*\{", ws):
        problems.append("Workspaces.qml must extend BarWidget")
    if "foregroundMuted" not in ws or "foreground" not in ws:
        problems.append("Workspaces.qml must dim empty workspaces (foreground vs foregroundMuted)")
    if "contentHandlesClicks" not in ws or "true" not in ws.split("contentHandlesClicks", 1)[-1][:40]:
        problems.append("Workspaces.qml must set contentHandlesClicks so per-workspace clicks work")
    if ".activate()" not in ws and "activate()" not in ws:
        problems.append("Workspaces.qml must switch workspace on click")

tray = read(widgets / "Tray.qml")
if tray:
    if not re.search(r"\bBarWidget\b\s*\{", tray):
        problems.append("Tray.qml must extend BarWidget")
    if "Qt.LeftButton | Qt.RightButton | Qt.MiddleButton" not in tray.replace("\n", " "):
        problems.append("Tray.qml must accept left, right and middle buttons on tray icons")
    if "secondaryActivate()" not in tray:
        problems.append("Tray.qml must call secondaryActivate on middle-click")
    if "menuAnchor.open()" not in tray:
        problems.append("Tray.qml must open the menu anchor on right-click")
    if "QsMenuAnchor" not in tray:
        problems.append("Tray.qml must keep QsMenuAnchor menu anchoring")
    if "contentHandlesClicks" not in tray:
        problems.append("Tray.qml must set contentHandlesClicks so icon clicks are not swallowed")

launcher = read(widgets / "Launcher.qml")
if launcher:
    if "nosarch-launcher" not in launcher:
        problems.append("Launcher.qml must open nosarch-launcher")
    if not re.search(r"\b(BarWidget|SimpleBarWidget)\b\s*\{", launcher):
        problems.append("Launcher.qml must extend a contract base")

if problems:
    print("    FAIL:")
    for p in problems:
        print("      !", p)
    sys.exit(1)
print("    PASS — three registry widgets on the contract with migrated behaviours")
PY
static_rc=$?

echo
echo "[B] runtime contract widgets ..."
mkdir -p "$HOME_DIR"
cd "$REPO" || exit 1
HOME="$HOME_DIR" timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &

summary_ok=false
for _ in $(seq 1 $((RUN_SECS * 10))); do
    grep -q "SMOKE SUMMARY" "$LOG" 2>/dev/null && { summary_ok=true; break; }
    sleep 0.1
done
if [[ "$summary_ok" != true ]]; then
    echo "    ERROR: no SMOKE SUMMARY within ${RUN_SECS}s"
    tail -n 25 "$LOG" 2>/dev/null
    runtime_rc=1
    resolve_rc=1
else
    runtime_rc=0
    resolve_rc=0
fi

python3 - "$LOG" <<'PY'
import sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()

def tokens(ln):
    i = ln.find("SMOKE ")
    return ln[i + 6:].split() if i != -1 else []

need = ["Workspaces.qml", "Tray.qml", "Launcher.qml"]
passed = set()
failed = []
for ln in lines:
    t = tokens(ln)
    if not t or len(t) <= 2:
        continue
    if t[0] == "PASS":
        passed.add(t[2])
    elif t[0] == "FAIL":
        failed.append((t[2], " ".join(t[3:])))
rc = 0
for name in need:
    if name in passed:
        print(f"      pass {name}")
    else:
        detail = next((d for n, d in failed if n == name), "no PASS line")
        print(f"      FAIL {name}: {detail}")
        rc = 1
sys.exit(rc)
PY
runtime_rc=$(( runtime_rc != 0 ? 1 : $? ))

echo
echo "[C] ticket-15 CONTRACT probes ..."
python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()

def line(key):
    for ln in lines:
        if f"SMOKE CONTRACT {key} " in ln:
            return ln.split(f"SMOKE CONTRACT {key} ", 1)[1].strip()
    return None

rc = 0
def check(label, ok, detail):
    global rc
    print(f"      {'pass' if ok else 'FAIL'} {label}: {detail}")
    if not ok:
        rc = 1

ws = line("workspaces-widget")
check("workspaces-dim", ws and "emptyColor=foregroundMuted" in ws and "occupiedColor=foreground" in ws,
      ws or "no workspaces-widget CONTRACT line")
check("workspaces-own-clicks", ws and "contentHandlesClicks=true" in ws,
      ws or "missing contentHandlesClicks report")

tr = line("tray-widget")
check("tray-three-buttons", tr and "acceptedButtons=left|right|middle" in tr,
      tr or "no tray-widget CONTRACT line")
check("tray-menu-anchor", tr and "menuAnchor=QsMenuAnchor" in tr,
      tr or "missing menu anchor report")

lo = line("launcher-widget")
check("launcher-command", lo and "command=nosarch-launcher" in lo,
      lo or "no launcher-widget CONTRACT line")

sys.exit(rc)
PY
resolve_rc=$?

echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $runtime_rc -eq 0 && $resolve_rc -eq 0 ]]; then
    echo " RESULT: PASS (static + runtime + contract probes)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  (static=$([[ $static_rc -eq 0 ]] && echo ok || echo FAIL), runtime=$([[ $runtime_rc -eq 0 ]] && echo ok || echo FAIL), resolution=$([[ $resolve_rc -eq 0 ]] && echo ok || echo FAIL))"
    tail -n 30 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi
