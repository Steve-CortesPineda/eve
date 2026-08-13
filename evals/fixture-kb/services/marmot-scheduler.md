---
kind: service
name: marmot-scheduler
date: 2029-09-05
review_by: 2030-03-05
---

# marmot-scheduler

> FICTIONAL FIXTURE. Nothing here describes a real system.

Runs batch jobs on a schedule and on demand. Owns the job queue, the worker pool,
and the retry policy. Does not own the index it rebuilds — that belongs to
`hoopoe-indexer`.

## Retries

A job that fails is retried automatically with exponential backoff, and is moved to
a dead-letter list after its retries are exhausted. The exact backoff interval, the
multiplier and the retry ceiling are set per job class in the deployment config;
they have never been written down here.

## Capacity

**PROVISIONAL — measured 2029-09-05, past its review date of 2030-03-05.**

The pool sustained **400 concurrent jobs** in the load test without queue growth.
This was a single test on the hardware of the day and has not been re-measured. Treat
it as an order of magnitude, not a limit, and re-run the test before relying on it.

A standby pool exists and is kept warm; it has never been exercised under load.

## Queue backend

Not stated here on purpose. The backend has changed once; see the decision records
rather than this file, and prefer the most recent one.
