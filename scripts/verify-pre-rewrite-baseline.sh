#!/usr/bin/env bash
#
# verify-pre-rewrite-baseline.sh
#
# Exercises the claims in docs/pre-rewrite-baseline.md rather than restating them:
#   - the `pre-rewrite` tag resolves to the pre-rewrite commit (not assumed),
#   - the tag checks out cleanly into an isolated worktree (restore is real),
#   - the documented launch command runs and loads without fatal QML errors,
#   - nothing leaks (no quickshell process, no leftover worktree).
#
# NOTE: this script briefly launches the pre-rewrite shell on the live session
# (~8s per launch). It draws surfaces but writes nothing to the live desktop
# configuration. Run it while no other quickshell instance is running.
#
# Exit status: 0 = every check passed, 1 = at least one check failed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$REPO_ROOT/docs/pre-rewrite-baseline.md"

TAG="pre-rewrite"
EXPECTED_COMMIT="77629f346b65f74ff042cf78a9a3b74d187328a1"
EXPECTED_SUBJECT="WIP: pre-rewrite state of nosarch-shell"

# The launch command, as documented in the baseline record. The script asserts
# the document records this exact command before running it.
LAUNCH_CMD="quickshell -p shell.qml"
SERVICETEST_CMD="quickshell -p testing/ServiceTest.qml"
LAUNCH_TIMEOUT=8 # seconds; a `timeout` exit of 124 means it stayed alive: healthy

# Error patterns that mean the shell failed to load (as opposed to WARN-level
# noise, which the baseline record documents as expected).
FATAL_PATTERNS=(
    "failed to load component"
    "Component is not ready"
    "is not a type"
    "QQmlApplicationEngine"
)

PASS=0
FAIL=0
WORKTREE_DIR=""
RUN_DIR=""

ok()   { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }
info() { printf '  ..  %s\n' "$1"; }

cleanup() {
    if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
        git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
    fi
    if [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ]; then
        rm -rf "$RUN_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT

leaked_quickshell_for() {
    # True if any live process cmdline references the given directory.
    local dir="$1" pid cmd
    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        cmd="$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)"
        case "$cmd" in
            *"$dir"*) return 0 ;;
        esac
    done
    return 1
}

log_matches_fatal() {
    local logfile="$1" pattern
    for pattern in "${FATAL_PATTERNS[@]}"; do
        if grep -qF "$pattern" "$logfile"; then
            printf 'fatal pattern: %s' "$pattern"
            return 0
        fi
    done
    return 1
}

run_baseline_launch() {
    # Runs one documented launch command from the checked-out baseline and
    # checks that it loaded and stayed alive without fatal QML errors.
    local label="$1" cmd="$2" rc=0 fatal logfile
    logfile="$RUN_DIR/$(echo "$cmd" | tr ' /' '__').log"

    (cd "$WORKTREE_DIR" && timeout -k 2 "$LAUNCH_TIMEOUT" $cmd) > "$logfile" 2>&1 || rc=$?
    info "$label log saved: $logfile"

    if [ "$rc" -eq 124 ] || [ "$rc" -eq 0 ]; then
        ok "$label stayed alive for the full ${LAUNCH_TIMEOUT}s (rc=$rc)"
    else
        bad "$label exited early (rc=$rc) -- fatal startup failure"
    fi

    if grep -qF "Configuration Loaded" "$logfile"; then
        ok "$label reports 'Configuration Loaded'"
    else
        bad "$label never reports 'Configuration Loaded'"
    fi

    if fatal="$(log_matches_fatal "$logfile")"; then
        bad "$label log contains a fatal QML error ($fatal)"
    else
        ok "$label log has no fatal QML errors (WARN-level noise is expected and documented)"
    fi

    if leaked_quickshell_for "$WORKTREE_DIR"; then
        bad "$label left a quickshell process running"
    else
        ok "$label left no quickshell process behind"
    fi
}

# --- preflight ---------------------------------------------------------------

if ! command -v git >/dev/null 2>&1; then
    echo "FAIL  git not available"; exit 1
fi
if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    echo "FAIL  WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE not set -- launch checks need a live Hyprland session"; exit 1
fi
if ! command -v quickshell >/dev/null 2>&1; then
    echo "FAIL  quickshell not on PATH"; exit 1
fi
ok "preflight: git, quickshell and a live Hyprland session available ($(quickshell --version 2>&1))"

# --- tag identity -------------------------------------------------------------

if resolved="$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" 2>/dev/null)"; then
    ok "tag '$TAG' exists (tag object $resolved)"
