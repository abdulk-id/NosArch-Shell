#!/usr/bin/env bash
#
# verify-launch-reload.sh — verification for ticket 02.
#
#   "The shell launches from an explicit path, saves reload it fast, the log
#    states plainly fresh-vs-reloaded, and every overlay surface sets a layer
#    and a namespace."
#
# Two checks:
#   (A) STATIC  — every layer-shell surface declares BOTH a WlrLayershell.layer
#       and a WlrLayershell.namespace. Framework PopupWindows and plain Items are
#       not layer-shell surfaces and are correctly excluded.
#   (B) RUNTIME — the real shell is launched by explicit path, the log shows a
#       clear STARTED FRESH line, a file edit triggers a reload that logs a clear
#       RELOADED line, and the end-to-end edit-loop time is measured.
#
# SAFETY (the live desktop is running): the shell is started under
# `dbus-run-session`, so its NotificationServer / tray / MPRIS clients talk to a
# throwaway private bus and cannot disturb the swaync / swayosd / waybar that own
# the real one. Layer-shell surfaces are wayland-only, so they DO flash on screen
# briefly; the run is short and the process is always killed on exit. Nothing is
# written to ~/.config or any installed location. HOME is redirected to a
# scratch directory because the file-backed palette (ticket 04) writes
# ~/.local/share/nosarch/current-theme/palette.json on first run — the path
# is resolved from HOME, so the write lands in the scratch home and the live
# theme directory is never touched.
#
# Exit status: 0 only if both checks pass.
#
set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

RUN_SECS="${RUN_SECS:-18}"
TMP="$(mktemp -d /tmp/opencode/qs-verify.XXXXXX)"
LOG="$TMP/run.log"
WRITE_TS="$TMP/write.ts"

static_rc=1
runtime_rc=1

