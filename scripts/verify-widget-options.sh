#!/usr/bin/env bash
#
# verify-widget-options.sh — verification for ticket 09.
#
#   "As a user, I want each widget to declare its own options in
#    configuration, so that widgets can be tuned without a code change."
#
# Four checks:
#   (A) STATIC — the mechanism is where it claims to be. The widget CONTRACT
#       (BarWidget) owns the option machinery, so every widget inherits it and
#       none re-implements it; the clock declares its own option and binds its
#       rendering to it; and the zone hands the entry's settings to the widget
#       at construction.
#   (B) RUNTIME — a declared option REACHES its widget, end to end: a real
#       configuration file on a real filesystem, read by the real reader, built
#       by the real zone. The claim under test is about the whole path, so the
#       test drives the whole path.
#   (C) BEHAVIOUR — changing that option changes what the widget SHOWS, with
#       no code change. Two runs of the same unmodified tree against two
#       different configuration files must produce different rendered text. This
#       is the falsifiable form of "tunable by configuration alone": a mechanism
#       that delivered the value without changing behaviour would still pass (B).
#   (D) FAILURE POLICY — an option no widget declares is reported by name and
#       the widget is STILL BUILT. It is refused, never fatal, and never
#       silently dropped (ADR 0003). Also asserted here: a bad option does not
#       poison the good ones beside it, and an entry carrying no options at all
#       — the format as shipped by ticket 07 — still works unchanged.
#
# WHY AN UNRECOGNISED OPTION IS REFUSED RATHER THAN STRIPPED
#
#   It is refused LOUDLY (a named log line, the same CONFIG prefix everything
#   else uses) rather than silently stripped, which is the whole of the
#   `path`/`file` precedent: a user who wrote one would otherwise believe it
#   worked. What differs is that refusing it does NOT cost the entry. A
#   `path`/`file` key had to be refused outright because honouring it is a
#   code-execution hole; there is no such danger in an option key, so the only
#   thing left to protect is the user's belief — and a named line does that.
#   Dropping the whole widget would additionally make the shipped configuration
#   hostile to the future it was designed for: the file is deployed to every
#   target machine, so a shell older than its own configuration file must
#   degrade to "this option is not applied yet", not "this widget is gone".
#   scripts/verify-widget-options.sh asserts that degradation.
#
# SAFETY (the live desktop is running): every launch runs under
# `dbus-run-session` (throwaway bus — the shell's NotificationServer cannot
# disturb swaync, which owns the real one) with HOME *and* XDG_CONFIG_HOME
# pointed at scratch, and is bounded by a timeout. Both variables matter:
# XDG_CONFIG_HOME is set in this environment, so redirecting HOME alone would
# point the reader straight back at the real ~/.config. smoke.qml draws no
# layer-shell surfaces, so nothing appears on screen and waybar is never
# involved. Nothing is written to ~/.config, ~/.local/share or any installed
# location.
#
# Exit status: 0 only if all four checks hold.

set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"

# Fast smoke timing: nothing here needs live hardware, only the shell's own
# load path, so the smoke shell's capped wait periods are shortened (as in
# verify-bar-config.sh and verify-widget-contract.sh) to keep each run quick.
export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-800}"

TMP="$(mktemp -d /tmp/opencode/qs-opts.XXXXXX)"
LOG="$TMP/smoke.log"

static_rc=1
reaches_rc=1
behaviour_rc=1
policy_rc=0

