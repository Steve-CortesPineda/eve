---
kind: decision
date: 2029-11-02
status: active
---

# Drop the nightly full rebuild

> FICTIONAL FIXTURE. Nothing here describes a real system.

## Decision

Stop running the full index rebuild every night. Keep the rebuild as an on-demand
operation only.

## Why

Two reasons, both measured before the call was made:

1. **It stopped fitting.** The rebuild had grown past the maintenance window, so it
   was routinely still running when morning traffic arrived, and the index it was
   replacing was serving degraded the whole time.
2. **The incremental path caught up.** Once incremental updates were landing within
   seconds, a nightly rebuild was no longer correcting any drift — we ran a month of
   diffs between the incrementally-updated index and a rebuilt one and found nothing
   that mattered.

The rebuild was doing no work and costing a window. So it went.

## Consequences

- A full rebuild is now a deliberate act with a runbook, not a background habit.
- Drift between the incremental index and source is no longer self-correcting on a
  24 hour cycle. If the incremental path silently breaks, nothing catches it for us.
