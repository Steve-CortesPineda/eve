# Loop 3 — outcome reweight

**Consumer: you, reading the "Waiting on reality" list in `$EVE_HOME/proposals/outcomes-<date>.md`. That list is the product.**

**Conditional second consumer:** `state/weights.tsv`, written *only* when you pass `--write-weights`, and only worth writing if your `eve search` reads it. Check first. A weights file that nothing multiplies by is the write-only producer in its purest form — a number computed every night, stored forever, multiplied by nothing.

**Producer: `eve outcome`.**

```sh
eve outcome drop-offset-pagination worked "duplicate-row reports went to zero"
```

That appends one line to the memory's `## Outcomes` section and touches nothing else in the file:

```markdown
## Outcomes

- 2026-05-02 worked - duplicate-row reports went to zero and stayed there.
- 2026-06-18 mixed - one caller stored page numbers in a saved-search table.
```

The argument before the verdict is an exact memory id, or any text that appears in exactly one id or title — `eve outcome pagination worked` if only one memory says "pagination". If more than one does, the command lists them and refuses; guessing which decision you meant is not a thing a tool should do with your notes.

**Outcomes accumulate.** Running it again in November adds a second line. Nothing is overwritten, because a decision that worked in May and failed in November is two facts and not a correction — and this loop pays `+0.10` specifically for outcomes on two or more distinct dates. Re-running the same date and verdict writes nothing and says so, so a script that calls it twice cannot inflate the tally.

**Frontmatter still counts, and is never written.**

```yaml
outcome: worked        # worked | failed | mixed
outcome_date: 2026-05-02
```

Stores written before the command existed keep ranking exactly as they did; a `(date, verdict)` pair present in both places is counted once. But `eve outcome` will not put a verdict there and will not rewrite one that is there. That field holds a single value, so recording a second check would mean deleting the first — history destroyed one improvement at a time.

**The other half of the habit is `eve waiting`**, which prints this loop's "waiting on reality" list without running the loop at all:

```
$ eve waiting
1 of 3 decision(s) have never been checked against reality.

    days  id                                   title
      51  decision-move-reconcile-to-queue     Decided to move nightly reconciliation onto the job queue

Record one:  eve outcome decision-move-reconcile-to-queue worked "what you observed"
```

It is also printed by `eve doctor`, and `eve add -t decision` scaffolds the empty `## Outcomes` section and tells you the command that fills it. Between them the habit has three prompts and no YAML.

Install this loop last. It has nothing to rank until decisions exist and outcomes have been recorded against them. It is still the only loop that depends on you going and finding something out — the command removes the friction, not the looking.

## It ranks. That is all it does.

It does not edit a memory. It does not delete one. It does not propose a deletion, including for a decision whose every recorded outcome is `failed`. Ranking and deleting are different operations, and this loop is not allowed near the other one.

The weight floor is 0.80 and the ceiling is 1.40. A multiplier that can reach zero is a deletion with extra steps.

## The tempting mistake: weighting by success

The obvious design is to rank successful decisions up and failed ones down. It is backwards.

When you ask *"should we cache the parsed manifests in process memory?"*, the memory that earns its retrieval is the one recording that this was tried twice and failed both times. Down-ranking it for having a bad outcome hides the single most useful file in the store, and every query starts returning only the decisions that went well. That is survivorship bias compiled into a ranker: a memory system that tells you what you want to hear, built one reasonable-looking multiplier at a time.

So the weight is a function of **evidence, not of success**:

| condition | effect |
|---|---|
| at least one recorded outcome | +0.25 |
| outcomes on two or more distinct dates | +0.10 |
| a **decision** with no outcome, older than `--stale-days` (90) | −0.10 |
| clamp | 0.80 … 1.40 |

The verdict tally is printed because you want to read it. It is not multiplied by anything. A decision that failed twice and a decision that worked once carry the same weight, because reality has spoken about both, and that is the only thing this loop claims to know.

The untested-intention penalty applies to decisions only. A reference note has no outcome because the concept does not apply to it — "Harborlight uses cursor pagination" is not waiting to find out how it went. Penalizing it for a missing field it was never supposed to have would be the loop measuring its own schema instead of the world.

## Run it

```sh
# read-only
$EVE_HOME/loops/outcome-reweight/eve-outcome-rank.sh --dry-run

# write the proposal
$EVE_HOME/loops/outcome-reweight/eve-outcome-rank.sh

# every memory, not just decisions
$EVE_HOME/loops/outcome-reweight/eve-outcome-rank.sh --all

# machine-readable
$EVE_HOME/loops/outcome-reweight/eve-outcome-rank.sh --format tsv

# only if something reads it
$EVE_HOME/loops/outcome-reweight/eve-outcome-rank.sh --write-weights
```

## Verified output