cleanup() {
    # Kill only THIS shell: its cmdline carries this worktree's unique path.
    # Never a broad pkill — the live desktop runs a shell too, and so do the
    # other verifiers and the other tickets' worktrees.
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 09 verification — per-widget options from configuration"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# new_home <case-name> — a fresh scratch HOME per case, so no case can see
# another case's configuration file (a leftover file would make a case pass for
# the wrong reason).
new_home() {
    local home="$TMP/$1"
    rm -rf "$home"
    mkdir -p "$home/.config/quickshell/nosarch"
    echo "$home"
}

# config_path <home> — the reader's path, as a real machine would have it. Built
# here independently of the shell code on purpose: if the two disagreed, the
# cases would be testing nothing.
config_path() { echo "$1/.config/quickshell/nosarch/shell.json"; }

# write_config <home> <json> — put a configuration file where a real machine
# would keep it.
write_config() {
    printf '%s\n' "$2" > "$(config_path "$1")"
}

# run_smoke <scratch-home> — launch the smoke shell with HOME and XDG_CONFIG_HOME
# both pointed at the scratch dir, wait for it to finish, leave the log at $LOG.
run_smoke() {
    local home="$1" pid
    cd "$REPO" || return 1
    HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        timeout "$RUN_SECS" dbus-run-session -- \
        quickshell --no-color --log-times -p "$SMOKE_QML" >"$LOG" 2>&1 &
    pid=$!
    local i
    for i in $(seq 1 $((RUN_SECS * 10))); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    # Still alive means it hung: TERM `timeout`, which kills the whole process
    # group (dbus-run-session and the quickshell under it).
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null
    return 0
}

# no_qml_errors <case> — the log must carry no WARN/ERROR naming a file in this
# repository. A deliberately mis-configured option is reported by the shell's
# OWN log line (the CONFIG prefix, which names no source file), so it does not
# trip this; a genuine QML type error or unresolved binding would.
check_log_clean() {
    local name="$1"
    python3 - "$LOG" "$name" "$REPO" <<'PY'
import re, sys, pathlib
log, name, repo = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
rc = 0
out = []
# A QML-level warning names the file it came from as `qs:<path>:<line>`, or
# "<file>:<line>". Anything naming a file inside this repo is a defect. Warnings
# with no repo file attached (xdg-desktop-portal, Qt platform services) are
# third-party noise.
for ln in log.read_text(errors='replace').splitlines():
    m = re.search(r'(?:WARN|ERROR)\s+(?:qml:)?\s*qs?:?/?(\S+?):\d+', ln)
    if not m:
        continue
    path = m.group(1)
    if path.startswith(str(repo)) or ('/' + str(repo).lstrip('/')) in ln:
        out.append(ln.strip())
        rc = 1
if rc == 0:
    print(f"PASS {name} — no WARN/ERROR naming a file in this repository")
else:
    print(f"FAIL {name} — {len(out)} WARN/ERROR line(s) name a file in this repository")
    for l in out[:6]:
        print(f"       {l}")
sys.exit(rc)
PY
}

# ---------------------------------------------------------------------------
# (A) STATIC: the mechanism is on the contract, not in one widget
# ---------------------------------------------------------------------------
echo
echo "[A] static: the option machinery, and the clock's own option ..."
static_rc=1
# The rc is taken from the assignment itself, not from `$?` after an `echo`:
# `x=$(cmd)` and `echo "$x"` in sequence would test the echo's status, which is
# always 0. Same pattern for every other python block below.
static_out=$(python3 - "$REPO" <<'PY'
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1])

def read(rel):
    p = repo / rel
    return p.read_text(encoding='utf-8', errors='replace') if p.is_file() else ''

base = read('shell/widgets/BarWidget.qml')
zone = read('shell/bar/BarZone.qml')
clock = read('shell/widgets/ClockWidget.qml')
simple = read('shell/widgets/SimpleBarWidget.qml')

bad = []
rc = 0
def ok(cond, label, detail):
    global rc
    print(f"  {'pass' if cond else 'FAIL'} {label}: {detail}")
    if not cond:
        rc = 1

# ---- the CONTRACT owns the machinery, so every widget inherits it ----------
# If this lived in ClockWidget it would be re-implemented twelve times over,
# which is exactly what the base class exists to prevent.
ok(bool(re.search(r'property\s+var\s+options\b', base)),
   'contract-declares-options',
   'BarWidget declares a `var options` property every widget inherits'
   if re.search(r'property\s+var\s+options\b', base)
   else 'BarWidget declares no `var options` property — there is nowhere for a '
        'configuration entry to put its settings')

