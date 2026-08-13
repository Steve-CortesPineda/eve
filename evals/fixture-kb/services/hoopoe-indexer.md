---
kind: service
name: hoopoe-indexer
date: 2031-05-20
review_by: none
---

# hoopoe-indexer

> FICTIONAL FIXTURE. Nothing here describes a real system.

Builds and serves the search index. Two paths into it: an incremental path that
applies changes as they arrive, and a full rebuild that discards the index and
recreates it from source.

## Shards

The index is split across **12 shards**. Shard assignment is by a hash of the
document id, so the split is even and rebalancing means a full rebuild.

Shard metadata is written alongside the index itself rather than in a separate
store.

## Incremental path

Changes are applied within seconds of arriving. This is the path that made the
nightly full rebuild unnecessary — see
`decisions/2029-11-02-drop-nightly-rebuild.md`.

## Full rebuild

Still supported, and still occasionally necessary (shard count changes, schema
changes, corruption). Procedure and timings live in the runbook — take the most
recent one, `notes/2031-05-20-indexer-rebuild-runbook.md`.
