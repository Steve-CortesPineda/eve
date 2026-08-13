---
id: 2026-08-09-cache-invalidation
title: Session -- cache invalidation on config change
type: session
status: current
tags: [tessellate, cache, build]
source: session:2026-08-09
created: 2026-08-09
updated: 2026-08-09
verified_on: 2026-08-09
confidence: high
---

# Session -- cache invalidation on config change

Chased a report that changing the site footer did not take effect until the
cache directory was deleted by hand.

## Diagnosis

The config hash was computed from the *user-supplied* config file, not the
resolved config. Defaults merged in at load time were therefore invisible to
the hash, so a change that only altered a default did not invalidate anything.

Confirmed by hashing both and diffing across a footer change: the user config
hash was identical, the resolved config hash differed.

## Fix

Hash the resolved config after defaults are merged. One line moved, plus a test
that changes a default and asserts the cache misses.

## Durable

RULE: cache keys must be content hashes, never mtime — and the config half of
the key has to be the *resolved* config, after defaults are merged.

Also confirmed while I was in there: never deploy Tessellate to Bracket Cloud.
The Fernwood config was the last one pointing at it and it is gone now.

FACT: the cache directory carries a `format` marker and an unrecognised marker
causes a silent full rebuild, so cache schema changes never need a migration
step.