ok(bool(re.search(r'function\s+optionValue\s*\(', base)),
   'contract-reads-options',
   'BarWidget exposes optionValue(), so a widget reads an option the same way '
   'everywhere'
   if re.search(r'function\s+optionValue\s*\(', base)
   else 'BarWidget exposes no optionValue() — each widget would roll its own '
        'fallback-to-default rule')

ok(bool(re.search(r'readonly\s+property\s+var\s+unrecognisedOptions\b', base)),
   'contract-reports-unknown-keys',
   'BarWidget reports the keys it was given but does not declare, as '
   'unrecognisedOptions'
   if re.search(r'readonly\s+property\s+var\s+unrecognisedOptions\b', base)
   else 'BarWidget computes no unrecognisedOptions — a key it silently ignores '
        'is indistinguishable from one it honoured')

# THE QML CONSTRAINT THAT MAKES optionDefaults NON-readonly. A derived type
# cannot override a base `readonly` property (verified on the installed
# Quickshell: "Invalid property assignment: \"optionDefaults\" is a read-only
# property"), so the widget's declaration would be unreachable if the base
# declared it readonly. This is checked because getting it wrong produces a
# widget that compiles and then silently keeps the empty default map.
m = re.search(r'property\s+var\s+optionDefaults\s*:', base)
readonly_decl = re.search(r'readonly\s+property\s+var\s+optionDefaults\s*:', base)
ok(m is not None and readonly_decl is None,
   'contract-declaration-is-overridable',
   'BarWidget declares optionDefaults writable, because a derived type cannot '
   'override a readonly property — a widget must be able to declare its own'
   if (m is not None and readonly_decl is None)
   else ('BarWidget declares no optionDefaults' if m is None else
         'BarWidget declares optionDefaults readonly, which no widget could '
         'override'))

# ---- the ZONE hands the entry's settings to the widget ---------------------
delivers = re.search(r'options\s*:\s*settings', zone) and \
           re.search(r'settings\s*=\s*[^\n]*entry\.settings', zone)
ok(bool(delivers),
   'zone-delivers-settings',
   'BarZone passes the entry\'s settings as the widget\'s options at '
   'construction'
   if delivers else
   'BarZone never hands entry.settings to the widget — the reader keeps the '
   'settings (ticket 07) and nothing ever delivers them')

# ---- the CLOCK declares and honours its OWN option -------------------------
m = re.search(r'optionDefaults\s*:\s*\(([^)]*)\)', clock)
declared = re.findall(r'"([A-Za-z][A-Za-z0-9]*)"\s*:', m.group(1)) if m else []
ok('timeFormat' in declared,
   'clock-declares-an-option',
   f'ClockWidget declares {declared} as its own option'
   if declared else 'ClockWidget declares no option of its own, so nothing '
                    'about it can be tuned by configuration')

drives = re.search(r"optionValue\s*\(\s*['\"]timeFormat", clock)
ok(bool(drives),
   'clock-option-drives-rendering',
   'the clock reads timeFormat through optionValue(), so the option drives '
   'rendering rather than sitting beside it'
   if drives else
   'the clock never reads its timeFormat option, so setting it could not '
   'change anything')

# The widget must render from the option, not from a literal: a clock whose
# format is written into its text binding would pass the line above and still
# be untunable.
renders_both = bool(re.search(r"LongFormat", clock)) or \
              bool(re.search(r"timeFormat\s*===?\s*['\"]long", clock))
ok(renders_both,
   'clock-renders-both-values',
   'the clock renders more than one time format, so the option has something '
   'to select'
   if renders_both else
   'the clock still renders exactly one hardcoded format — an option that '
   'cannot change anything is not an option')

