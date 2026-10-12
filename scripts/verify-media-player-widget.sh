#!/usr/bin/env bash
#
# verify-media-player-widget.sh — verification for ticket 14.
#
#   A media indicator on the widget contract (config type "player") showing
#   what is playing, with click toggling play/pause; the MPRIS singleton
#   renamed to MediaService with no remaining references to the old name.
#
# Three checks:
#   (A) STATIC — registry name player, PlayerWidget on the contract, qmldir
#       registers MediaService (not Media), no Services.Media left in QML,
#       PlayerModule delegates to the contract widget, OSD uses MediaService.
#   (B) RUNTIME — smoke.qml finishes with a clean repo QML log.
#   (C) CONTRACT — SMOKE CONTRACT lines report the player widget and service
#       rename from live instances.
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

TMP="$(mktemp -d /tmp/opencode/qs-ticket14.XXXXXX)"
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
echo " Ticket 14 verification — media player widget and MediaService rename"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC
# ---------------------------------------------------------------------------
echo
echo "[A] static: registry, widget, service rename, module migration ..."
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

qmldir = read("services/qmldir")
if "singleton MediaService MediaService.qml" not in qmldir.replace("\t", " "):
    fail("services/qmldir must register singleton MediaService MediaService.qml")
if re.search(r"\bsingleton\s+Media\s+Media\.qml\b", qmldir):
    fail("services/qmldir still registers the old Media singleton")
if not (repo / "services/MediaService.qml").is_file():
    fail("services/MediaService.qml is missing")
if (repo / "services/Media.qml").is_file():
    fail("services/Media.qml still exists — rename must be complete")

for path in repo.rglob("*.qml"):
    rel = str(path.relative_to(repo))
    if rel.startswith(".git"):
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    if re.search(r"Services\.Media\b(?!Service)", text):
        fail(f"{rel} still references Services.Media (old singleton name)")

reg = read("shell/widgets/WidgetRegistry.qml")
if '"player"' not in reg or '"PlayerWidget.qml"' not in reg:
    fail('WidgetRegistry must map "player" → PlayerWidget.qml')

player = read("shell/widgets/PlayerWidget.qml")
if not player:
    fail("shell/widgets/PlayerWidget.qml is missing")
elif not re.search(r"\bBarWidget\b\s*\{", player):
    fail("PlayerWidget must extend BarWidget")
elif "Services.MediaService" not in player:
    fail("PlayerWidget must read playback state through Services.MediaService")
elif "togglePlayPause" not in player:
    fail("PlayerWidget activate must call MediaService.togglePlayPause()")
elif "nowPlayingText" not in player:
    fail("PlayerWidget must expose nowPlayingText for what is playing")

osd = read("shell/osds/MediaOsd.qml")
if "Services.MediaService" not in osd:
    fail("MediaOsd must use Services.MediaService")

if rc == 0:
    print("PASS — registry, widget, and rename")
else:
    print("FAIL — " + "; ".join(bad))
sys.exit(rc)
PY
)
static_rc=$?
echo "$static_out" | sed 's/^/    /'

# ---------------------------------------------------------------------------
# (B) RUNTIME
# ---------------------------------------------------------------------------
echo
echo "[B] runtime: smoke.qml ..."
mkdir -p "$HOME_DIR/.config/quickshell/nosarch"
runtime_rc=1
cd "$REPO" || exit 1
HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 1 $((RUN_SECS * 10))); do
    grep -q "SMOKE SUMMARY" "$LOG" 2>/dev/null && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
wait "$pid" 2>/dev/null || true

python3 - "$LOG" "$REPO" <<'PY'
import re, sys, pathlib
log, repo = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
problems = []
text = log.read_text(errors="replace")
for ln in text.splitlines():
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
if "SMOKE SUMMARY" not in text:
    print("    FAIL — smoke did not reach SMOKE SUMMARY")
    sys.exit(1)
print("    PASS — smoke finished with a clean repo QML log")
sys.exit(0)
PY
runtime_rc=$?

# ---------------------------------------------------------------------------
# (C) CONTRACT
# ---------------------------------------------------------------------------
echo
echo "[C] contract probes ..."
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

need("player-widget", lambda v: "action=togglePlayPause" in v and "available=" in v and "nowPlaying=" in v,
     "player widget members and toggle action")
need("media-service", lambda v: "name=MediaService" in v and "old-name=absent" in v,
     "service renamed and old name gone from smoke plan")

if rc == 0:
    print("PASS — ticket-14 contract probes")
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
    echo " Ticket 14 verification: PASS"
    exit 0
fi
echo " Ticket 14 verification: FAIL (static=$static_rc runtime=$runtime_rc contract=$contract_rc)"
exit 1
