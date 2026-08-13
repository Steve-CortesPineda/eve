---
kind: note
date: 2030-05-02
review_by: none
status: superseded
superseded_by: notes/2031-05-20-indexer-rebuild-runbook.md
---

# Index rebuild runbook (2030 edition)

> FICTIONAL FIXTURE. Nothing here describes a real system.

**SUPERSEDED by `notes/2031-05-20-indexer-rebuild-runbook.md`. Kept unedited. Do not
run from this version.**

## Artifact retention

Keep the **3** most recent rebuild artifacts and delete anything older. Three was
chosen as "the current one, the one before it, and one spare".

## Procedure

Drain, rebuild, verify shard counts match, swap, keep the previous artifact until
the new index has served a full day without a rollback.

## Measured wall time

Not measured. The rebuild was timed by whoever was watching it and reported as
"about four hours", which is why the 2031 edition of this runbook actually measures
it.