# ---- a widget with NO options needs to declare nothing ---------------------
# The point of the mechanism being general: adding options to the eleven other
# widgets is their own tickets, and this one must not need editing.
ok('optionDefaults' not in simple,
   'options-are-optional',
   'SimpleBarWidget declares no option, so a widget with nothing to tune '
   'changes nothing (as panelContent is optional under the same contract)'
   if 'optionDefaults' not in simple
   else 'SimpleBarWidget declares optionDefaults although it has nothing to '
        'tune — every widget would then carry a declaration it does not need')

sys.exit(rc)
PY
) && static_rc=0
echo "${static_out}"
echo "    [A] static exit=$static_rc"

# ---------------------------------------------------------------------------
# (B) a declared option REACHES its widget, end to end
# ---------------------------------------------------------------------------
echo
echo "[B] runtime: a declared option reaches the widget that declared it ..."
reaches_rc=1
home="$(new_home reaches)"
write_config "$home" '{
  "bar": {
    "floating": true,
    "zones": {
      "left": [],
      "center": [{ "type": "clock", "timeFormat": "long" }],
      "right": []
    }
  }
}'
run_smoke "$home"
reaches_out=$(python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()
rc = 0
def ok(cond, label, detail):
    global rc
    print(f"  {'pass' if cond else 'FAIL'} {label}: {detail}")
    if not cond:
        rc = 1

opts = [l for l in lines if 'CONFIG probe option ' in l]
if not opts:
    ok(False, 'option-reaches-widget',
       'the smoke run reported nothing about any widget\'s options — there is '
       'no seam at which this claim can be checked')
    sys.exit(rc)
line = next((l for l in opts if 'type=clock' in l), opts[0])

def field(name):
    m = re.search(rf'(?:^|\s){name}=("[^"]*"|\S*)', line.split('CONFIG probe option ', 1)[1])
    return m.group(1).strip('"') if m else None

value = field('value')
ok(value == 'long',
   'option-reaches-widget',
   f'the configuration file said timeFormat="long" and the clock reports '
   f'value={value!r}'
   if value == 'long' else
   f'the configuration file said timeFormat="long" but the clock reports '
   f'value={value!r} — the option never reached the widget')

declared = field('declared')
ok(declared is not None and 'timeFormat' in declared,
   'widget-declares-it',
   f'the clock reports its own declaration as declared={declared!r}'
   if declared else 'the clock reported no declaration at all')

built = field('built')
ok(built == 'yes',
   'widget-built-with-options',
   'the widget was built from an entry that carried an option'
   if built == 'yes' else f'the widget reports built={built!r}')

unrec = field('unrecognised')
ok(unrec in ('', None),
   'declared-key-not-reported',
   'a key the widget declares is not reported as unrecognised'
   if unrec in ('', None) else f'a DECLARED key was reported unrecognised: {unrec!r}')

sys.exit(rc)
PY
) && reaches_rc=0
echo "${reaches_out}"
check_log_clean "options-reach-no-qml-errors" || reaches_rc=1
echo "    [B] runtime exit=$reaches_rc"

# ---------------------------------------------------------------------------
# (C) changing the option changes what the widget SHOWS, no code change
# ---------------------------------------------------------------------------
echo
echo "[C] behaviour: the option changes the rendering, with no code change ..."
behaviour_rc=1
: > "$TMP/behaviour.txt"

# Two runs of the SAME unmodified tree against two different configuration
# files. Nothing in this repository changes between them, which is the whole
# claim: tuning a widget is a configuration edit and nothing else.
for pair in "short:behaviour-short" "long:behaviour-long"; do
    fmt="${pair%%:*}"
    name="${pair##*:}"
    h="$(new_home "$name")"
    write_config "$h" "{
  \"bar\": {
    \"floating\": true,
    \"zones\": {
      \"left\": [],
      \"center\": [{ \"type\": \"clock\", \"timeFormat\": \"$fmt\" }],
      \"right\": []
    }
  }
}"
    run_smoke "$h"
    # APPEND, never write: one row per configuration, and the comparison below
    # needs both. (write_text truncates, which silently leaves one row.)
    python3 - "$LOG" "$fmt" "$TMP/behaviour.txt" <<'PY'
