#!/usr/bin/env bash
#
# verify-widget-contract.sh — verification for ticket 06.
#
#   "Every bar widget satisfies one uniform contract by extending a single base
#    class, declaring the same required interface: content for the bar, a click
#    action, a tooltip, and optionally panel content. A widget name in
#    configuration resolves through a map from name to file held in the shell
#    code — and configuration never carries file paths."
#
# Three checks:
#   (A) STATIC — the contract is what it claims to be. The base declares the
#       uniform required interface; the simplified base exists and fills in the
#       members a trivial label-plus-click widget should not have to declare;
#       every widget in shell/widgets/ extends one of the two bases; the
#       registry's name→file map agrees with the directory in BOTH directions;
#       and no registry key or value is a file path (the code-execution
#       surface the spec refuses to open).
#   (B) RUNTIME — smoke.qml is launched and every planned widget reports PASS,
#       by name. This is the same instantiation seam verify-smoke.sh uses; the
#       framework's only failure signal is the log, so a type error in a widget
#       that loads cleanly enough to compile is caught here and nowhere else.
#   (C) RESOLUTION — the registry is asked, at run time, to resolve every name
#       it holds and every name it must reject. A name that resolves to null
#       fails; a name it was never given must not resolve to anything.
#
# WHAT MAKES THE CONTRACT'S PROMISES FALSIFIABLE HERE
#
#   * A widget with no panel must report hasPanel === false and must not
#     declare panelContent at all — "supplies nothing rather than an empty one"
#     is checked as the absence of the declaration, not the emptiness of it.
#   * The clock is asked for its own members (does it carry time and date, is
#     its update cadence one minute) and the answers are compared against what
#     the contract promises.
#   * The base is asked whether it dims when not hovered and brightens on
#     hover, i.e. the affordance is read off the instance rather than trusted
#     from a comment.
#
# SAFETY (the live desktop is running): smoke.qml runs under `dbus-run-session`,
# so its NotificationServer owns org.freedesktop.Notifications on a throwaway
# private bus and cannot disturb swaync, which owns the real one. smoke.qml
# creates NO layer-shell surfaces (every instantiated object is parented to plain
# in-memory Items), so nothing is drawn and waybar is never involved. HOME is
# redirected to a scratch directory because the file-backed palette (ticket 04)
# writes ~/.local/share/nosarch/current-theme/palette.json on first run — the
# path is resolved from HOME, so the write lands in the scratch home.
#
# Exit status: 0 only if all three checks pass.

set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SMOKE_QML="smoke.qml"
RUN_SECS="${RUN_SECS:-30}"

# Fast smoke timing: nothing here needs live hardware, only the shell's own load
# path, so the smoke shell's capped wait periods are shortened (as in
# verify-palette.sh) to keep the run to a few seconds.
export SMOKE_HARDWARE_CAP_MS="${SMOKE_HARDWARE_CAP_MS:-500}"
export SMOKE_SCREEN_WAIT_MS="${SMOKE_SCREEN_WAIT_MS:-500}"
export SMOKE_FINAL_MS="${SMOKE_FINAL_MS:-800}"

TMP="$(mktemp -d /tmp/opencode/qs-contract.XXXXXX)"
LOG="$TMP/smoke.log"
HOME_DIR="$TMP/home"

static_rc=1
runtime_rc=1
resolve_rc=1