cleanup() {
    # Kill only THIS test's shell (its cmdline carries the unique temp path).
    pkill -f "quickshell.*${TMP}/shell.qml" 2>/dev/null || true
    pkill -f "quickshell -p ${TMP}/shell.qml" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 02 verification — launch / reload / fresh-vs-reload logging"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC: layer + namespace on every overlay surface
# ---------------------------------------------------------------------------
echo
echo "[A] static layer/namespace convention ..."
python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
pat_surface = re.compile(r'\bPanelWindow\b\s*\{')
# Only an ASSIGNMENT counts. The convention is that a surface SETS a layer and
# a namespace; reading `someWindow.WlrLayershell.namespace` back off a live
# window is not setting one. Counting reads made this check fail on
# shell/bar/Bar.qml, which reads each bar window's namespace to report it
# (ticket 10) — that is the check measuring the wrong thing, not the bar being
# wrong.
pat_layer   = re.compile(r'\bWlrLayershell\.layer\s*:')
pat_ns      = re.compile(r'\bWlrLayershell\.namespace\s*:')
skip_dirs   = {'.git', '.scratch', '.agents', '.zed'}
problems, seen = [], []
for f in sorted(repo.rglob('*.qml')):
    if skip_dirs & set(p.name for p in f.parents):
        continue
    text = f.read_text(encoding='utf-8', errors='replace')
    nsurf  = len(pat_surface.findall(text))
    nlayer = len(pat_layer.findall(text))
    nns    = len(pat_ns.findall(text))
    if nsurf:
        seen.append(str(f.relative_to(repo)))
        if not (nsurf == nlayer == nns):
            problems.append(f"{f.relative_to(repo)}: {nsurf} PanelWindow(s) but "
                            f"{nlayer} layer / {nns} namespace")
print("    overlay surfaces checked:")
for s in seen:
    print("      -", s)
if problems:
    print("    FAIL — surface(s) missing layer and/or namespace:")
    for p in problems:
        print("      !", p)
    sys.exit(1)
print("    PASS — every PanelWindow sets both a layer and a namespace")
PY
static_rc=$?

# ---------------------------------------------------------------------------
# (B) RUNTIME: launch by path, read log, force a reload, measure it
# ---------------------------------------------------------------------------
echo
echo "[B] runtime launch + reload (isolated bus, up to ${RUN_SECS}s) ..."

# Copy the runnable config to a private temp dir: unique config path => its own
# quickshell instance, and a safe file to edit for the reload trigger.
cp "$REPO/shell.qml" "$TMP/"
cp -r "$REPO/shell"     "$TMP/shell"
cp -r "$REPO/services"  "$TMP/services"
cp -r "$REPO/components" "$TMP/components"

# HOME is pointed at a scratch dir: the palette resolves its file from HOME
# and writes it on first run, so this keeps the live theme directory out of
# the run (see the SAFETY note above).
mkdir -p "$TMP/home"
HOME="$TMP/home" timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$TMP/shell.qml" >"$LOG" 2>&1 &
runtime_rc=0

# Wait for the explicit fresh-start line.
fresh_ok=false
for _ in $(seq 1 200); do grep -q "STARTED FRESH" "$LOG" 2>/dev/null && { fresh_ok=true; break; }; sleep 0.05; done
if [[ "$fresh_ok" != true ]]; then
    echo "    ERROR: no STARTED FRESH line within timeout"; runtime_rc=1
fi

# Force a real reload with a CONTENT change (mtime alone does not reload quickshell).
date +'%Y-%m-%d %H:%M:%S.%3N' > "$WRITE_TS"
printf '\n// verify-launch-reload trigger\n' >> "$TMP/shell.qml"

# Wait for the explicit reloaded line.
reload_ok=false
for _ in $(seq 1 200); do grep -q "RELOADED" "$LOG" 2>/dev/null && { reload_ok=true; break; }; sleep 0.05; done
if [[ "$reload_ok" != true ]]; then
    echo "    ERROR: no RELOADED line after the file edit within timeout"; runtime_rc=1
fi

# ---------------------------------------------------------------------------
echo
echo "[B] log analysis ..."
python3 - "$LOG" "$WRITE_TS" <<'PY'
import re, sys, datetime, pathlib
logp, writep = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
lines = logp.read_text(errors='replace').splitlines()

ts_re = re.compile(r'^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3})')
def to_ms(s):
    return datetime.datetime.strptime(s, "%Y-%m-%d %H:%M:%S.%f").timestamp() * 1000.0

def stamps(keyword):
    out = []
    for ln in lines:
        m = ts_re.match(ln)
        if m and keyword in ln:
            out.append(to_ms(m.group(1)))
    return out

loaded   = stamps("Configuration Loaded")     # 1st = fresh, 2nd = after reload
reloading= stamps("Reloading configuration...")
fresh    = [ln for ln in lines if "STARTED FRESH" in ln]
reload   = [ln for ln in lines if "RELOADED"   in ln]

print("    STARTED FRESH line:", fresh[0].split("INFO",1)[-1].strip() if fresh else "<MISSING>")
print("    RELOADED line     :", reload[0].split("INFO",1)[-1].strip() if reload else "<MISSING>")

if not fresh or not reload or len(loaded) < 2:
    print("    FAIL — expected both a fresh line and a reloaded line with a reload")
    sys.exit(1)

write_ms = to_ms(writep.read_text().strip())
n = min(len(reloading), len(loaded) - 1)
if n >= 1:
    reload_internal = loaded[n] - reloading[n-1]      # quickshell's own reload compute
    write_to_reload = loaded[n] - write_ms            # end-to-end: save -> new config live
    write_to_line   = (to_ms(ts_re.match(reload[0]).group(1)) - write_ms)
    print(f"    reload compute (Reloading -> Configuration Loaded): {reload_internal:.0f} ms")
    print(f"    end-to-end edit loop (save -> Configuration Loaded): {write_to_reload:.0f} ms")
    print(f"    save -> RELOADED log line: {write_to_line:.0f} ms")
    if write_to_reload > 1000:
        print("    NOTE: measured edit loop exceeded 1s (loaded machine?); reported, not failed")
print("    PASS — fresh and reloaded are both plainly stated and distinguishable")
sys.exit(0)
PY
analysis_rc=$?
[[ $analysis_rc -ne 0 ]] && runtime_rc=1

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $runtime_rc -eq 0 ]]; then
    echo " RESULT: PASS (static + runtime)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  (static=$([[ $static_rc -eq 0 ]] && echo ok || echo FAIL), runtime=$([[ $runtime_rc -eq 0 ]] && echo ok || echo FAIL))"
    echo " --- captured log tail (if any) ---"
    tail -n 40 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi
