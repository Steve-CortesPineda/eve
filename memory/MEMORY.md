# Memory index

Every memory in this store, one line each. The line states the **claim**, not the
topic, so this file is useful without opening anything. Open the file when you
need the reasoning or the exact conditions.

Conventions, in short (full rules in [docs/02-memory-format.md](../docs/02-memory-format.md)):

- One file, one claim. The filename stem is the id.
- `status: superseded` is a tombstone. Superseded memories are **not** listed
  here — they stay on disk, demoted, so the reversed claim cannot come back.
- Nothing here is authoritative about the world; it is authoritative about what
  *you* decided. Anything dated is quoted with its date.
- This starter index is hand-written because the repo ships four examples. In a
  real store, generate it. An index you maintain by hand drifts from the files
  it describes, and an index that lies is worse than no index at all.

> **This file is not your index.** It is a sample of the one-line convention,
> listing this repo's fictional examples, and it stays in the clone. Your store's
> index is `~/.eve/INDEX.md` — created by `scripts/new-memory.sh` and regenerated
> from the files by `eve index`. That is the path the `CLAUDE.md` rule block
> names, and the only one your agent is told to read.

---

## Standing rules

<!-- eve:section type=feedback -->

- [Nobody reviews your Harborlight changes](examples/you-review-solo.md) — feedback, verified 2026-06-30
- [Show the actual failure output before proposing a fix](examples/feedback-show-the-failure-first.md) — feedback, verified 2026-05-21

## Project state

<!-- eve:section type=project -->

- [Harborlight ingests manifests through exactly one writer](examples/harborlight-manifest-ingest.md) — project, verified 2026-06-18

## Decisions

<!-- eve:section type=decision -->

*(none yet — a decision memory records a call you made and the reasoning that made it, so you stop re-litigating it)*

## Reference

<!-- eve:section type=reference -->

- [The carrier tracking API signals throttling with an empty 200, not 429](examples/reference-carrier-throttle-returns-200.md) — reference, verified 2026-05-02

## Notes

<!-- eve:section type=note -->

*(none yet — `note` is the default type for something you have written down but not yet decided what it is)*
