#!/usr/bin/env bash
#
# verify-network-widget-and-panel.sh — verification for ticket 12.
#
#   Network indicator and panel on the overlay architecture (ticket 11), with
#   presentation moved out of NetworkService (ADR 0001). Panel switching
#   between volume and network is exercised with two real panel-bearing widgets
#   on one coordinator.
#
# Exit status: 0 only if every check holds.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-45}"

export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-8000}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-2000}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-1500}"

TMP="$(mktemp -d /tmp/opencode/qs-ticket12.XXXXXX)"
LOG="$TMP/smoke.log"
HOME_DIR="$TMP/home"

PASS=0
FAIL=0
FAILED_CASES=()

cleanup() {
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); echo "    PASS $1: $2"; }
fail() {
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$1")
    echo "    FAIL $1: $2"
}

echo "======================================================================"
echo " Ticket 12 verification — network widget, panel, and service boundary"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC
# ---------------------------------------------------------------------------
echo
echo "[A] static: registry, widget on contract, no service glyphs ..."
static_rc=1
static_out=$(python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
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
if '"network"' not in reg or "NetworkWidget.qml" not in reg:
    fail('WidgetRegistry must map "network" → NetworkWidget.qml')

nw = read("shell/widgets/NetworkWidget.qml")
if not nw:
    fail("shell/widgets/NetworkWidget.qml is missing")
elif not re.search(r"\bBarWidget\b\s*\{", nw):
    fail("NetworkWidget must extend BarWidget")
elif "panelContent" not in nw or re.search(r"panelContent\s*:\s*null", nw):
    fail("NetworkWidget must declare panelContent")
elif "togglePanel" not in nw and "togglePanel(" not in nw:
    fail("NetworkWidget must open its panel through togglePanel")
elif "Services.NetworkService" not in nw:
    fail("NetworkWidget must read network state through Services.NetworkService")

if "NetworkWidget" not in read("shell/widgets/qmldir"):
    fail("shell/widgets/qmldir must register NetworkWidget")

if not (repo / "components/NetworkIcon.qml").is_file():
    fail("components/NetworkIcon.qml is missing — presentation lives outside the service")
if "NetworkIcon" not in read("components/qmldir"):
    fail("components/qmldir must register NetworkIcon")

ns = read("services/NetworkService.qml")
if re.search(r"\bproperty\s+\w+\s+textIcon\b", ns):
    fail("NetworkService still declares textIcon (ADR 0001)")
if re.search(r"\bwifiIcons\b", ns):
    fail("NetworkService still carries wifiIcons — that is presentation")
if re.search(r"\b(rxSpeedText|txSpeedText|totalReceivedText|totalSentText)\b", ns):
    fail("NetworkService still publishes formatted throughput strings")

# Panel lists and throughput must be visible in the widget file.
for needle in ("signal", "rxSpeed", "txSpeed", "ListView", "ListModel"):
    if needle not in nw:
        fail(f"NetworkWidget panel must expose {needle} for connections or throughput")

if rc == 0:
    print("PASS — registry, contract widget, and service boundary")
else:
    print("FAIL — " + "; ".join(bad))
sys.exit(rc)
PY
)
echo "    $static_out"
[[ "$static_out" == PASS* ]] && static_rc=0 && pass "static" "${static_out#PASS — }" || fail "static" "${static_out#FAIL — }"

# ---------------------------------------------------------------------------
# (B) RUNTIME — smoke.qml
# ---------------------------------------------------------------------------
echo
echo "[B] runtime: smoke shell ..."
mkdir -p "$HOME_DIR/.config"
runtime_rc=1
cd "$REPO" || exit 1
HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    timeout "$RUN_SECS" dbus-run-session -- \
    quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &
smoke_pid=$!
for _ in $(seq 1 $((RUN_SECS * 10))); do
    kill -0 "$smoke_pid" 2>/dev/null || break
    grep -q "SMOKE SUMMARY" "$LOG" 2>/dev/null && break
    sleep 0.1
done
kill "$smoke_pid" 2>/dev/null || true
wait "$smoke_pid" 2>/dev/null

if grep -q "SMOKE SUMMARY planned=.* failed=0" "$LOG"; then
    runtime_rc=0
    pass "smoke-instantiation" "every planned item instantiated with no failures"
