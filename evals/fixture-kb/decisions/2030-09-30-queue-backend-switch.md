---
kind: decision
date: 2030-09-30
status: active
supersedes: notes/2029-08-14-queue-backend-ribbon.md
---

# Switch the scheduler queue backend to Bramble

> FICTIONAL FIXTURE. Nothing here describes a real system.

## Decision

`marmot-scheduler` now uses **Bramble** as its queue backend. This **supersedes**
`notes/2029-08-14-queue-backend-ribbon.md`, which recorded the earlier choice of
Ribbon and which is now out of date.

The old note has deliberately not been edited. It is a record of what was true in
2029, and rewriting it would destroy the only evidence of why the change happened.

## Why

Ribbon's at-least-once delivery was fine, but its visibility timeout could not be
extended mid-job. Long jobs were being redelivered while still running, and the
scheduler was doing duplicate work it could not detect. Bramble lets a worker extend
the lease while it holds the job, which removes the failure mode rather than papering
over it with idempotency checks everywhere.

## Migration

Done in place over one maintenance window by draining Ribbon and cutting over. No
jobs were lost; some were run twice, which was already the condition we were fixing.

Effort and cost of the migration were not tracked and are not recorded anywhere.
