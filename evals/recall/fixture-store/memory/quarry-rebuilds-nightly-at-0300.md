---
id: quarry-rebuilds-nightly-at-0300
title: Quarry reporting tables rebuild nightly at 03:00 and are stale until then
type: project
status: current
tags: [quarry, warehouse, reporting]
source: quarry scheduler configuration, 2026-04-21
created: 2026-04-21
updated: 2026-04-21
verified_on: 2026-04-21
confidence: high
---

Quarry's reporting tables are rebuilt by one nightly job at 03:00. Anything written after the previous run is invisible to reports until the next one finishes.

**Why:** The rebuild is a full recomputation, not an incremental merge, and it
takes about forty minutes. Two separate investigations into "missing revenue"
turned out to be somebody comparing a report against the live table in the
afternoon and finding the numbers disagreed, exactly as designed.

**How to apply:**
- Never compare a Quarry report against the live tables and treat a difference
  as a bug. Check the timestamp of the last rebuild first.
- If a number has to be current, read the live table directly and say in the
  output that it bypassed the warehouse.
- Do not trigger a manual rebuild during working hours. It saturates the same
  pool the live queries use.
