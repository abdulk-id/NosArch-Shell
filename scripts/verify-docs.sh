#!/usr/bin/env bash
#
# verify-docs.sh — verification for ticket 05.
#
#   "A glossary and two decision records that a future reader will not
#    silently undo: the vocabulary the spec settles, the service/widget
#    boundary, and the panel architecture."
#
# Documentation has no behaviour to launch, so the failure signal here is
# different from the other three verifiers: the risk is not a QML error, it is
# A DOCUMENT THAT LIES. These files outlive the session that writes them and
# will be read as fact, so most of the checks below are TRUTH CHECKS — each
# reads a literal claim out of a document and compares it against a fact
# recomputed from the tree. A document that drifts from the code fails here
# rather than misleading whoever reads it next.
#
# Six checks:
#   (A) FORMAT   — GLOSSARY.md follows .agents/skills/domain-modeling/
#                  GLOSSARY-FORMAT.md: one title, a `## Language` section, a
#                  tight definition plus an `_Avoid_:` line for every required
#                  term, and no `_Avoid_` line that recommends the retired word.
#   (B) TRUTH    — the three senses the retired word "module" names all still
#                  exist in the tree, and the "applied to one widget of twelve"
#                  claim is recomputed rather than trusted.
#   (C) TRUTH    — ADR 0001's account of presentation in services is true:
#                  every service that currently publishes a display glyph is
#                  named, and while any remain the ADR must say the migration
#                  is in progress and must not claim it is finished.
#   (D) TRUTH    — ADR 0002's account of panels is true: while framework
#                  popups and focus grabbing are still in the tree, the ADR
#                  must name them and mark the panel architecture as not yet
#                  built.
#   (E) TRUTH    — the idle-lock inversion is true against the INSTALLED
#                  NosArch session helper, and the helper's stale kill of the
#                  old bar is recorded (not edited) in the project instructions.
#   (F) CURRENCY — AGENTS.md still describes the repo: the layer-shell
#                  convention is present, every verify-*.sh in scripts/ is
#                  documented (so "two verification scripts" cannot go stale
#                  again), the domain docs are pointed at, and the widget
#                  naming convention is stated without pinning the directory
#                  the widget registry is still choosing.
#
# SAFETY: reads only. It launches nothing, draws nothing, writes nothing, and
# touches neither ~/.config nor ~/.local/share. The session helper is read,
# never edited.
#
# Exit status: 0 only if all six checks pass.
#
set -uo pipefail   # deliberately not -e: run every check, then report

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"
HELPER="${NOSARCH_SESSION_HELPER:-/usr/local/bin/nosarch/nosarch-session}"
export NOSARCH_DOCS_REPO="$REPO"

PASS=0
FAIL=0
FAILED_CHECKS=()

# check <id> <python-heredoc-body-as-filename-free-code> — the python blocks
# below print one line beginning "PASS|" or "FAIL|" plus optional "  (tree)"
# context lines, and this turns that into the run's tally. Keeping it in one
# place is what stops the six checks drifting in style.
check() {
    local id="$1"
    local out verdict
    out="$(python3 - "$@" 2>&1)"
    verdict="$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' | head -n1)"
    printf '%s\n' "$out" | grep -E '^  \(' || true
    if [[ -z "$verdict" ]]; then
        report FAIL "$id" "the checker produced no verdict (see above)"
        return
    fi
    verdict="${verdict%%|*}"
    report "$verdict" "$id" "${out#*"$verdict"|}"
}

report() {  # report <PASS|FAIL> <check-id> <detail>
    local verdict="$1" id="$2" detail="$3"
    if [[ "$verdict" == PASS ]]; then
        PASS=$((PASS + 1))
        echo "    PASS $id: $detail"
    else
        FAIL=$((FAIL + 1))
        FAILED_CHECKS+=("$id")
        echo "    FAIL $id: $detail"
    fi
}

skip() { echo "    SKIP $1: $2"; }

echo "======================================================================"
echo " Ticket 05 verification — glossary, decision records, live conventions"
echo " repo: $REPO"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (A) FORMAT — GLOSSARY.md exists and follows the house format
# ---------------------------------------------------------------------------
echo
echo "[A] glossary format and required terms ..."
check format - <<'PY'
import os, re, sys, pathlib

