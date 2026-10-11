#!/usr/bin/env bash
#
# verify-palette.sh — verification for ticket 04.
#
#   "The shell reads its colours from a palette file in the existing NosArch
#    theme directory and falls back to a known-good default palette when none
#    exists; on first run it writes the defaults out; it never overwrites an
#    existing file; a malformed file is left completely alone."
#
# Six cases, one per user-visible promise, each exercised against a REAL
# filesystem by launching the smoke entrypoint (the shell's single
# instantiation seam) with HOME pointed at a throwaway scratch directory.
# The palette path is resolved from HOME, so the resolved theme directory
# lands under the scratch home — the live ~/.local/share/nosarch/ is never
# touched:
#
#   1. no palette file          → the shell renders with the built-in defaults.
#   2. no palette file, 1st run → the defaults are written out, so there is
#                                 something to edit afterwards.
#   3. palette file present     → the shell uses it.
#   4. palette file present     → it is NOT overwritten (byte-for-byte).
#   5. palette file malformed   → defaults are used AND the file is left
#                                 byte-for-byte unchanged.
#   6. palette file is a subset → keys the file does not mention keep their
#                                 defaults (never undefined / black).
#
# HOW THE CASES ARE OBSERVED
#
# The palette logs two lines per run — a verdict and the effective values:
#   "nosarch-shell ▸ PALETTE verdict source=<file|default> file=<path> \
#    keys-from-file=<n>/8 [note=<tag>]"
#   "nosarch-shell ▸ PALETTE values background=<c> backgroundSurface=<c> ..."
# Every case greps those lines out of the smoke log and compares them against
# an independent expectation (the default literals below, or the file content
# the case wrote). Nothing here inspects the shell's internals — the file on
# disk and the log lines are the whole interface.
#
# SAFETY (the live desktop is running): every launch runs under
# `dbus-run-session` (throwaway bus — the shell's NotificationServer cannot
# disturb swaync) with HOME redirected to a scratch dir, and is bounded by a
# timeout. The live theme directory is never read or written: the palette
# path is derived from HOME, which this script always points at scratch.
#
# Exit status: 0 only if all six cases pass.

set -uo pipefail   # deliberately not -e: run every case, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"

# Fast smoke timing: the palette does not need live hardware, only the shell's
# own load path. The smoke shell waits out these (capped) periods before
# instantiating widgets, so small values keep each case to a few seconds.
export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-500}"

TMP="$(mktemp -d /tmp/opencode/qs-palette.XXXXXX)"
LOG="$TMP/smoke.log"

PASS=0
FAIL=0
FAILED_CASES=()

