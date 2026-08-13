---
kind: note
date: 2029-08-14
review_by: none
status: superseded
superseded_by: decisions/2030-09-30-queue-backend-switch.md
---

# Scheduler queue backend: Ribbon

> FICTIONAL FIXTURE. Nothing here describes a real system.

**SUPERSEDED by `decisions/2030-09-30-queue-backend-switch.md`. Kept unedited as a
record of what was true in 2029. Do not answer questions about the current backend
from this file.**

## Backend

`marmot-scheduler` uses **Ribbon** as its queue backend.

## Why Ribbon

At-least-once delivery, no operational burden, and it was already running for
another purpose so it cost nothing to adopt. The known weakness — a visibility
timeout that cannot be extended once a job is in flight — was accepted on the
grounds that jobs were short. Jobs did not stay short.
