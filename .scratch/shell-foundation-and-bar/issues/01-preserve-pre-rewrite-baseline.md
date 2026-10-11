# 01: Preserve the pre-rewrite baseline

**What to build:** A tagged, restorable snapshot of the shell as it stands before the rewrite, plus a written record of how to launch it. As a maintainer I want to diff the rewrite against this and get back to a working desktop if the rewrite goes badly, without reconstructing how to run the old code from memory. The `pre-rewrite` tag already exists at the pre-rewrite commit; this ticket makes it trustworthy and usable rather than assuming it.

**Blocked by:** None (can start immediately).

**Status:** resolved


- [x] The pre-rewrite state is tagged, and the tag is verified to point at the pre-rewrite commit rather than assumed to.
- [x] The baseline record states how to launch the pre-rewrite shell, including the working directory and any required entrypoint path, so it can actually be run and not merely checked out.
- [x] The baseline record states how to restore from the tag, so recovery is a documented command rather than improvisation.
- [x] Restoring and re-tagging is confirmed to work, not just documented — the record is only trustworthy if it was exercised at least once.

## Comments

Implemented on branch `01-preserve-pre-rewrite-baseline`, merged to `feat/shell-foundation-and-bar`.

Correction to the facts I was given: the tag is **annotated**, not lightweight (tag object `ec90b71`, with a tagger and message), resolving to `77629f3`. Stronger than assumed, but the extra tag object is now recorded in `docs/pre-rewrite-baseline.md` so scripting against the tag does not trip over it.

`docs/pre-rewrite-baseline.md` records the launch command as `quickshell -p shell.qml` **from the root of a checkout of the tag** — `shell.qml`'s imports are directory-relative, so working directory matters. Both restore forms are documented (in-place `git switch --detach` and isolated `git worktree add --detach`), plus the observed log output and failure signatures.

`scripts/verify-pre-rewrite-baseline.sh` exercises the record: 28 checks covering tag identity/ancestry/tree, record claims, a live worktree restore, both launches, a fatal-error grep, and leak checks. Red showed 7 failures before the record existed; green 28/28.

Known limitation, recorded in the baseline doc: swaync owns `org.freedesktop.Notifications` on the live bus, so the baseline shell cannot own notifications while swaync runs. It warns and carries on. Verification launches were run under `dbus-run-session` with timeouts; waybar/hyprpaper/swayosd/swaync kept their original PIDs and no quickshell processes survived.

Note for whoever takes the "repository conventions" half of ticket 05: `scripts/` is a new top-level directory, and the AGENTS.md "No verification step" line was corrected here by ticket 03, not by this ticket.

- [ ] The pre-rewrite state is tagged, and the tag is verified to point at the pre-rewrite commit rather than assumed to.
- [ ] The baseline record states how to launch the pre-rewrite shell, including the working directory and any required entrypoint path, so it can actually be run and not merely checked out.
- [ ] The baseline record states how to restore from the tag, so recovery is a documented command rather than improvisation.
- [ ] Restoring and re-tagging is confirmed to work, not just documented — the record is only trustworthy if it was exercised at least once.
