---
title: Decided to cache parsed manifests in process memory
type: decision
tags: [harborlight, performance, decision]
created: 2026-03-19
updated: 2026-07-01
status: active
---

We cached parsed manifests in the API process instead of adding a cache tier,
on the argument that the working set was small enough to fit.

## Outcomes

- 2026-04-11 failed - the working set was not small. Two workers were killed by
  the memory limit during a bulk import and the import had to be restarted.
- 2026-07-01 failed - reintroduced with a size cap and it still evicted the hot
  entries first, so the cache hit rate sat under ten percent.

Rye argued for the cache tier at the time. That argument is the reason this
file exists: the losing side of a decision is worth writing down.
