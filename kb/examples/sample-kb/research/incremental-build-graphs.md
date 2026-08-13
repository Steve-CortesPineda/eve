---
id: incremental-build-graphs
title: How incremental build graphs handle deletes
type: research
status: current
tags: [build, incremental, research]
source: https://notes.example.invalid/incremental-builds
created: 2026-06-30
updated: 2026-06-30
verified_on: 2026-06-30
confidence: medium
---

# How incremental build graphs handle deletes

Reading on how other incremental builders handle the delete case, since
`tess serve` currently gets it wrong.

## The general shape

Most incremental builders track a dependency edge from output to input. On a
write they walk forward from the changed input and rebuild the reachable
outputs. Deletes are harder because there is no changed input to walk from —
the input is gone, and the edge that would have pointed at it is gone too.

Two approaches show up repeatedly:

- **Tombstones.** The manifest keeps an entry for a deleted file with a
  `deleted` flag, so the next build still has an edge to walk. Cheap, but the
  manifest grows without bound unless something prunes it.
- **Reverse index.** Keep an explicit input-to-output index and consult it on
  delete. Correct in all cases, costs memory proportional to the edge count.

## Relevance to Tessellate

Tessellate's link graph is already a reverse index for internal links; it is
just not consulted on delete. The fix is plausibly small — invalidate from the
reverse index in the watcher's delete handler rather than only in its write
handler.

Not verified against the code. Treat this as a lead, not a plan.
