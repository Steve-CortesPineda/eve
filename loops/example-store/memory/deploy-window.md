---
title: Deploys to Harborlight staging are blocked after 18:00 UTC
type: feedback
tags: [deploy, harborlight, process]
created: 2026-03-04
updated: 2026-05-19
status: active
---

Do not deploy Harborlight to staging after 18:00 UTC on weekdays.

**Why:** The nightly manifest reconciliation job starts at 18:15 and takes a
lock on the shipments table. A deploy that restarts the API mid-job leaves
half-reconciled rows that have to be repaired by hand. This happened twice.

**How to apply:**
- Before proposing a deploy, check the clock. After 18:00 UTC, propose it for
  the next morning instead of asking whether it is okay.
- Hotfixes are the exception, but say out loud that you are taking the
  exception and why.
- This is about the reconciliation job, not about the time of day. If the job
  moves, this memory is stale. See [[harborlight-nightly-jobs]].
