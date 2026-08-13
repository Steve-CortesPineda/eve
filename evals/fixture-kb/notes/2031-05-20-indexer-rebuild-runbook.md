---
kind: note
date: 2031-05-20
review_by: none
status: active
supersedes: notes/2030-05-02-indexer-rebuild-runbook.md
---

# Index rebuild runbook (2031 edition)

> FICTIONAL FIXTURE. Nothing here describes a real system.

**Supersedes `notes/2030-05-02-indexer-rebuild-runbook.md`.** The older runbook is
kept unedited; this one is authoritative.

## Artifact retention

Keep the **5** most recent rebuild artifacts, raised from 3. Two rollbacks in one
quarter both wanted an artifact that had already been pruned, which is a cheap
problem to stop having.

## Measured wall time

A full rebuild across all shards took **3 hours 20 minutes**, measured on
2031-05-20 with the shards rebuilt in parallel and nothing else running. Expect
longer under live traffic; this was a clean run.

## Procedure

1. Confirm the incremental path is healthy before starting — a rebuild started on
   top of a broken incremental path just bakes the breakage in.
2. Rebuild into a new artifact. Do not touch the serving index.
3. Verify shard count and document count against source.
4. Swap. Keep the previous artifact for a full day of serving before pruning to the
   retention limit.