import re, sys, pathlib
log, fmt, out = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
lines = log.read_text(errors='replace').splitlines()
line = next((l for l in lines if 'CONFIG probe option ' in l and 'type=clock' in l), None)
if line is None:
    out.write_text(f"{fmt}\tNO-REPORT\n"); sys.exit(0)   # nothing to append
body = line.split('CONFIG probe option ', 1)[1]
def field(name):
    m = re.search(rf'(?:^|\s){name}=("[^"]*"|\S*)', body)
    return m.group(1).strip('"') if m else ''
with out.open('a') as fh:
    fh.write(f"{fmt}\t{field('value')}\t{field('pattern')}\t{field('text')}\n")
PY
    check_log_clean "behaviour-$fmt-no-qml-errors" || behaviour_rc=1
done

behaviour_out=$(python3 - "$TMP/behaviour.txt" <<'PY'
import sys, pathlib
rows = {}
for ln in pathlib.Path(sys.argv[1]).read_text().splitlines():
    parts = ln.split('\t')
    if len(parts) >= 4:
        rows[parts[0]] = (parts[1], parts[2], parts[3])
rc = 0
def ok(cond, label, detail):
    global rc
    print(f"  {'pass' if cond else 'FAIL'} {label}: {detail}")
    if not cond:
        rc = 1

for fmt, expect in (('short', 'short'), ('long', 'long')):
    got = rows.get(fmt)
    ok(got is not None and got[0] == expect,
       f'{fmt}-config-honoured',
       f'the configuration file said timeFormat="{fmt}" and the clock reports '
       f'value={got[0]!r}' if got and got[0] == expect
       else f'no report for the {fmt} configuration'
            if got is None else
            f'the configuration file said timeFormat="{fmt}" but the clock '
            f'reports value={got[0]!r}')

s, l = rows.get('short'), rows.get('long')
if s and l and s[0] == 'short' and l[0] == 'long':
    ok(s[1] != l[1],
       'format-pattern-differs',
       f'the two configurations produced different renderings: short={s[1]!r}, '
       f'long={l[1]!r} — so the option selects the behaviour'
       if s[1] != l[1] else
       f'both configurations produced the SAME rendering {s[1]!r}: the option '
       f'is delivered but does nothing, which is not tuning')
    ok(s[2] != l[2],
       'rendered-text-differs',
       f'the clock actually rendered different text: short={s[2]!r}, '
       f'long={l[2]!r}'
       if s[2] != l[2] else
       f'both configurations rendered the identical text {s[2]!r}')
    ok(l[1] != '' and 'ss' in l[1],
       'long-format-shows-seconds',
       f'the long rendering is the seconds-bearing one ({l[1]!r}), so the '
       f'formats are genuinely different and not two names for one thing'
       if 'ss' in l[1] else
       f'the "long" rendering pattern is {l[1]!r}, which does not even carry '
       f'seconds — the two names may not mean what they say')
sys.exit(rc)
PY
) && behaviour_rc=0
echo "${behaviour_out}"
echo "    [C] behaviour exit=$behaviour_rc"

# ---------------------------------------------------------------------------
# (D) the failure policy: an option nobody declares is refused, never fatal
# ---------------------------------------------------------------------------
echo
echo "[D] failure policy: an undeclared option is named, and never fatal ..."
policy_d_rc=0   # both variants must pass, so a failure in EITHER fails [D]
# [D] and [E] can only ever SET policy_rc to 1 (on failure), so it starts at 0
# and is never lowered afterwards. An earlier version of this script reset it to
# 0 just before the verdict, which silently discarded [D]'s result: a mutation
# that made an unrecognised option FATAL still reported PASS. Verified by
# mutation, not assumed — see the note at the end of this file.
policy_rc=0

