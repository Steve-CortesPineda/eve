---
id: tessellate-cache-mtime
title: Tessellate rebuild cache (mtime scheme)
type: note
status: current
tags: [tessellate, cache, build]
source: you
created: 2026-04-09
updated: 2026-04-09
verified_on: 2026-04-09
confidence: medium
---

# Tessellate rebuild cache (mtime scheme)

The rebuild cache stores one entry per source file, keyed on the path plus the
file's modification time. On each build Tessellate stats every source file and
reuses the cached render when the mtime matches.

This is cheap: a stat is far less work than reading the file. It also matches
what most build tools do.

## Caveat

Any operation that rewrites mtimes without changing content — a fresh clone, a
restored backup, a `touch` — invalidates the whole cache. On CI, where every
run starts from a clean checkout, the cache never hits at all.
