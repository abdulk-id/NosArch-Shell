# 01: Preserve the pre-rewrite baseline

**What to build:** A tagged, restorable snapshot of the shell as it stands before the rewrite, plus a written record of how to launch it. As a maintainer I want to diff the rewrite against this and get back to a working desktop if the rewrite goes badly, without reconstructing how to run the old code from memory. The `pre-rewrite` tag already exists at the pre-rewrite commit; this ticket makes it trustworthy and usable rather than assuming it.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The pre-rewrite state is tagged, and the tag is verified to point at the pre-rewrite commit rather than assumed to.
- [ ] The baseline record states how to launch the pre-rewrite shell, including the working directory and any required entrypoint path, so it can actually be run and not merely checked out.
- [ ] The baseline record states how to restore from the tag, so recovery is a documented command rather than improvisation.
- [ ] Restoring and re-tagging is confirmed to work, not just documented — the record is only trustworthy if it was exercised at least once.