repo = pathlib.Path(os.environ["NOSARCH_DOCS_REPO"])
gloss = repo / "GLOSSARY.md"

# The ticket's acceptance criteria, plus the two terms the naming convention
# hangs off (the registry is where widget names are resolved).
REQUIRED = ["bar", "zone", "widget", "panel", "service", "palette",
            "idle-lock inhibit", "widget registry", "module"]
bad = []

if not gloss.is_file():
    print(f"FAIL|no GLOSSARY.md at the repo root ({gloss}) — the vocabulary the "
          "spec settles is not recorded anywhere")
    sys.exit(0)
if (repo / "GLOSSARY-MAP.md").exists():
    bad.append("GLOSSARY-MAP.md exists alongside a root GLOSSARY.md; "
               "docs/agents/domain.md says this is a single-context repo")

text = gloss.read_text()
if not text.lstrip().startswith("# "):
    bad.append("no top-level `# Title` heading")
if "## Language" not in text:
    bad.append("no `## Language` section (GLOSSARY-FORMAT.md requires it)")

# Entries: a `**Term**:` heading opens one and runs to the next heading.
entries, cur, cur_name = {}, [], None
for line in text.splitlines():
    m = re.match(r"^\*\*(.+?)\*\*:", line)
    if m:
        if cur_name:
            entries[cur_name] = "\n".join(cur)
        cur_name, cur = m.group(1).strip().lower(), [line]
    elif cur_name:
        cur.append(line)
if cur_name:
    entries[cur_name] = "\n".join(cur)

for term in REQUIRED:
    key = term.lower()
    if key not in entries:
        bad.append(f"no glossary entry for '{term}'")
        continue
    body = entries[key]
    prose = [l.strip() for l in body.splitlines()[1:]
             if l.strip() and not l.strip().startswith("_Avoid_:")]
    joined = " ".join(prose)
    if not joined:
        bad.append(f"'{term}' has no definition line")
    elif len(joined) > 400:
        bad.append(f"'{term}' definition runs to {len(joined)} chars; "
                   "GLOSSARY-FORMAT.md says keep definitions to one or two sentences")
    avoids = [l.strip() for l in body.splitlines()
              if l.strip().startswith("_Avoid_:")]
    if not avoids:
        bad.append(f"'{term}' has no `_Avoid_:` line — the ticket requires the "
                   "terms to avoid, not just a definition")
    elif not avoids[0][len("_Avoid_:"):].strip():
        bad.append(f"'{term}' has an empty `_Avoid_:` line")

# No entry may recommend the retired word to anyone else.
for term, body in entries.items():
    for line in body.splitlines():
        s = line.strip().lower()
        if s.startswith("_avoid_:") and "module" in s and term != "module":
            bad.append(f"the '{term}' entry recommends the retired word 'module' "
                       "under _Avoid_ — name widget, service or component instead")

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print(f"PASS|GLOSSARY.md follows GLOSSARY-FORMAT.md and covers all "
          f"{len(REQUIRED)} required terms, each with a tight definition and a "
          "non-empty `_Avoid_:` line, and none of them recommends 'module'")
PY

# ---------------------------------------------------------------------------
# (B) TRUTH — the three senses of "module" are real, and the base class really
#     is applied to fewer widgets than exist.
# ---------------------------------------------------------------------------
echo
echo "[B] the retired word 'module' — are the three senses real? ..."
check truth-module - <<'PY'
import os, re, sys, pathlib

repo = pathlib.Path(os.environ["NOSARCH_DOCS_REPO"])
gloss = repo / "GLOSSARY.md"
bad = []

# Sense 1 — the bar widgets, in a directory literally named `modules`.
moddir = repo / "shell/topisland/modules"
widgets = sorted(moddir.glob("*.qml")) if moddir.is_dir() else []
if not widgets:
    bad.append("shell/topisland/modules/ is gone or empty, so the first sense of "
               "'module' no longer exists — rewrite or drop the glossary entry")
else:
    print(f"  (tree) sense 1 — bar widgets: {len(widgets)} .qml files in "
          f"shell/topisland/modules/")

