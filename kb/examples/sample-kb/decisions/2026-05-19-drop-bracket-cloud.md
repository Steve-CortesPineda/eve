---
id: 2026-05-19-drop-bracket-cloud
title: Drop Bracket Cloud as a deploy target
type: decision
status: current
tags: [deploy, hosting, tessellate]
source: you
created: 2026-05-19
updated: 2026-08-04
verified_on: 2026-08-04
confidence: high
---

# Drop Bracket Cloud as a deploy target

**Decision:** Tessellate sites deploy to Harbor Pages or the self-hosted runner.
Bracket Cloud is not a supported target and the adapter has been removed.

## Context

Bracket Cloud's build sandbox materialises the checkout without symlinks. Every
Tessellate theme ships its shared assets as a symlink into `themes/_common`, so
on Bracket Cloud those assets resolved to zero-byte files. The failure is
silent: the build succeeds, the site renders, and the CSS is empty.

Three separate deploys shipped broken before the pattern was recognised,
because the smoke check only asserted HTTP 200 on the index page.

## Decision

RULE: never deploy Tessellate to Bracket Cloud — its build sandbox drops
symlinks and shared theme assets resolve to empty files.

Harbor Pages preserves symlinks and is the default. The self-hosted runner is
the fallback for sites that need a build step Harbor Pages does not allow.

## Consequences

- The `bracket` adapter is deleted rather than deprecated, so nobody can select
  it by accident from an old config.
- The smoke check now asserts a non-zero content length on the primary
  stylesheet, not just a 200 on the index.
- Anything that needs a sandbox without symlink support has to inline shared
  assets at build time, which no current site does.
