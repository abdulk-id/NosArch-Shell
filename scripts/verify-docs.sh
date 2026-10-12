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
#   (B) TRUTH    — the pre-rewrite bar the retired word "module" named is gone,
#                  the glossary records that retirement honestly, and QML's own
#                  module directories still exist where the entry says they do.
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

# check <id> <python-heredoc> — the python blocks print one or more lines
# beginning "PASS|" or "FAIL|" plus optional "  (tree)" context lines. This
# turns those into the run's tally: any FAIL anywhere makes the whole check
# fail, and every verdict's detail is reported. Keeping it in one place is
# what stops the six checks drifting in style.
check() {
    local id="$1" out verdict details
    out="$(python3 - "$@" 2>&1)"
    printf '%s\n' "$out" | grep -E '^  \(' || true
    details="$(printf '%s\n' "$out" | sed -n -E 's/^(PASS|FAIL)\|//p')"
    if printf '%s\n' "$out" | grep -q '^FAIL|'; then
        verdict=FAIL
    elif [[ -n "$(printf '%s\n' "$out" | sed -n -E 's/^PASS\|//p')" ]]; then
        verdict=PASS
    else
        verdict=""
    fi
    if [[ -z "$verdict" ]]; then
        report FAIL "$id" "the checker produced no verdict (see above)"
        return
    fi
    report "$verdict" "$id" "$(printf '%s\n' "$details" \
        | awk 'BEGIN{ORS=""} {print (n++ ? "; " : "") $0}')"
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
    # Split the entry into its definition and its `_Avoid_` list: an `_Avoid_`
    # entry wraps onto continuation lines, so everything from the marker to the
    # next heading belongs to the avoid list, not the definition.
    body = entries[key]
    lines = [l.strip() for l in body.splitlines()]
    cut = next((i for i, l in enumerate(lines) if l.startswith("_Avoid_:")), len(lines))
    prose = [l for l in lines[1:cut] if l]
    avoid = [l for l in lines[cut:] if l]
    joined = " ".join(prose)
    if not joined:
        bad.append(f"'{term}' has no definition line")
    elif len(joined) > 400:
        bad.append(f"'{term}' definition runs to {len(joined)} chars; "
                   "GLOSSARY-FORMAT.md says keep definitions to one or two sentences")
    if not avoid:
        bad.append(f"'{term}' has no `_Avoid_:` line — the ticket requires the "
                   "terms to avoid, not just a definition")
    elif not avoid[0][len("_Avoid_:"):].strip():
        bad.append(f"'{term}' has an empty `_Avoid_:` line")
    # Naming the retired word AS an avoided synonym is the point; using it as
    # this entry's own word is the thing that must not happen.
    if term != "module" and re.search(r"\bmodules?\b", joined, re.I):
        bad.append(f"the '{term}' definition uses the retired word 'module'")
    if term == "module" and not re.search(r"retired", joined, re.I):
        bad.append("the 'module' entry does not say the word is retired")
    if term == "module":
        # Retiring a word without saying what to use instead just leaves a hole.
        named = [t for t in ("widget", "service", "component", "base class",
                             "contract") if t in " ".join(avoid).lower()]
        if len(named) < 2:
            bad.append(f"the 'module' entry names only {len(named)} replacement "
                       "term(s) in its `_Avoid_:` list — retiring a word without "
                       "saying what to use instead just leaves a hole")

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
echo "[B] the retired word 'module' — is the pre-rewrite bar gone and the entry honest? ..."
check truth-module - <<'PY'
import os, re, sys, pathlib

repo = pathlib.Path(os.environ["NOSARCH_DOCS_REPO"])
gloss = repo / "GLOSSARY.md"
bad = []

moddir = repo / "shell/topisland/modules"
if moddir.is_dir() and any(moddir.glob("*.qml")):
    bad.append("shell/topisland/modules/ still holds widget files — ticket 18 deletes "
               "the pre-rewrite bar wholesale")
elif (repo / "shell/topisland/TopIsland.qml").is_file():
    bad.append("shell/topisland/TopIsland.qml still exists — the pre-rewrite bar is "
               "not retired")
else:
    print("  (tree) pre-rewrite bar: shell/topisland/ is gone")

base = repo / "components/TopIslandModule.qml"
if base.is_file():
    bad.append("components/TopIslandModule.qml still exists — the pre-rewrite widget "
               "base is not retired")
else:
    print("  (tree) pre-rewrite base: TopIslandModule.qml is gone")

if not gloss.is_file():
    bad.append("no GLOSSARY.md, so there is no retired-word entry to check")
else:
    g = gloss.read_text()
    if not re.search(r"retired", g, re.I):
        bad.append("the module entry does not say the word is retired")
    if "shell/topisland/modules/" not in g:
        bad.append("the module entry no longer names shell/topisland/modules/, so it "
                   "does not record what was deleted")
    if "shell/widgets/" not in g:
        bad.append("the module entry does not point at shell/widgets/ as the widget home")

qml_modules = sorted(p.parent.relative_to(repo).as_posix() for p in repo.rglob("qmldir")
                     if not {".scratch", ".agents", ".git"} & set(p.parts))
if not qml_modules:
    bad.append("no directory in this repo declares a qmldir, so the QML-module "
               "sense of 'module' has nothing to point at")
else:
    print(f"  (tree) QML module directories: {', '.join(qml_modules)}")

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print("PASS|the pre-rewrite bar is gone, widgets live on the contract, and the "
          "glossary records the retirement")
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
# Prose wraps, so needles must not depend on where a line happens to break.
low = re.sub(r"\s+", " ", text.lower())
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
    # Unambiguous completion phrasings only. A phrase like "the services are
    # clean" cannot go here: a negation ("must not be read as saying the
    # services are clean") contains it too, and a substring test cannot tell
    # the two apart. The positive in-progress requirement above is what
    # actually carries this check.
    for claim in ("no longer", "already removed", "already migrated",
                  "fully migrated", "complete migration", "has been moved",
                  "have been moved", "presentation has been moved"):
        if claim in low:
            bad.append(f"the ADR says '{claim}', which is false today: {total} "
                       "display glyph(s) are still in services/")

# The decision must record the decision itself, not only the migration status.
for needle, why in (("state", "the boundary (services expose state)"),
                    ("presentation", "what moves out of them"),
                    ("widget", "who consumes the state")):
    if needle not in low:
        bad.append(f"the ADR never mentions {needle} — {why}")

# A count in prose is the easiest thing to get wrong and the hardest for a
# reader to notice, so lock it to the tree while the glyphs are still there.
NUMBERS = {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
           "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
           "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
           "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
           "one": 1, "zero": 0}
if glyphs:
    sites = []
    for f in sorted(repo.rglob("*.qml")):
        rel = f.relative_to(repo).parts
        if rel[0] == "services" or {".git", ".scratch", ".agents", ".zed"} & set(rel):
            continue
        sites += re.findall(r"^\s*(?!.*(?:function|property)\s+\w+\s+textIcon\b)"
                            r".*\btextIcon\b.*$",
                            f.read_text(errors="replace"), re.M)
    print(f"  (tree) call sites consuming a service glyph: {len(sites)}")
    m = re.search(r"\b(" + "|".join(NUMBERS) + r") call sites?\b", low)
    if not m:
        bad.append(f"the ADR does not state how many call sites consume the glyphs "
                   f"({len(sites)} of them) — an unstated count is a count nobody "
                   "checks")
    elif NUMBERS[m.group(1)] != len(sites):
        bad.append(f"the ADR says '{m.group(1)} call sites' but the tree has "
                   f"{len(sites)}")

if bad:
    print("FAIL|" + "; ".join(bad))
else:
    print(f"PASS|ADR 0001 names all {len(glyphs)} service(s) still publishing "
          f"glyphs ({total} total), marks the migration in progress, and its "
          "call-site count matches the tree")

# The ADR offers a mechanical test for its own boundary — a service must not
# import the palette. Enforce it, because that is the one thing about this
# decision that can be checked without reading the prose.
offenders = [f.name for f in sorted((repo / "services").glob("*.qml"))
             if re.search(r'import\s+"[^"]*ui"\s+as\s+\w+|UI\.Colors|UI\.Fonts',
                          f.read_text(errors="replace"))]
if offenders:
    print("FAIL|a service imports the palette, which ADR 0001 names as the "
          "mechanical test for the boundary: " + ", ".join(offenders))
else:
    print("PASS|no service imports the palette, as ADR 0001 requires")
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
low = re.sub(r"\s+", " ", text.lower())   # prose wraps; needles must not care
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
    # Name the files themselves, so whoever implements the panels knows what to
    # delete. Mirrors check (C), which names the services still holding glyphs.
    for f in popups:
        if f.name not in text:
            bad.append(f"{f.relative_to(repo).as_posix()} still declares a "
                       "PopupWindow but the ADR does not name the file")
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

# The four reasons the decision exists must all be recorded. The needles are
# deliberately specific: "focus" appears everywhere in this subject, so a bare
# mention of it proves nothing.
for needle, why in (
    ("popupwindow", "what is being abandoned"),
    ("hover", "why popups cannot take keyboard input until clicked or hovered"),
    ("pointer event", "why exclusive focus alone would break clicks on other outputs"),
    ("hyprland", "the deliberate compositor trade-off"),
):
    if needle not in low:
        bad.append(f"the ADR does not mention {needle} — {why}")
if "one panel" not in low and "at a time" not in low:
    bad.append("the ADR does not record that only one panel is open at a time")
# The claim is specifically "deleted, not ported". Checking for a stray
# "deleted" or "removed" anywhere would pass on unrelated wording.
if "rather than ported" not in low and "not ported" not in low:
    bad.append("the ADR does not say the focus workaround is deleted rather than "
               "ported")

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
            # Naming the helper is not enough; the instruction has to carry the
            # inversion, because that is the part a reader gets wrong.
            if not re.search(r"will \*{0,2}not\*{0,2} lock", atext, re.I):
                bad.append("AGENTS.md names the helper but never says that its "
                           "enabled/true means the machine will NOT lock")
            if not re.search(r"inhibit", atext, re.I):
                bad.append("AGENTS.md's idle-lock convention does not say the words "
                           "name the inhibit rather than the locking")
    else:
        bad.append("no AGENTS.md to carry the helper convention")

# The helper's stale kill of the old bar must be recorded, not edited.
stale = sorted(set(re.findall(r"pkill[^\n]*waybar", src)))
if stale:
    print(f"  (helper) stale call(s) against the old bar: {'; '.join(stale)}")
    # "waybar" alone is too weak — the record has to name the kill itself.
    if agents.is_file():
        alow = re.sub(r"\s+", " ", agents.read_text().lower())
        if "pkill" not in alow or "waybar" not in alow:
            bad.append("the helper still carries a stale `pkill … waybar` against the "
                       "old bar, but AGENTS.md does not record it — the spec says "
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
low = re.sub(r"\s+", " ", text.lower())   # prose wraps; needles must not care
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
# Each one must be a BULLET of its own, not merely named somewhere: a passing
# mention in a summary line documents nothing about what the script checks.
bulleted = set(re.findall(r"^- `(?:scripts/)?([A-Za-z0-9._-]+\.sh)`",
                          text, re.M))
undocumented = [v for v in verifiers if v not in bulleted]
if undocumented:
    bad.append("AGENTS.md has no bullet describing these verifier scripts: "
               + ", ".join(undocumented))
for orphan in sorted(b for b in bulleted if b.startswith("verify-")
                     and b not in verifiers):
    bad.append(f"AGENTS.md documents {orphan}, which is not in scripts/")
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

# Report where widgets actually are.
wdir = repo / "shell/widgets"
wfiles = sorted(p.name for p in wdir.glob("*.qml") if p.name not in ("BarWidget.qml", "SimpleBarWidget.qml", "WidgetRegistry.qml")) if wdir.is_dir() else []
print(f"  (tree) contract widgets in shell/widgets/: {len(wfiles)} file(s)")

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
