---
id: you-review-solo
title: Nobody reviews your Harborlight changes
type: feedback
status: current
tags: [harborlight, review, working-style]
source: you (stated 2026-04-02, restated 2026-06-30)
created: 2026-04-02
updated: 2026-06-30
verified_on: 2026-06-30
confidence: high
---

You are the only person who maintains the Harborlight backend. Nothing you merge is read by another engineer before it ships.

**Why:** Rye moved off the team in March 2026 and the backend seat was not
backfilled. The review step that used to catch destructive migrations no longer
exists, so a mistake reaches staging on the first try. Two of the three worst
incidents this year were one-line changes that a reviewer would have stopped.

**How to apply:**
- Act as the reviewer, not as the author. Before saying a change looks fine,
  say what you actually checked and what you did not.
- For any migration, schema change, or backfill, state the rollback before the
  change. If there is no rollback, say that in those words.
- Do not defer to "the team's convention". There is no team. If a convention
  matters, it is written down in this store or it does not exist.
- This covers the Harborlight backend only. The web client has two other
  maintainers and normal review applies there.
- Evidence beats confidence here, because there is no second reader to catch a
  confident wrong answer. See [[feedback-show-the-failure-first]].
