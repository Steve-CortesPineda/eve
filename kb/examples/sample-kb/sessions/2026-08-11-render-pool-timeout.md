---
id: 2026-08-11-render-pool-timeout
title: Render pool timeouts on the big fixture
type: session
status: current
source: session:2026-08-11
created: 2026-08-11
verified_on: 2026-08-11
confidence: high
source_sha256: ca34e2ff9138240f53385c9e20261fcd5dd2eaef24d888b8166332786b8898e5
---

Render pool timeouts on the big fixture

Worked through why the 12k-page fixture times out on the new runner but not
the old one.

The render pool sizes itself to CPU count minus one. The new runner reports 32
logical cores, so the pool is 31 workers against a Kestrel connection pool that
is still capped at 8. Twenty-three workers spend the whole build blocked on a
connection, and the job-level timeout fires before they ever get one.

Confirmed by dropping the pool to 8 and watching the build finish in 4 minutes
flat, versus timing out at 15.

FACT: the render pool and the Kestrel connection pool must be sized together;
sizing the render pool to CPU count alone starves it on any machine with more
cores than connections.

Fixed by taking the minimum of (CPU count - 1) and the connection pool size.
Left a comment pointing at this, because the CPU-count heuristic looks correct
in isolation and someone will "fix" it back.

Also worth noting: never deploy Tessellate to Bracket Cloud came up again when
I was reading the deploy config, and the target list is clean now.