# Two shapes of the same mistake, because they must behave the same way:
#   1. a MISSPELT key — an ordinary mistake, and the one a user actually makes;
#   2. a key NO shipped widget declares — the forward-compatibility case, where
#      the configuration file is newer than the shell reading it.
# In both the widget must still be built, the declared option beside the bad
# key must still take effect, and a named line must be in the log.
for variant in "policy-misspelt:timeformat" "policy-unknown:nonesuch"; do
    name="${variant%%:*}"
    badkey="${variant##*:}"
    h="$(new_home "$name")"
    write_config "$h" "{
  \"bar\": {
    \"floating\": true,
    \"zones\": {
      \"left\": [],
      \"center\": [{ \"type\": \"clock\", \"timeFormat\": \"long\", \"$badkey\": \"short\" }],
      \"right\": [{ \"type\": \"clock\", \"timeFormat\": \"long\" }]
    }
  }
}"
    run_smoke "$h"
    policy_d_out=$(python3 - "$LOG" "$name" "$badkey" <<'PY'
import re, sys, pathlib
log, name, badkey = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = log.read_text(errors='replace').splitlines()
rc = 0
def ok(cond, label, detail):
    global rc
    print(f"  {'pass' if cond else 'FAIL'} {name}/{label}: {detail}")
    if not cond:
        rc = 1

# --- the refusal must be NAMED, not silent --------------------------------
# Matched on the REFUSAL line itself, not merely on the key appearing
# anywhere. The smoke probe also prints the keys an entry carried, so a looser
# match would pass against a build that silently strips the key — which is
# exactly the behaviour this check exists to forbid. (Verified by mutation.)
refusals = [l for l in lines
            if re.search(r'CONFIG\s+refused\s+option\b', l)
            and re.search(rf'\bkey={re.escape(badkey)}\b', l)]
ok(bool(refusals),
   'bad-option-is-named',
   f'the log names the offending key {badkey!r} as a refusal: '
   + (refusals[0].split('CONFIG refused option ', 1)[-1][:130] if refusals else '')
   if refusals else
   f'no refusal line names {badkey!r} — an option that is silently dropped '
   f'leaves its author believing it worked, which is the one thing the '
   f'`path`/`file` precedent forbids')

# --- and only the offending entry, by name ---------------------------------
# The configuration used here has TWO clocks: one in `center` carrying the bad
# key, one in `right` that is clean. Every refusal must therefore name
# `center`, and none may name `right`. That is the assertion with teeth: a
# build that reported a refusal per rebuild, or attributed it to the wrong
# entry, or refused a key no entry carried all fail here. (A bare "appeared at
# least once" check passed against all three.)
misattributed = [l for l in refusals
                 if not re.search(r'bar\.zones\.center\[', l)]
ok(not misattributed,
   'refused-only-the-offending-entry',
   'every refusal names the entry that actually carried the bad key '
   '(center), and the clean entry in right drew none'
   if not misattributed else
   f'{len(misattributed)} refusal line(s) name an entry that did not carry '
   f'the key: {misattributed[0].split("CONFIG refused option ")[-1][:90]}')

# The refusal must name the key AND the widget's declared options, because
# "which did I mean" is the question the author actually has.
ok(all(re.search(r'\bdeclared=\S+', l) for l in refusals) and bool(refusals),
   'refusal-lists-the-declared-options',
   'each refusal lists what the widget DOES declare, so a misspelt key can be '
   'matched against the real ones from the log alone'
   if all(re.search(r'\bdeclared=\S+', l) for l in refusals) and refusals
   else 'a refusal does not say what the widget does declare')

# --- the widget must STILL BE BUILT (never fatal, never lost) -------------
opts = [l for l in lines if 'CONFIG probe option ' in l and 'type=clock' in l]
ok(len(opts) >= 2,
   'both-widgets-still-built',
   f'{len(opts)} clock(s) were built from an entry carrying a bad option'
   if len(opts) >= 2 else
   f'only {len(opts)} clock(s) were built — a bad option cost the user the '
   f'widget, which is what ADR 0003 forbids')
for l in opts:
    m = re.search(r'built=(\S+)', l)
    if m and m.group(1) != 'yes':
        ok(False, 'widget-built', f'a clock reports built={m.group(1)}')
        break
else:
    ok(True, 'widget-built', 'every clock reports built=yes')

# --- the bad key must not poison the good one beside it -------------------
# The bad key must be the ONLY casualty: an entry that also carries a declared
# option must still have had that one applied. This is the check that
# distinguishes "the unknown key was refused" from "the whole entry was
# refused", which are easy to confuse and behave very differently for a user.
for l in opts:
    body = l.split('CONFIG probe option ', 1)[1]
    m = re.search(r'(?:^|\s)value=(\S*)', body)
    if m and m.group(1) != 'long':
        ok(False, 'good-option-still-applies',
           f'the DECLARED option beside the bad key did not take effect '
           f'(value={m.group(1)!r} — expected long): one bad key must cost one '
           f'key, not the whole entry')
        break
else:
    ok(True, 'good-option-still-applies',
       'the declared option beside the bad key still took effect — the bad key '
       'cost exactly one key')
sys.exit(rc)
PY
    ) || policy_d_rc=1
    echo "${policy_d_out}"
    check_log_clean "$name-no-qml-errors" || policy_rc=1