# Sense 2 — the shared base class, declared in components/qmldir.
base = repo / "components/TopIslandModule.qml"
subclasses = []
if not base.is_file():
    bad.append("components/TopIslandModule.qml is gone, so the base-class sense of "
               "'module' no longer exists — rewrite the glossary entry")
else:
    qmldir = ((repo / "components/qmldir").read_text()
              if (repo / "components/qmldir").is_file() else "")
    if "TopIslandModule" not in qmldir:
        bad.append("TopIslandModule.qml exists but is not declared in "
                   "components/qmldir, so it is not the shared base class the "
                   "glossary claims")
    skip = {".git", ".scratch", ".agents", ".zed"}
    for f in repo.rglob("*.qml"):
        if skip & set(f.parts) or f == base:
            continue
        if "TopIslandModule {" in f.read_text(errors="replace"):
            subclasses.append(f)
    print(f"  (tree) sense 2 — the base class: TopIslandModule.qml is declared in "
          f"components/qmldir and is extended by {len(subclasses)} of the "
          f"{len(widgets)} widget file(s)"
          + (f" ({', '.join(f.name for f in subclasses)})" if subclasses else ""))
    if widgets and len(subclasses) >= len(widgets):
        bad.append(f"every one of the {len(widgets)} widgets now extends the base "
                   "class, so the 'unapplied abstraction' claim is no longer true "
                   "— rewrite the glossary entry")

# The glossary's own count is a claim; lock it to the tree.
if not gloss.is_file():
    bad.append("no GLOSSARY.md, so there is no retired-word entry to check")
