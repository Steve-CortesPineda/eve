---
id: lantern-paginates-with-keyset-cursors
title: Lantern paginates with keyset cursors, never with offset
type: project
status: current
tags: [lantern, api, pagination]
source: lantern api design review, 2026-04-09
created: 2026-04-09
updated: 2026-06-01
verified_on: 2026-06-01
confidence: high
---

Every list endpoint in Lantern pages with a keyset cursor built from `(created_at, id)`. Offset paging was removed and must not come back.

**Why:** Offset paging is only stable if nothing is inserted while a caller is
paging. Lantern's list is ordered newest first and receives writes constantly,
so every insert shifts the window and the caller sees a row it has already
been given while a different row is skipped entirely. Support read this as a
data corruption bug for five weeks before anyone connected it to paging.

**How to apply:**
- New list endpoints take a cursor. Do not add a `page` or `skip` parameter.
- The cursor must include the tiebreaker column. Ordering on a timestamp alone
  is not a total order and two rows sharing a timestamp will repeat or vanish.
- A client that has lost its cursor starts again from the beginning. There is
  deliberately no way to jump to an arbitrary page.
