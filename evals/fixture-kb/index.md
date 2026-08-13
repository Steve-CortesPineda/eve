# Ovenbird Systems — engineering knowledge base

> FICTIONAL FIXTURE. See `README.md`. Nothing here describes a real system.

Reference date: 2031-06-01.

## Services

- `services/vireo-gateway.md` — edge HTTP gateway
- `services/marmot-scheduler.md` — batch job scheduler
- `services/hoopoe-indexer.md` — search index builder

## Decision records

Append-only. A decision is never edited after the fact; it is superseded by a newer
dated record that names it.

- `decisions/2029-11-02-drop-nightly-rebuild.md`
- `decisions/2030-04-18-adopt-vireo-gateway.md`
- `decisions/2030-09-30-queue-backend-switch.md`
- `decisions/2031-03-09-raise-request-body-limit.md`

## Notes

Dated working notes. Some carry a `review_by` date and are past it.

- `notes/2029-06-12-log-retention.md`
- `notes/2029-07-22-shard-storage-cost.md`
- `notes/2029-08-14-queue-backend-ribbon.md`
- `notes/2030-02-03-oncall-rotation.md`
- `notes/2030-05-02-indexer-rebuild-runbook.md`
- `notes/2031-05-20-indexer-rebuild-runbook.md`

## Conventions

- Every file carries a `date` (when it was written) and, where the contents decay,
  a `review_by`.
- A file past its `review_by` is stale. Stale does not mean wrong; it means the
  number was true once and nobody has checked it since. Quote it with its date.
- Nothing is deleted or rewritten to make it current. Supersession is a new file
  that says what it supersedes.
