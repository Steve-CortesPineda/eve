---
id: tessellate-cache-keys
title: Tessellate cache keys are content-addressed
type: note
status: current
tags: [tessellate, cache, build]
source: you
created: 2026-06-11
updated: 2026-07-28
verified_on: 2026-07-28
confidence: high
supersedes: [tessellate-cache-mtime]
---

# Tessellate cache keys are content-addressed

RULE: cache keys must be content hashes, never mtime.

The rebuild cache is keyed on `sha256(file bytes) + sha256(resolved config)`.
Both halves matter. Hashing only the file bytes meant a config change that
altered rendering left the cache warm and produced pages built under the old
settings, which is how the Fernwood Museum site shipped with the wrong footer
for nine days before anyone noticed.

## What invalidates an entry

- the source file bytes change
- any key in the resolved config changes, including keys the page does not read
- the Tessellate version changes (the version string is part of the config hash)

Deliberately *not* invalidating on config keys a page does not read: the
dependency tracking needed to know which keys a page touched costs more than
the rebuilds it saves.

## Migration note

Builds cached under the old mtime scheme are not readable. The cache directory
carries a `format: 2` marker and Tessellate silently discards a cache whose
marker it does not recognise, so the upgrade needs no manual step.
