---
id: migrations-never-during-business-hours
title: Schema migrations never run during business hours
type: decision
status: current
tags: [database, migrations, risk]
source: you (team decision, 2026-01-08)
created: 2026-01-08
updated: 2026-01-08
verified_on: 2026-01-08
confidence: high
---

A schema migration runs on a weekend morning or not at all. This is separate from the release rule and stricter than it.

**Why:** A migration holds locks that a release does not. The 2025-12-14
migration added an index on a large table, held a lock for eleven minutes, and
every write behind it timed out. Nothing about the change was risky; the
duration was. A release can be reverted in a minute and a half completed
migration cannot.

**How to apply:**
- Schedule the migration separately from the code that needs it. Ship the code
  behind a flag first, migrate later, then turn the flag on.
- Estimate the lock duration on a copy of the real table before running it.
  Row counts from a development database predict nothing.
- Write the reverse migration before running the forward one, and test it.
