---
id: connection-pool-capped-at-twenty
title: The database connection pool is capped at twenty per instance
type: reference
status: current
tags: [database, capacity, configuration]
source: database configuration + capacity review, 2026-05-19
created: 2026-05-19
updated: 2026-05-19
verified_on: 2026-05-19
confidence: high
---

Each application instance opens at most twenty database connections, and the database itself accepts one hundred in total.

**Why:** Five instances at twenty is the whole budget, with nothing left for
the migration runner or a human holding a session open. Raising the per
instance cap does not add capacity, it just moves which process gets refused
first — and the process that gets refused first is usually the one trying to
diagnose the problem.

**How to apply:**
- Do not raise the pool size to fix slowness. A saturated pool means queries
  are slow, and more connections make a slow query slower.
- Adding an instance costs twenty connections from the shared hundred. Count
  before scaling out.
- Keep one connection spare for an operator. Losing the ability to log in
  during an incident turns a slow system into an opaque one.