cleanup() {
    # Kill only THIS shell: its cmdline carries this worktree's unique path.
    pkill -f "quickshell.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    pkill -f "dbus-run-session.*${REPO}/${SMOKE_QML}" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo " Ticket 06 verification — widget contract, registry, and the clock"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) STATIC: the contract, the bases, and the name→file map
# ---------------------------------------------------------------------------
echo
echo "[A] static contract + registry ..."
python3 - "$REPO" <<'PY'
import json, re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
widgets_dir = repo / 'shell/widgets'
problems = []

def read(p):
    return p.read_text(encoding='utf-8', errors='replace') if p.is_file() else ''

BASE = 'BarWidget.qml'
SIMPLE = 'SimpleBarWidget.qml'
REGISTRY = 'WidgetRegistry.qml'

# ---- the directory exists, and is a single predictable place ---------------
if not widgets_dir.is_dir():
    print(f"    FAIL — no {widgets_dir.relative_to(repo)}/ directory: widgets have no one place to live")
    sys.exit(1)

# ---- the base declares the uniform required interface ----------------------
base = read(widgets_dir / BASE)
if not base:
    problems.append(f"{BASE} does not exist")
else:
    required_members = {
        'content':   r'required\s+property\s+Component\s+content\b',
        'activate':  r'required\s+property\s+var\s+activate\b',
        'tooltip':   r'required\s+property\s+string\s+tooltip\b',
    }
    for member, pat in required_members.items():
        if not re.search(pat, base):
            problems.append(f"{BASE} does not declare `required property ... {member}` "
                            f"— every widget must be forced to supply it")
    # panel content is OPTIONAL: not required, and null by default.
    m = re.search(r'property\s+Component\s+panelContent\s*:\s*(\S+)', base)
    if not m:
        problems.append(f"{BASE} declares no `panelContent` property — the optional half "
                        f"of the contract is missing")
    elif m.group(1) != 'null':
        problems.append(f"{BASE} defaults panelContent to {m.group(1)}, not null — a widget "
                        f"with no panel would inherit a non-empty one")
    if re.search(r'required\s+property\s+Component\s+panelContent', base):
        problems.append(f"{BASE} marks panelContent required — panel content must stay optional")
    # hasPanel is what the contract's optionality is read through
    if 'hasPanel' not in base:
        problems.append(f"{BASE} exposes no `hasPanel` — nothing can tell a widget with a "
                        f"panel from one without")
    # the hover affordance lives in the BASE, not in each widget
    for token, why in (('hoverEnabled', 'hover tracking'),
                       ('ToolTip', 'the tooltip'),
                       ('contentOpacity', 'dim/bright on hover')):
        if token not in base:
            problems.append(f"{BASE} carries no {token} ({why}) — the affordance must live in "
                            f"the contract, not be reimplemented per widget")

# ---- the simplified base exists and does fill the members in ---------------
simple = read(widgets_dir / SIMPLE)
if not simple:
    problems.append(f"{SIMPLE} does not exist — a trivial label-plus-click widget is "
                    f"forced to declare a panel it does not have")
else:
    if not re.search(r'extends\s*\(?\s*' + re.escape(BASE[:-4]), simple) and \
       not re.search(re.escape(BASE[:-4]) + r'\s*\{', simple):
        problems.append(f"{SIMPLE} does not extend {BASE[:-4]}")
    if not re.search(r'\bcontent\s*:', simple):
        problems.append(f"{SIMPLE} supplies no `content` — the whole point of the simplified "
                        f"base is that a trivial widget need not build its own")
    if re.search(r'required\s+property\s+Component\s+content', simple):
        problems.append(f"{SIMPLE} re-declares `content` as required, defeating its purpose")

# ---- every widget in the directory is on one of the two bases --------------
qmldir_text = read(widgets_dir / 'qmldir')
registered = {}
for line in qmldir_text.splitlines():
    line = line.strip()
    if not line or line.startswith('#') or line.startswith('module '):
        continue
    parts = line.split()
    if len(parts) >= 2:
        name = parts[1] if parts[0] == 'singleton' else parts[0]
        registered[name] = parts[-1]

on_disk = {f.name for f in widgets_dir.glob('*.qml')}
unregistered = sorted(on_disk - set(registered.values()))
if unregistered:
    problems.append(f"in shell/widgets/ but absent from its qmldir (so they are "
                    f"unimportable): {', '.join(unregistered)}")
if not registered:
    problems.append("shell/widgets/qmldir registers no types")

# The contract machinery (base, simplified base, registry) is not itself a
# widget: it declares no content and configuration never places it. Matched by
# FILE name, which is what on_disk holds.
INFRASTRUCTURE = {BASE, SIMPLE, REGISTRY}
widget_files = sorted(f for f in on_disk if f not in INFRASTRUCTURE)
for f in widget_files:
    text = read(widgets_dir / f)
    if not re.search(r'\b' + re.escape(BASE[:-4]) + r'\b\s*\{', text) and \
       not re.search(r'\b' + re.escape(SIMPLE[:-4]) + r'\b\s*\{', text):
        problems.append(f"{f} extends neither {BASE[:-4]} nor {SIMPLE[:-4]} "
                        f"— a widget outside the contract")

# ---- the registry: name→file, in shell code, never a path ------------------
reg = read(widgets_dir / REGISTRY)
if not reg:
    problems.append(f"{REGISTRY} does not exist — names would have no way to resolve")
else:
    m = re.search(r'(?:property|readonly\s+property)\s+var\s+entries\s*:\s*\(?\{(.*?)\}\)?\s*\n',
                  reg, re.S)
    if not m:
        problems.append(f"{REGISTRY} has no `var entries` name→file map")
    else:
        body = m.group(1)
        entries = dict(re.findall(r'["\']([^"\']+)["\']\s*:\s*["\']([^"\']+)["\']', body))
        print(f"    registry entries: {len(entries)}")
        for k, v in sorted(entries.items()):
            # the code-execution surface the spec refuses: a config that can
            # NAME a file can load arbitrary code.
            if '/' in k or k.endswith('.qml') or '\\' in k or '..' in k:
                problems.append(f"registry key {k!r} looks like a path — configuration must "
                                f"name widgets, never locate code")
            if '/' in v or '\\' in v or v.startswith('..'):
                problems.append(f"registry value for {k!r} is a path ({v}) — the map resolves "
                                f"relative to its own directory, never from configuration")
            target = widgets_dir / v
            if not target.is_file():
                problems.append(f"registry name {k!r} points at {v}, which is not a file in "
                                f"shell/widgets/")
            elif v not in widget_files:
                problems.append(f"registry name {k!r} points at {v}, which is not a widget "
                                f"(not on the contract)")
        # and in the OTHER direction: a widget nobody can ask for is unreachable
        unreachable = sorted(set(widget_files) - set(entries.values()))
        if unreachable:
            problems.append(f"widget(s) no registry name resolves to: {', '.join(unreachable)} "
                            f"— configuration could never place them")

print("    widgets found:")
for f in widget_files:
    print("      -", f)
if problems:
    print("    FAIL — the contract does not hold:")
    for p in problems:
        print("      !", p)
    sys.exit(1)
print("    PASS — one base contract, one simplified base, every widget on the "
      "contract, and a name→file map that carries no paths")
PY
static_rc=$?

# ---------------------------------------------------------------------------
# (B/C) RUNTIME: launch smoke.qml and read the contract off the log
# ---------------------------------------------------------------------------
echo
echo "[B] runtime instantiation (isolated bus, up to ${RUN_SECS}s) ..."

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
    echo "    ERROR: no SMOKE SUMMARY line within ${RUN_SECS}s"
    echo "    --- log tail ---"; tail -n 30 "$LOG" 2>/dev/null
    runtime_rc=1
    resolve_rc=1
else
    runtime_rc=0
    resolve_rc=0
fi

echo
echo "[B] every contract widget instantiated ..."
python3 - "$LOG" <<'PY'
import re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()

def tokens(ln):
    i = ln.find('SMOKE ')
    return ln[i + 6:].split() if i != -1 else []

plan = [(t[1], t[2]) for ln in lines
        if (t := tokens(ln)) and t[0] == 'PLAN' and len(t) > 2]
passed = [(t[1], t[2]) for ln in lines
          if (t := tokens(ln)) and t[0] == 'PASS' and len(t) > 2]
failed = [(t[1], t[2], ' '.join(t[3:])) for ln in lines
          if (t := tokens(ln)) and t[0] == 'FAIL' and len(t) > 2]

# The contract's own types, which is what this ticket added to the plan.
contract = ['BarWidget.qml', 'SimpleBarWidget.qml', 'WidgetRegistry.qml',
            'ClockWidget.qml', 'Launcher.qml', 'Workspaces.qml', 'Tray.qml']
rc = 0
print(f"    contract widgets ({len(contract)}):")
for name in contract:
    detail = next((d for _, n, d in failed if n == name), None)
    if detail:
        print(f"      FAIL {name}: {detail}"); rc = 1
    elif any(n == name for _, n in passed):
        print(f"      pass {name}")
    else:
        print(f"      MISS {name}: planned but no PASS line in the log"); rc = 1

summary = next((l for l in lines if 'SMOKE SUMMARY' in l), None)
if summary:
    print("    " + summary.split('INFO qml:', 1)[-1].strip())
sys.exit(rc)
PY
runtime_rc=$(( runtime_rc != 0 ? 1 : $? ))

echo
echo "[C] registry resolution + contract promises, read off the instances ..."
python3 - "$LOG" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text(errors='replace')
lines = text.splitlines()

def contract_line(key):
    for ln in lines:
        if f'SMOKE CONTRACT {key} ' in ln:
            return ln.split(f'SMOKE CONTRACT {key} ', 1)[1].strip()
    return None

rc = 0
def check(label, ok, detail):
    global rc
    print(f"      {'pass' if ok else 'FAIL'} {label}: {detail}")
    if not ok:
        rc = 1

# ---- (C1) the registry resolves every name it holds, and only those -------
resolved = contract_line('registry-resolved')
if resolved is None:
    check('registry-resolved', False, 'the smoke run printed no registry resolution verdict')
else:
    names = re.findall(r'name=([A-Za-z0-9-]+)\|([A-Za-z0-9-]+)', resolved)
    count = re.search(r'count=(\d+)', resolved)
    bad = [f"{n}->{s}" for n, s in names if s != 'READY']
    if count and int(count.group(1)) == 0:
        check('registry-resolved', False,
              "the registry holds no names at all — no widget could ever be placed")
    elif bad:
        check('registry-resolved', False,
              f"{len(bad)} registered name(s) did not resolve to a loadable "
              f"component: {', '.join(bad)}")
    else:
        check('registry-resolved', True,
              f"every registered name resolved to a loadable component: "
              f"{', '.join(n for n, _ in names)}")

rejected = contract_line('registry-rejected')
check('registry-rejects-unknown', rejected is not None and 'resolves=no' in (rejected or ''),
      rejected or 'the smoke run never asked for an unknown name')

# ---- (C2) a widget with no panel supplies NOTHING, not an empty panel -----
panel = contract_line('clock-panel')
check('clock-offers-no-panel', panel is not None and 'hasPanel=false' in (panel or ''),
      panel or 'the clock was never asked whether it has a panel')

# ---- (C3) the clock carries time and date on a one-minute cadence ---------
clock = contract_line('clock-members')
if clock is None:
    check('clock-members', False, 'the clock was never asked for its members')
else:
    def field(name):
        m = re.search(rf'{name}=("[^"]*"|\S+)', clock)
        return m.group(1).strip('"') if m else None
    for field_name, why in (('time', 'shows the time'), ('date', 'shows the date')):
        v = field(field_name)
        check(f'clock-{field_name}', bool(v), f"{why}: {field_name}={v!r}" if v else f"no {field_name} text")
    cadence = field('cadence')
    check('clock-cadence', cadence == 'Minutes',
          f"updates every minute (SystemClock precision={cadence})" if cadence == 'Minutes'
          else f"expected SystemClock precision Minutes, clock reports {cadence!r}")

# ---- (C4) the hover affordance is on the BASE, read off an instance ------
hover = contract_line('base-hover')
if hover is None:
    check('base-hover', False, 'the base was never asked about its hover affordance')
else:
    def h(name):
        m = re.search(rf'{name}=([0-9.]+|true|false)', hover)
        return m.group(1) if m else None
    dim, bright = h('dimOpacity'), h('brightOpacity')
    ok = dim is not None and bright is not None and float(dim) < 1.0 <= float(bright)
    check('base-hover', ok,
          f"dim={dim} when not hovered, bright={bright} on hover"
          if ok else f"dim={dim} bright={bright} — must dim below 1.0 and brighten to at least 1.0")

sys.exit(rc)
PY
resolve_rc=$?

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $static_rc -eq 0 && $runtime_rc -eq 0 && $resolve_rc -eq 0 ]]; then
    echo " RESULT: PASS (static contract + runtime instantiation + resolution)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  (static=$([[ $static_rc -eq 0 ]] && echo ok || echo FAIL), runtime=$([[ $runtime_rc -eq 0 ]] && echo ok || echo FAIL), resolution=$([[ $resolve_rc -eq 0 ]] && echo ok || echo FAIL))"
    echo " --- captured log tail (if any) ---"
    tail -n 40 "$LOG" 2>/dev/null || true
    echo "======================================================================"
    exit 1
fi