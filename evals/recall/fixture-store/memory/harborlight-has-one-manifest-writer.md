---
id: harborlight-has-one-manifest-writer
title: Exactly one process writes Harborlight shipments
type: project
status: current
tags: [harborlight, ingest, architecture]
source: harborlight ingest worker + design review notes, 2026-01-20
created: 2026-01-22
updated: 2026-06-18
verified_on: 2026-06-18
confidence: high
---

Carrier manifests enter Harborlight through a single queue consumer, and that consumer is the only writer to the `shipments` table.

**Why:** Queue delivery is at-least-once, so the same manifest arrives more
than once under retry. Deduplication is keyed on the carrier's `manifest_id`
and never on our own row identifier, because ours is assigned at insert time —
a duplicate gets a fresh one and looks new. An earlier version had two writers,
each deduplicating independently, and produced doubled shipments for four
months before a customer noticed.

**How to apply:**
- Do not add a second process that writes `shipments`. New consumers read.
- Any consumer must be idempotent on `manifest_id`. Assume every message is
  delivered at least twice.
- If throughput is the problem, partition the single writer. A second writer is
  the failure mode, not the fix.
