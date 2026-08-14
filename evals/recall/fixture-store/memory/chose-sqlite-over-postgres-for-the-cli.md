---
id: chose-sqlite-over-postgres-for-the-cli
title: The command line tool stores its state in SQLite, not Postgres
type: decision
status: current
tags: [cli, storage, architecture]
source: you (decision, 2026-02-28)
created: 2026-02-28
updated: 2026-02-28
verified_on: 2026-02-28
confidence: high
---

The command line tool keeps its state in a single SQLite file under the user's home directory. It does not talk to Postgres and does not require a server.

**Why:** The tool has to work on a laptop with no network and be installable in
one step. Requiring a server would make the first run a configuration exercise,
and the data involved is one user's own history — there is no concurrency to
justify the cost. The write pattern is one process appending, which is the case
SQLite is best at.

**How to apply:**
- Keep it single-writer. If two processes ever need to write, that is a design
  change, not a locking problem to be tuned around.
- Do not add a server dependency for a feature that only needs a table. Ask
  whether the feature could be a file first.
- Ship schema changes as forward-only migrations that run at start-up. A user
  will never run a migration command by hand.