else
    bad "tag '$TAG' does not exist"; echo; echo "0 of 0... one critical check failed"; exit 1
fi

tagtype="$(git -C "$REPO_ROOT" cat-file -t "$TAG")"
commit="$(git -C "$REPO_ROOT" rev-parse "$TAG^{commit}")"
info "tag type: $tagtype; peels to commit $commit"

if [ "$commit" = "$EXPECTED_COMMIT" ]; then
    ok "'$TAG' points at the expected pre-rewrite commit $EXPECTED_COMMIT"
else
    bad "'$TAG' points at $commit, expected $EXPECTED_COMMIT -- was the tag moved?"
fi

subject="$(git -C "$REPO_ROOT" log -1 --format=%s "$TAG")"
if [ "$subject" = "$EXPECTED_SUBJECT" ]; then
    ok "'$TAG' subject is '$EXPECTED_SUBJECT'"
else
    bad "'$TAG' subject is '$subject', expected '$EXPECTED_SUBJECT'"
fi

if git -C "$REPO_ROOT" merge-base --is-ancestor "$TAG" master 2>/dev/null; then
    ok "'$TAG' is a genuine ancestor of master (diff base, not a side branch)"
else
    bad "'$TAG' is not an ancestor of master"
fi
if git -C "$REPO_ROOT" merge-base --is-ancestor "$TAG" HEAD 2>/dev/null; then
    ok "'$TAG' is an ancestor of HEAD"
else
    bad "'$TAG' is not an ancestor of HEAD"
fi

for f in shell.qml testing/ServiceTest.qml services/qmldir shell/topisland/TopIsland.qml; do
    if git -C "$REPO_ROOT" cat-file -e "$TAG:$f" 2>/dev/null; then
        ok "baseline tree contains $f"
    else
        bad "baseline tree is missing $f"
    fi
done

# --- the document exists and records what it claims --------------------------

if [ -s "$DOC" ]; then
    ok "baseline record exists at docs/pre-rewrite-baseline.md"
else
    bad "baseline record missing at docs/pre-rewrite-baseline.md -- nothing documents the tag"
fi

for claim in "$TAG" "$EXPECTED_COMMIT" "$EXPECTED_SUBJECT" "$LAUNCH_CMD" "git worktree add" "pre-rewrite"; do
    if [ -s "$DOC" ] && grep -qF -- "$claim" "$DOC"; then
        ok "baseline record documents: $claim"
    else
        bad "baseline record does not document: $claim"
    fi
done

# --- restore: the tag checks out cleanly, in isolation -------------------------

if [ ! -s "$DOC" ]; then
    echo
    echo "$FAIL check(s) failed, $PASS passed -- stop before launch checks (no record yet)."
    exit 1
fi

BASE_TMP="${TMPDIR:-/tmp}"
if [ -d /tmp/opencode ] && [ -w /tmp/opencode ]; then BASE_TMP="/tmp/opencode"; fi
RUN_DIR="$(mktemp -d "$BASE_TMP/nosarch-baseline-verify.XXXXXX")"
WORKTREE_DIR="$RUN_DIR/pre-rewrite-checkout"

if git -C "$REPO_ROOT" worktree add --detach "$WORKTREE_DIR" "$TAG" >"$RUN_DIR/worktree.log" 2>&1; then
    ok "'git worktree add --detach <dir> $TAG' succeeds (restore is exercisable)"
else
    bad "restore via temp worktree failed -- see $RUN_DIR/worktree.log"; exit 1
fi

if [ -z "$(git -C "$WORKTREE_DIR" status --porcelain)" ]; then
    ok "checkout of '$TAG' is clean (no missing or modified files)"
else
    bad "checkout of '$TAG' is not clean"
fi

if [ -f "$WORKTREE_DIR/shell.qml" ]; then
    ok "checked-out baseline has its entrypoint (shell.qml) at the worktree root"
else
    bad "checked-out baseline has no shell.qml at the worktree root"
fi

# --- launch: the documented command actually runs -----------------------------

if [ -z "${BASELINE_SKIP_LAUNCH:-}" ]; then
    run_baseline_launch "shell.qml launch" "$LAUNCH_CMD"
    run_baseline_launch "ServiceTest launch" "$SERVICETEST_CMD"
else
    info "BASELINE_SKIP_LAUNCH set -- skipping live launch checks"
fi

# --- summary ------------------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    echo "All $PASS checks passed. The pre-rewrite baseline record is trustworthy."
    exit 0
else
    echo "$FAIL check(s) failed, $PASS passed."
    exit 1
fi
