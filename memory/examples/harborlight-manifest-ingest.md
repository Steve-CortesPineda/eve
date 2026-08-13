---
id: harborlight-manifest-ingest
title: Harborlight ingests manifests through exactly one writer
type: project
status: current
tags: [harborlight, ingest, architecture]
source: harborlight ingest worker + design review notes, 2026-01-20
created: 2026-01-22
updated: 2026-06-18
verified_on: 2026-06-18
confidence: high
---

Every carrier manifest enters Harborlight through a single queue consumer. Exactly one process writes to the `shipments` table.

**Why:** Delivery is at-least-once, so the same manifest arrives more than once
under retry. Dedupe is keyed on the carrier's `manifest_id`, never on our own
row id — our id is assigned at insert time, so a duplicate gets a fresh one and
looks new. The first version of this system had two writers, each doing its own
dedupe, and produced duplicate shipments for four months before a customer
noticed.

**How to apply:**
- Do not add a second process that writes `shipments`. New consumers read.
- Any consumer must be idempotent on `manifest_id`. Assume every message is
  delivered at least twice.
- If throughput is the problem, partition the single writer. Adding a second
  writer is the failure mode, not the fix.
- Retry behaviour depends on how the carrier signals throttling, which is not
  what you would guess. See [[reference-carrier-throttle-returns-200]].