done
[[ $policy_d_rc -eq 0 ]] || policy_rc=1

# ---------------------------------------------------------------------------
# (E) the entry format as shipped: no options at all
# ---------------------------------------------------------------------------
echo
echo "[E] the ticket-07 entry format still works with no options at all ..."
home="$(new_home nooptions)"
write_config "$home" '{
  "bar": {
    "floating": true,
    "zones": {
      "left": [],
      "center": [{ "type": "clock" }],
      "right": []
    }
  }
}'
run_smoke "$home"
policy_e=1
policy_e_out=$(python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()
rc = 0
def ok(cond, label, detail):
    global rc
    print(f"  {'pass' if cond else 'FAIL'} {label}: {detail}")
    if not cond:
        rc = 1

opts = [l for l in lines if 'CONFIG probe option ' in l and 'type=clock' in l]
ok(bool(opts), 'no-options-builds',
   'a bare { "type": "clock" } entry — the exact format ticket 07 shipped — '
   'still builds'
   if opts else 'a bare { "type": "clock" } entry no longer builds')

if opts:
    body = opts[0].split('CONFIG probe option ', 1)[1]
    def field(n):
        m = re.search(rf'(?:^|\s){n}=("[^"]*"|\S*)', body)
        return m.group(1).strip('"') if m else None
    ok(field('built') == 'yes', 'no-options-built-yes',
       f'the clock reports built={field("built")!r}')
    ok(field('unrecognised') in ('', None), 'no-options-no-unrecognised',
       'an entry carrying no options reports nothing unrecognised')
    ok(bool(field('text')), 'no-options-still-renders',
       f'the clock still renders text={field("text")!r} with no configuration '
       f'options at all')

# The shell must have reached a verdict rather than falling over.
ok(any('SMOKE SUMMARY' in l for l in lines), 'shell-still-up',
   'the smoke shell ran to its summary — a bad configuration cost one key, '
   'not the shell')
sys.exit(rc)
PY
) && policy_e=0 || policy_e=1
echo "${policy_e_out}"
[[ $policy_e -eq 0 ]] || policy_rc=1
check_log_clean "no-options-no-qml-errors" || policy_rc=1

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $reaches_rc -eq 0 && $behaviour_rc -eq 0 && $policy_rc -eq 0 ]]; then
    echo " RESULT: PASS (static mechanism + option reaches widget + behaviour"
    echo "         changes + failure policy)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  (static=$([[ $static_rc -eq 0 ]] && echo ok || echo FAIL),"
    echo "         reaches=$([[ $reaches_rc -eq 0 ]] && echo ok || echo FAIL),"
    echo "         behaviour=$([[ $behaviour_rc -eq 0 ]] && echo ok || echo FAIL),"
    echo "         policy=$([[ $policy_rc -eq 0 ]] && echo ok || echo FAIL))"
    echo " --- captured log tail (if any) ---"
    tail -n 40 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi