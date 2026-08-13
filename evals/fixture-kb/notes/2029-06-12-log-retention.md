---
kind: note
date: 2029-06-12
review_by: 2030-06-12
status: stale
---

# Log retention

> FICTIONAL FIXTURE. Nothing here describes a real system.

**STALE — written 2029-06-12, review date 2030-06-12 has passed. Quote with the
date and re-verify before acting on it.**

## Policy

Application logs are kept for **45 days** and then deleted. The number came from the
longest incident investigation we had run at the time (31 days back) plus margin.

## Why it will drift

Retention is the first thing that gets cut when storage gets tight and the first
thing that gets extended after a long investigation. It has changed before without
anyone updating a document. If the answer matters, read it off the running system
rather than off this note.