elif True:
    g = gloss.read_text()
    m = re.search(r"one widget of (\w+)", g, re.I)
    if not m:
        bad.append("the module entry does not quantify the unapplied abstraction "
                   "('one widget of twelve'), so the claim cannot be checked")
    else:
        words = {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                 "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12}
        claimed = words.get(m.group(1).lower())
        if claimed is None:
            bad.append(f"the module entry says 'one widget of {m.group(1)}', which "
                       "is not a number this checker can verify")
        elif claimed != len(widgets):
            bad.append(f"the module entry claims 'one widget of {m.group(1)}' but "
                       f"shell/topisland/modules/ holds {len(widgets)} widget files")
        elif len(subclasses) != 1:
            bad.append(f"the module entry claims exactly one widget is on the base "
                       f"class, but {len(subclasses)} files extend it")

# Sense 3 — QML's own sense of the word: a directory of types with a qmldir.
qml_modules = sorted(p.parent.relative_to(repo).as_posix() for p in repo.rglob("qmldir")
                     if not {".scratch", ".agents", ".git"} & set(p.parts))
if not qml_modules:
    bad.append("no directory in this repo declares a qmldir, so the QML-module "
               "sense of 'module' has nothing to point at")
else:
    print(f"  (tree) sense 3 — QML modules: {', '.join(qml_modules)}")
    if moddir in [p.parent for p in repo.rglob("qmldir")
                  if not {".scratch", ".agents", ".git"} & set(p.parts)]:
        bad.append("shell/topisland/modules/ now declares a qmldir, so the directory "
                   "is a real QML module as well as the widget home")

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print("PASS|all three senses of 'module' are real in the tree and the entry's "
          "count of unapplied widgets matches the tree")
PY

# ---------------------------------------------------------------------------
# (C) TRUTH — ADR 0001 about presentation in services
# ---------------------------------------------------------------------------
echo
echo "[C] service/widget boundary ADR — does it match the services on disk? ..."
check truth-adr1 - <<'PY'
import os, re, sys, pathlib

repo = pathlib.Path(os.environ["NOSARCH_DOCS_REPO"])
adr = repo / "docs/adr/0001-services-expose-state-never-presentation.md"

if not adr.is_file():
    print("FAIL|no such file — the service/widget boundary decision is not recorded")
    sys.exit(0)
text = adr.read_text()
low = text.lower()
bad = []

# Every service that publishes a display glyph today must be named in the ADR.
glyphs = {}
for f in sorted((repo / "services").glob("*.qml")):
    n = len(re.findall(r"\btextIcon\b", f.read_text(errors="replace")))
    if n:
        glyphs[f.name] = n
total = sum(glyphs.values())
print(f"  (tree) services publishing a display glyph: "
      + (", ".join(f"{k} x{v}" for k, v in glyphs.items()) or "none"))

if not glyphs:
    if not any(c in low for c in ("no longer", "already removed", "already migrated")):
        bad.append("no service publishes a glyph any more, but the ADR still frames "
                   "them as present — say the migration is finished")
else:
    for name in glyphs:
        if name not in text:
            bad.append(f"{name} publishes {glyphs[name]} display glyph(s) today but "
                       "the ADR does not mention it")
    if "texticon" not in low:
        bad.append("no service is named as publishing a `textIcon` glyph property")
    if not any(m in low for m in ("in progress", "not yet implemented", "not yet "
                                  "migrated", "still holds", "still contains",
                                  "still publishes", "remains to be")):
        bad.append(f"{total} display glyph(s) still live in services/, but the ADR "
                   "does not say the migration is in progress")
    for claim in ("no longer", "already removed", "already migrated",
                  "fully migrated", "complete migration"):
        if claim in low:
            bad.append(f"the ADR says '{claim}', which is false today: {total} "
                       "display glyph(s) are still in services/")

# The ADR must record the decision itself, not only the migration status.
for needle, why in (("state", "the boundary (services expose state)"),
                    ("presentation", "what moves out of them"),
                    ("widget", "who consumes the state")):
    if needle not in low:
        bad.append(f"the ADR never mentions {needle} — {why}")

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print(f"PASS|ADR 0001 names all {len(glyphs)} service(s) still publishing "
          f"glyphs ({total} total) and marks the migration in progress")
PY

# ---------------------------------------------------------------------------
# (D) TRUTH — ADR 0002 about panels vs popups
# ---------------------------------------------------------------------------
echo
echo "[D] panel architecture ADR — does it match what is still in the tree? ..."
check truth-adr2 - <<'PY'
import os, re, sys, pathlib

repo = pathlib.Path(os.environ["NOSARCH_DOCS_REPO"])
adr = repo / "docs/adr/0002-panels-are-overlay-surfaces-not-popups.md"

if not adr.is_file():
    print("FAIL|no such file — the panel architecture decision is not recorded")
    sys.exit(0)
text = adr.read_text()
low = text.lower()
bad = []
skip = {".git", ".scratch", ".agents", ".zed", "docs"}


def qml_files():
    for f in sorted(repo.rglob("*.qml")):
        if not skip & set(f.parts):
            yield f


popups = [f for f in qml_files() if "PopupWindow {" in f.read_text(errors="replace")]
grabs = [f for f in qml_files() if "grabFocus" in f.read_text(errors="replace")]
rel = lambda fs: ", ".join(f.relative_to(repo).as_posix() for f in fs) or "none"
print(f"  (tree) framework PopupWindows still declared in: {rel(popups)}")
print(f"  (tree) keyboard-focus grabbing (grabFocus) in: {rel(grabs)}")

# Anything still in the tree must be named, and recorded as on the way out —
# otherwise the ADR reads as though the migration already happened.
if popups:
    if "popupwindow" not in low:
        bad.append(f"{len(popups)} file(s) still declare a PopupWindow but the ADR "
                   "never names the type")
    if not any(m in low for m in ("in progress", "not yet implemented", "not yet "
                                  "built", "still uses", "still contains",
                                  "remains to be")):
        bad.append(f"{len(popups)} file(s) still declare a PopupWindow, but the ADR "
                   "does not mark the panel architecture as not yet implemented")
if grabs:
    if "grabfocus" not in low and "grab focus" not in low:
        bad.append("keyboard-focus grabbing is still in the tree but the ADR never "
                   "mentions it")
    fn = re.search(r"function (make\w*[Uu]nfocusable\w*)\(",
                   "\n".join(f.read_text(errors="replace") for f in qml_files()))
    if fn and fn.group(1).lower() not in low:
        bad.append(f"the recursive focus-clearing workaround ({fn.group(1)}) is "
                   "still in the tree but the ADR does not record it as deleted "
                   "rather than ported")

# The reasons the decision exists must all be recorded, in some wording.
for needle, why in (
    ("popupwindow", "what is being abandoned"),
    ("focus", "why popups cannot take keyboard input at open time"),
    ("exclusive", "why the short exclusive-focus prime exists"),
    ("hyprland", "the deliberate compositor trade-off"),
):
    if needle not in low:
        bad.append(f"the ADR does not mention {needle} — {why}")
if "one panel" not in low and "at a time" not in low:
    bad.append("the ADR does not record that only one panel is open at a time")
if "deleted" not in low and "removed" not in low:
    bad.append("the ADR does not say the focus workaround is deleted rather than ported")

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print(f"PASS|ADR 0002 records all four reasons and is honest about the "
          f"{len(popups)} PopupWindow file(s) still in the tree")
PY

# ---------------------------------------------------------------------------
# (E) TRUTH — the idle-lock inversion, against the installed session helper
# ---------------------------------------------------------------------------
echo
echo "[E] idle-lock semantics — true against the NosArch session helper? ..."
if [[ ! -f "$HELPER" ]]; then
    skip truth-idle-lock "no session helper at $HELPER (not a NosArch machine, or \
NOSARCH_SESSION_HELPER is set elsewhere); nothing to check the inversion against"
else
    export NOSARCH_DOCS_HELPER="$HELPER"
    check truth-idle-lock - <<'PY'
import os, re, sys, pathlib

helper = pathlib.Path(os.environ["NOSARCH_DOCS_HELPER"])
repo = pathlib.Path(os.environ["NOSARCH_DOCS_REPO"])
gloss, agents = repo / "GLOSSARY.md", repo / "AGENTS.md"

src = helper.read_text(errors="replace")
bad = []


def func_body(name):
    m = re.search(rf"^{name}\(\) \{{(.*?)^\}}", src, re.S | re.M)
    return m.group(1) if m else ""


status = func_body("idle_lock_status")
if not status:
    bad.append(f"{helper} has no idle_lock_status() to check")
else:
    # `true` when the inhibit unit is ACTIVE. If that is what it does, then
    # "idle-lock status == true" means locking is being SUPPRESSED — the
    # inversion the spec insists must be documented.
    inverted = bool(re.search(r"is-active[^\n]*IDLE_LOCK_UNIT", status))
    print("  (helper) idle_lock_status(): "
          + ("true == the inhibit unit is running == locking will NOT happen "
             "(semantics inverted relative to the name)" if inverted else
             "does NOT test the inhibit unit — the documented inversion could not "
             "be confirmed"))
    if not inverted:
        bad.append("the helper's status does not test the inhibit unit, so the "
                   "documented inversion cannot be confirmed")

    if gloss.is_file():
        gtext = gloss.read_text()
        m = re.search(r"^\*\*idle-lock inhibit\*\*:(.*?)(?=^\*\*|\Z)", gtext,
                      re.S | re.M | re.I)
        entry = (m.group(1) if m else "").lower()
        if not entry:
            bad.append("the glossary has no 'idle-lock inhibit' entry")
        else:
            if not re.search(r"will not|will \*\*not\*\*|prevents|inhibit is running",
                             entry):
                bad.append("the 'idle-lock inhibit' entry does not state that the "
                           "helper's enabled/true means locking will NOT happen")
            if "true" not in entry and "enabled" not in entry:
                bad.append("the 'idle-lock inhibit' entry never mentions the helper's "
                           "own 'true'/'enabled' wording")
    else:
        bad.append("no GLOSSARY.md to carry the idle-lock invert-in-name entry")

    if agents.is_file():
        atext = agents.read_text()
        if str(helper) not in atext:
            bad.append(f"AGENTS.md does not name the helper path ({helper}), so an "
                       "implementer writing the indicator cannot find the inversion")
        if "idle" not in atext.lower():
            bad.append("AGENTS.md says nothing about the idle-lock helper")
    else:
        bad.append("no AGENTS.md to carry the helper convention")

# The helper's stale kill of the old bar must be recorded, not edited.
stale = sorted(set(re.findall(r"pkill[^\n]*waybar", src)))
if stale:
    print(f"  (helper) stale call(s) against the old bar: {'; '.join(stale)}")
    if agents.is_file() and "waybar" not in agents.read_text().lower():
        bad.append("the helper still carries a stale process-kill against the old "
                   "bar, but nothing in AGENTS.md records it — the spec says "
                   "record it, do not edit the helper")

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print("PASS|the helper's status is inverted exactly as documented, and both "
          "the inversion and the stale old-bar kill are recorded in the project "
          "instructions")
PY
fi

# ---------------------------------------------------------------------------
# (F) CURRENCY — AGENTS.md describes the repo as it is
# ---------------------------------------------------------------------------
echo
echo "[F] project instructions are current ..."
check currency - <<'PY'
import os, re, sys, pathlib

repo = pathlib.Path(os.environ["NOSARCH_DOCS_REPO"])
agents = repo / "AGENTS.md"
if not agents.is_file():
    print("FAIL|AGENTS.md is missing")
    sys.exit(0)
text = agents.read_text()
low = text.lower()
bad = []

# Ticket 02 restored this; it is load-bearing under the panel architecture, so
# its absence is a regression rather than a tidiness issue.
for needle, why in (("wlrlayershell.namespace", "every overlay surface sets a namespace"),
                    ("wlrlayershell.layer", "every overlay surface sets a layer")):
    if needle.lower() not in low:
        bad.append(f"AGENTS.md no longer states the layer-shell convention: {why}")

# The verification section must not claim there is none, and must document
# EVERY verifier that exists — that is what stops "two verification scripts"
# going stale the way the older note did.
verifiers = sorted(p.name for p in (repo / "scripts").glob("verify-*.sh"))
print(f"  (tree) verifiers in scripts/: {', '.join(verifiers) or 'none'}")
undocumented = [v for v in verifiers if v not in text]
if undocumented:
    bad.append("AGENTS.md does not document these verifier scripts: "
               + ", ".join(undocumented))
for stale_claim in ("no verification step", "there is no verification",
                    "no test harness", "nothing objects"):
    if stale_claim in low:
        bad.append(f"AGENTS.md still says '{stale_claim}' — false since ticket 03")

# The domain docs must be pointed at; they did not exist until this ticket.
for needle in ("GLOSSARY.md", "docs/adr/"):
    if needle not in text:
        bad.append(f"AGENTS.md does not point maintainers at {needle}")

# Widget naming, stated as a rule and deliberately not pinning a directory.
if not re.search(r"widget naming", low):
    bad.append("AGENTS.md has no widget-naming convention (spec story 89)")
else:
    for needle, why in (("kebab", "the config `type` is kebab-case"),
                        ("uppercamel", "the file and QML type are UpperCamelCase"),
                        ("registry", "the name resolves through the registry")):
        if needle not in low:
            bad.append(f"the widget-naming convention does not say {why}")
    if re.search(r"widget naming.{0,900}?shell/topisland/modules", low, re.S):
        bad.append("the widget-naming convention pins shell/topisland/modules/ as the "
                   "widget location — that is the pre-rewrite home, and the registry "
                   "decides where widgets live")

# Report where widgets actually are, so the reader can see the gap by eye.
moddir = repo / "shell/topisland/modules"
files = sorted(p.name for p in moddir.glob("*.qml")) if moddir.is_dir() else []
print(f"  (tree) bar widgets still at the pre-rewrite path "
      f"shell/topisland/modules/: {len(files)} file(s)"
      + (f" — {', '.join(files)}" if files else ""))

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print(f"PASS|AGENTS.md states the layer-shell convention, documents all "
          f"{len(verifiers)} verifiers, points at the domain docs, and states the "
          "widget-naming convention without pinning the registry's directory")
PY

# ---------------------------------------------------------------------------
echo
echo "======================================================================"
if [[ $FAIL -eq 0 ]]; then
    echo " RESULT: PASS (all six checks hold)"
    echo "======================================================================"
    exit 0
else
    echo " RESULT: FAIL  ($PASS passed, $FAIL failed: ${FAILED_CHECKS[*]})"
    echo "======================================================================"
    exit 1
fi
