---
id: 2026-08-02-deploy-postmortem
title: Session -- Fernwood deploy postmortem
type: session
status: current
tags: [deploy, tessellate, postmortem]
source: session:2026-08-02
created: 2026-08-02
updated: 2026-08-02
verified_on: 2026-08-02
confidence: high
---

# Session -- Fernwood deploy postmortem

Spent the session working out why the Fernwood Museum site rendered unstyled
after Tuesday's deploy, and fixing the check that should have caught it.

## What happened

The deploy config still listed Bracket Cloud as the target for that one site.
Everything else had been migrated in May. The build succeeded, the smoke check
passed on HTTP 200, and the stylesheet was zero bytes because the theme assets
are a symlink.

Reproduced it locally by building in a container with symlinks stripped, which
took about ten minutes and is now a test.

## Fix

- Removed the `bracket` target from the Fernwood config; it now points at
  Harbor Pages like everything else.
- Added `tests/no_symlink_sandbox.py`, which builds a fixture site with
  symlinks flattened and asserts the stylesheet is non-empty.

## Durable

RULE: never deploy Tessellate to Bracket Cloud — the build sandbox drops
symlinks and shared theme assets silently resolve to empty files.

RULE: always run `tess verify` before publishing to Harbor Pages. It checks
asset byte lengths, which a plain HTTP 200 smoke check does not.

GOTCHA: a passing build says nothing about asset integrity. Assert content
length on at least one asset per deploy.
