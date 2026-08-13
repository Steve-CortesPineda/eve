---
title: Decided to move nightly reconciliation onto the job queue
type: decision
tags: [harborlight, jobs, decision]
created: 2026-06-24
updated: 2026-06-24
status: active
---

Reconciliation will move from the cron entry on the staging host onto the job
queue, so a deploy no longer has to be timed around it.

**Why:** the 18:00 UTC deploy freeze exists only because reconciliation holds a
table lock from a machine nobody watches. See [[deploy-window]].

No outcome has been recorded yet. If this worked, the deploy-window rule is
stale and should be superseded; if it failed, that is worth knowing before
someone proposes it again.