cleanup() {
    # The smoke shell quits itself and `timeout` kills its whole process
    # group on expiry, so nothing is left to clean; this is a belt-and-braces
    # reaping of this script's own temp dir only.
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 04 verification — file-backed palette (six filesystem promises)"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# run_smoke <scratch-home> — launch the smoke shell with HOME pointed at the
# scratch dir, wait for it to finish, leave the log at $LOG.
run_smoke() {
    local home="$1"
    local pid
    cd "$REPO" || return 1
    HOME="$home" timeout "$RUN_SECS" dbus-run-session -- \
        quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &
    pid=$!
    # The smoke shell quits itself; the timeout is the backstop. Poll for the
    # process instead of a fixed sleep so a fast machine does not pay for it.
    local i
    for i in $(seq 1 $((RUN_SECS * 10))); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    # Still alive means it hung: TERM `timeout`, which kills the whole
    # process group (dbus-run-session and the quickshell under it).
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null
    return 0
}

# new_home <case-name> — a fresh scratch HOME per case so no case can see
# another case's palette file (a seen file would make "first run" meaningless).
new_home() {
    local home="$TMP/$1"
    rm -rf "$home"
    mkdir -p "$home"
    echo "$home"
}

# prepare_theme <home> — the theme directory as a real machine has it: the
# directory exists (NosArch created it for wallpapers) with no palette file.
prepare_theme() {
    mkdir -p "$1/.local/share/nosarch/current-theme"
}

# check <case-name> — run the case's python checker against $LOG. It prints
# exactly one line: "PASS <case>: detail" or "FAIL <case>: detail".
check() {
    local name="$1"
    python3 - "$LOG" "$name" <<'PY'
import json, sys, pathlib

logp, name = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = logp.read_text(errors='replace').splitlines()

DEFAULTS = {
    "background":          "#1D1D20",
    "backgroundSurface":   "#2E2E32",
    "backgroundHover":     "#434346",
    "foreground":          "#FFFFFF",
    "foregroundSecondary": "#9A9A9C",
    "foregroundMuted":     "#444B6A",
    "alertRed":            "#FF6666",
    "accent":              "#6799e4",
}
KEYS = list(DEFAULTS)

# Distinctive values a prepared palette file carries. They differ from every
# default, so "the shell used the file" is proven by the values alone.
FILED = {
    "background":          "#101010",
    "backgroundSurface":   "#202020",
    "backgroundHover":     "#303030",
    "foreground":          "#F0F0F0",
    "foregroundSecondary": "#A0A0A0",
    "foregroundMuted":     "#505050",
    "alertRed":            "#FF0000",
    "accent":              "#00FF00",
}

def palette_line(kind):
    for ln in lines:
        if f"PALETTE {kind} " in ln:
            return ln.split(f"PALETTE {kind} ", 1)[1].strip()
    return None

def values_dict():
    """Parse the 'PALETTE values' line into {key: colour} (lowercased)."""
    ln = palette_line("values")
    if ln is None:
        return None
    out = {}
    for tok in ln.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            out[k.lower()] = v.lower()
    return out

def compare_values(label, actual, expected):
    """expected: {key: lower-case colour}. The independent expectation."""
    if actual is None:
        return f"FAIL {label}: no 'PALETTE values' line in the log"
    problems = []
    for k, v in expected.items():
        got = actual.get(k.lower())
        if got is None:
            problems.append(f"{k} missing from the values line")
        elif got != v:
            problems.append(f"{k}={got} (expected {v})")
    if problems:
        return f"FAIL {label}: " + "; ".join(problems)
    shown = " ".join(f"{k}={actual[k.lower()]}" for k in KEYS)
    return f"PASS {label}: effective palette is exactly as expected ({shown})"

results = []

if name == "case1-no-file-defaults":
    v = palette_line("verdict")
    if v is None:
        results.append("FAIL case1: no 'PALETTE verdict' line in the log")
    elif "source=default" not in v:
        results.append(f"FAIL case1: expected source=default, verdict was: {v}")
    elif "keys-from-file=0/8" not in v:
        results.append(f"FAIL case1: expected keys-from-file=0/8, verdict was: {v}")
    else:
        results.append(compare_values("case1", values_dict(),
                                       {k: DEFAULTS[k].lower() for k in KEYS}))

elif name == "case2-first-run-writes":
    v = palette_line("verdict")
    if v is None:
        results.append("FAIL case2: no 'PALETTE verdict' line in the log")
    elif "source=default" not in v or "note=no-file-wrote-defaults" not in v:
        results.append(f"FAIL case2: expected source=default + first-run note, verdict was: {v}")
    else:
        results.append("PASS case2: verdict shows the defaults were written out on first run")

elif name == "case3-existing-file-used":
    v = palette_line("verdict")
    if v is None:
        results.append("FAIL case3: no 'PALETTE verdict' line in the log")
    elif "source=file" not in v:
        results.append(f"FAIL case3: expected source=file, verdict was: {v}")
    elif "keys-from-file=8/8" not in v:
        results.append(f"FAIL case3: expected keys-from-file=8/8, verdict was: {v}")
    else:
        results.append(compare_values("case3", values_dict(),
                                       {k: FILED[k].lower() for k in KEYS}))

elif name == "case4-never-overwrites":
    # bash already compared checksums; here we prove the run really READ the
    # file (otherwise "unchanged" would be vacuously true).
    v = palette_line("verdict")
    if v is None:
        results.append("FAIL case4: no 'PALETTE verdict' line in the log")
    elif "source=file" not in v or "keys-from-file=8/8" not in v:
        results.append(f"FAIL case4: the run did not read the existing file (verdict: {v})")
    else:
        results.append("PASS case4: the file was read (source=file) and the bytes are unchanged")

elif name == "case5-malformed-untouched":
    v = palette_line("verdict")
    if v is None:
        results.append("FAIL case5: no 'PALETTE verdict' line in the log")
    elif "source=default" not in v or "note=malformed-left-untouched" not in v:
        results.append(f"FAIL case5: expected defaults + malformed note, verdict was: {v}")
    else:
        results.append(compare_values("case5", values_dict(),
                                       {k: DEFAULTS[k].lower() for k in KEYS}))

elif name == "case6-subset-keeps-defaults":
    v = palette_line("verdict")
    if v is None:
        results.append("FAIL case6: no 'PALETTE verdict' line in the log")
    elif "source=file" not in v or "keys-from-file=2/8" not in v:
        results.append(f"FAIL case6: expected source=file with 2/8 keys from file, verdict was: {v}")
    else:
        expected = {k: DEFAULTS[k].lower() for k in KEYS}
        expected["accent"] = "#00ff00"
        expected["alertRed"] = "#ff0000"
        results.append(compare_values("case6", values_dict(), expected))

else:
    results.append(f"FAIL {name}: no checker wired for this case")

for r in results:
    print(r)
sys.exit(1 if results and results[0].startswith("FAIL") else 0)
PY
}

record() {  # record <case-name> <checker-output>
    local name="$1" out="$2"
    echo "$out" | sed 's/^/    /'
    if [[ "$out" == PASS* ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("$name")
    fi
}

# ---------------------------------------------------------------------------
# case 1 — no palette file → the shell renders with the built-in defaults
# ---------------------------------------------------------------------------
echo
echo "[1] no palette file → renders with the known-good defaults ..."
home="$(new_home case1)"
prepare_theme "$home"
run_smoke "$home"
record "case1" "$(check case1-no-file-defaults)"

# ---------------------------------------------------------------------------
# case 2 — first run with no palette file → the defaults get written out
# ---------------------------------------------------------------------------
echo
echo "[2] first run with no palette file → defaults are written out ..."
home="$(new_home case2)"
prepare_theme "$home"
run_smoke "$home"
written="$home/.local/share/nosarch/current-theme/palette.json"
out="$(check case2-first-run-writes)"
if [[ "$out" == FAIL* ]]; then
    record "case2" "$out"
else
    # The file itself must now exist and carry every default, so there is
    # something to edit afterwards.
    out2="$(python3 - "$written" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
DEFAULTS = {
    "background": "#1D1D20", "backgroundSurface": "#2E2E32",
    "backgroundHover": "#434346", "foreground": "#FFFFFF",
    "foregroundSecondary": "#9A9A9C", "foregroundMuted": "#444B6A",
    "alertRed": "#FF6666", "accent": "#6799e4",
}
if not p.is_file():
    print(f"FAIL case2: no palette file was written to {p}")
else:
    try:
        data = json.loads(p.read_text())
    except Exception as e:
        print(f"FAIL case2: written file is not valid JSON: {e}")
    else:
        problems = [f"{k}: {data.get(k)!r} != {v!r}" for k, v in DEFAULTS.items()
                    if str(data.get(k, "")).lower() != v.lower()]
        extra = sorted(str(k) for k in set(data) - set(DEFAULTS))
        if extra:
            problems.append(f"unexpected keys: {extra}")
        if problems:
            print("FAIL case2: written palette is wrong — " + "; ".join(problems))
        else:
            print(f"PASS case2: {p.name} exists and carries all 8 defaults, ready to edit")
PY
)"
    record "case2" "$out2"
fi

# ---------------------------------------------------------------------------
# case 3 — an existing palette file → the shell uses it
# ---------------------------------------------------------------------------
echo
echo "[3] existing palette file → the shell uses it ..."
home="$(new_home case3)"
prepare_theme "$home"
python3 - "$home" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]) / ".local/share/nosarch/current-theme/palette.json"
vals = {
    "background": "#101010", "backgroundSurface": "#202020",
    "backgroundHover": "#303030", "foreground": "#F0F0F0",
    "foregroundSecondary": "#A0A0A0", "foregroundMuted": "#505050",
    "alertRed": "#FF0000", "accent": "#00FF00",
}
p.write_text(json.dumps(vals, indent=2) + "\n")
PY
run_smoke "$home"
record "case3" "$(check case3-existing-file-used)"