Against the fixture store. `--stale-days 30` so the waiting list is populated (the fixture's untested decision was created on 2026-06-24, so it clears that threshold on any plausible run date):

```
$ EVE_HOME=loops/example-store sh loops/outcome-reweight/eve-outcome-rank.sh --dry-run --stale-days 30

<!-- generated by eve-outcome-rank.sh on 2026-08-13; regenerable -->

# Decisions, ranked by whether reality has voted - 2026-08-13

Memories considered: 3 (decisions: 3)
With a recorded outcome: 2   Waiting over 30 days: 1   Still young: 0

## Ranked

| weight | id | worked | failed | mixed | last outcome |
|---|---|---|---|---|---|
| 1.35 | decision-cache-manifests-in-memory | 0 | 2 | 0 | 2026-07-01 |
| 1.35 | decision-drop-offset-pagination | 1 | 0 | 1 | 2026-06-18 |
| 0.90 | decision-move-reconcile-to-queue | 0 | 0 | 0 | - |

The weight rises when a decision has been checked against reality and
falls slightly when one has sat untested. It does not rise for success
or fall for failure -- a decision that failed is often the most useful
file in the store, and a ranker that buries failures will happily tell
you to do the thing that did not work last time.

## Waiting on reality (1)

Asserted, never checked. This is the actionable list: pick one, find out
what happened, and record it.

| id | age (days) | title |
|---|---|---|
| decision-move-reconcile-to-queue | 51 | Decided to move nightly reconciliation onto the job queue |

```sh
eve outcome decision-move-reconcile-to-queue worked|failed|mixed "what you observed"
```

The same list, without running this loop: `eve waiting`.

## What this loop will not do

- It will not edit a memory. `eve outcome` writes the verdict you
  hand it and nothing anywhere derives one, because an outcome a
  program inferred is evidence a program invented.
- It will not propose deleting anything, including a decision whose
  every outcome is `failed`. That file is the reason nobody repeats it.
- It will not weight below 0.80. A multiplier that can reach zero is a
  deletion with extra steps.


[dry run] nothing written.
```

The top two rows are the design in one screenshot: the decision that failed twice and the decision that worked both sit at 1.35, above the one nobody ever checked. And the actionable output is not the ranking — it is the one-row table underneath it, naming a decision nobody has established the result of, and the exact command that would settle it.

(The age is measured from the report's own run date, so that number climbs by one each day the decision goes unchecked. Everything else in the output is fixed.)

Verified separately: `--dry-run` writes nothing; a full run leaves every file in `memory/` byte-identical (`diff -r` clean); an invalid `--format` exits 64.

Verified on the producer side too, because a command that writes into your notes has to earn it: creating a decision, recording an outcome, then recording a second one months later leaves the file byte-identical except for the added lines (`diff` shows insertions and zero modifications); the loop then reports both dates and pays the two-date bonus; re-running the same date and verdict writes nothing; an ambiguous name lists the candidates and exits 65 rather than picking one. `eve outcome` re-derives the original file from what it is about to write and refuses to write at all if they do not match.

## If you wire the weights file into retrieval

Only if your `eve search` supports it. The integration is one lookup in the scorer — read `state/weights.tsv` into an array keyed by memory id and multiply the final score. Two rules if you do:

1. **Clamp on the consumer side too.** Never trust a producer's bounds; the file is plain text and a fat-fingered edit should not be able to bury a memory.
2. **Fall back silently when the file is absent, stale, or malformed.** A retrieval path that depends on an optional Tier 2 file is not optional any more.

If you do not wire it in, do not pass `--write-weights`. That is not a style preference. See the worked example in [`docs/04-loops.md`](../../docs/04-loops.md) for what a producer with no consumer costs over a few months.

## A bug found while building this

The body-outcome parser was a `sed` script containing `\(worked\|failed\|mixed\)`. That alternation is a GNU extension. BSD `sed` does not implement it, does not complain, and simply matches nothing — so every outcome recorded in a body section counted as zero on macOS. The report was well-formatted, internally consistent, and wrong: a decision with two recorded failures displayed `0 failed`, and the summary line agreed with it. Alternation now lives in `awk`'s ERE, where every implementation agrees what it means.

The general shape is worth keeping: **a parser that finds nothing looks exactly like a store that contains nothing.** Any loop that reads a format should be tested against a fixture where the answer is known and non-zero, which is what `loops/example-store` is for.

## The same bug from the other direction

Adding `eve outcome` meant there were suddenly two programs reading this format, and writing the second one surfaced a case the first had always got wrong. A memory that documents the outcome format contains a sample line:

````markdown
```markdown
- 2020-01-01 worked - this is a sample, not a verdict
```
````

That sample was counted as a real verdict. Same failure as the `sed` bug — a report that is well-formatted, internally consistent, and wrong — arrived at by finding something that is not there instead of missing something that is. Both readers now skip fenced code, in three lines that are identical on purpose and commented as such in all three places.

The rule that falls out of having two readers: **the format is the contract, and the reader you did not run is the one that was right.** `eve outcome` and this loop agree on what a verdict is, where to look for one, and that a `(date, verdict)` pair written in both frontmatter and the body counts once — not because they share code (a Tier 2 loop must stay standalone, and Tier 0 may not depend on one) but because the fixture is checked against both.