else
    summary="$(grep "SMOKE SUMMARY" "$LOG" | tail -1)"
    fail "smoke-instantiation" "smoke did not finish clean: ${summary:-no summary}"
fi

warns=$(grep -E "^[0-9]{4}-.* (WARN|ERROR) " "$LOG" | grep -E "@(smoke\.qml|services/|shell/widgets/NetworkWidget|components/NetworkIcon)" || true)
if [[ -z "$warns" ]]; then
    pass "smoke-log" "no WARN/ERROR against ticket 12 files"
else
    fail "smoke-log" "log named ticket files: $(echo "$warns" | head -3)"
fi

# ---------------------------------------------------------------------------
# (C) CONTRACT — live probes
# ---------------------------------------------------------------------------
echo
echo "[C] contract: network widget, service readout, panel switching ..."

check_contract() {
    local probe="$1"
    shift
    local line
    line="$(grep "SMOKE CONTRACT ${probe} " "$LOG" | tail -1)"
    if [[ -z "$line" ]]; then
        fail "$probe" "no SMOKE CONTRACT line — probe did not run"
        return
    fi
    local kv bad="" key expected actual
    kv="$(sed 's/^.*SMOKE CONTRACT [^ ]* //' <<<"$line")"
    for want in "$@"; do
        key="${want%%=*}"
        expected="${want#*=}"
        actual=""
        for tok in $kv; do
            [[ "$tok" == "$key="* ]] && actual="${tok#*=}"
        done
        actual="${actual%\"}"
        if [[ "$actual" != "$expected" ]]; then
            bad="${bad}${key}='${actual}' (wanted ${expected}); "
        fi
    done
    if [[ -z "$bad" ]]; then
        pass "$probe" "claims held (${#} checks)"
    else
        fail "$probe" "$bad"
    fi
}

check_contract network-widget \
    hasPanel=true panelContent=SUPPLIED coordinator-handed-over=true \
    portal-distinct-from-connected=true no-hardware-graceful=true \
    panel-lists-networks=true panel-shows-throughput=true

check_contract network-panel-toggle widget-opens=true widget-toggles-closed=true

check_contract volume-network-panel-switch \
    volume-to-network-one-click=true network-to-volume-one-click=true \
    one-panel-at-a-time=true

net_line="$(grep "SMOKE CONTRACT network-widget " "$LOG" | tail -1)"
portal_g="$(sed -n 's/.*portal="\([^"]*\)".*/\1/p' <<<"$net_line")"
full_g="$(sed -n 's/.*connected="\([^"]*\)".*/\1/p' <<<"$net_line")"
# Pre-rewrite portal glyph U+F59F (󰖟), wired U+F002 (󰀂) — literals independent of the shell.
portal_want=$(python3 -c 'print("\U000f059f")')
if [[ -n "$portal_g" && -n "$full_g" ]]; then
    if [[ "$portal_g" != "$portal_want" ]]; then
        fail "glyph-portal" "portal glyph is not U+F059F"
    else
        pass "glyph-portal" "captive portal uses the portal glyph (U+F059F)"
    fi
    if [[ "$portal_g" == "$full_g" ]]; then
        fail "glyph-portal-distinct" "portal and connected glyphs must differ"
    else
        pass "glyph-portal-distinct" "portal and full connectivity glyphs differ"
    fi
else
    fail "glyph-portal" "probe reported no portal/connected glyph values"
fi

if grep -qE 'property\s+\w+\s+textIcon' "$REPO/services/NetworkService.qml"; then
    fail "network-no-glyph-property" "NetworkService still declares a glyph property"
else
    pass "network-no-glyph-property" "NetworkService declares no glyph; NetworkIcon owns presentation"
fi

net_svc="$(grep "SMOKE PASS service NetworkService " "$LOG" | tail -1)"
if [[ -n "$net_svc" ]] && grep -q "via NetworkIcon" <<<"$net_svc"; then
    pass "network-service-readout" "smoke readout separates service state from widget presentation"
else
    fail "network-service-readout" "NetworkService readout must not embed a service glyph: ${net_svc:-missing}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $FAIL -eq 0 && $static_rc -eq 0 && $runtime_rc -eq 0 ]]; then
    echo " RESULT: PASS (network widget, panel, service boundary, volume↔network switch)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  ($PASS passed, $FAIL failed: ${FAILED_CASES[*]})"
    echo "======================================================================"
    exit 1
fi