# ---------------------------------------------------------------------------
# case 4 — an existing palette file → it is NOT overwritten
# ---------------------------------------------------------------------------
echo
echo "[4] existing palette file → never overwritten (byte-for-byte) ..."
home="$(new_home case4)"
prepare_theme "$home"
palette="$home/.local/share/nosarch/current-theme/palette.json"
printf '{\n  "accent": "#00FF00",\n  "alertRed": "#FF0000",\n  "background": "#101010",\n  "backgroundHover": "#303030",\n  "backgroundSurface": "#202020",\n  "foreground": "#F0F0F0",\n  "foregroundMuted": "#505050",\n  "foregroundSecondary": "#A0A0A0"\n}\n' > "$palette"
before="$(sha256sum "$palette" | cut -d' ' -f1)"
run_smoke "$home"
after="$(sha256sum "$palette" | cut -d' ' -f1)"
out="$(check case4-never-overwrites)"
if [[ "$out" == FAIL* ]]; then
    record "case4" "$out"
elif [[ "$before" != "$after" ]]; then
    record "case4" "FAIL case4: the palette file changed on disk (sha256 $before → $after)"
else
    record "case4" "PASS case4: file read and byte-for-byte unchanged (sha256 $after)"
fi

# ---------------------------------------------------------------------------
# case 5 — a malformed palette file → defaults, and the file is left alone
# ---------------------------------------------------------------------------
echo
echo "[5] malformed palette file → defaults + file left untouched ..."
home="$(new_home case5)"
prepare_theme "$home"
palette="$home/.local/share/nosarch/current-theme/palette.json"
printf 'this is definitely not json {{{\n' > "$palette"
before="$(sha256sum "$palette" | cut -d' ' -f1)"
run_smoke "$home"
after="$(sha256sum "$palette" | cut -d' ' -f1)"
out="$(check case5-malformed-untouched)"
if [[ "$out" == FAIL* ]]; then
    record "case5" "$out"
elif [[ "$before" != "$after" ]]; then
    record "case5" "FAIL case5: the malformed file was modified (sha256 $before → $after)"
else
    record "case5" "PASS case5: defaults used and the malformed file is byte-for-byte unchanged (sha256 $after)"
fi

# ---------------------------------------------------------------------------
# case 6 — a subset palette file → unmentioned keys keep their defaults
# ---------------------------------------------------------------------------
echo
echo "[6] subset palette file → unspecified keys keep their defaults ..."
home="$(new_home case6)"
prepare_theme "$home"
printf '{\n  "accent": "#00FF00",\n  "alertRed": "#FF0000"\n}\n' \
    > "$home/.local/share/nosarch/current-theme/palette.json"
run_smoke "$home"
record "case6" "$(check case6-subset-keeps-defaults)"

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $FAIL -eq 0 ]]; then
    echo " RESULT: PASS (all six palette promises hold)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  ($PASS passed, $FAIL failed: ${FAILED_CASES[*]})"
    echo " --- captured log tail (if any) ---"
    tail -n 40 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi
