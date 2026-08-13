# Tier 2 — learning loops

Optional. Off by default. Nothing in Tier 0 or Tier 1 depends on anything here.

**These are reference implementations, not products.** Each is one readable file
that demonstrates a pattern from [`docs/04-loops.md`](../docs/04-loops.md) on a
real store. They are deliberately small, they have no test suite, and the
thresholds in them are guesses that happened to suit one store. Read the script
before you schedule it, and expect to change the numbers.

These are the parts of the idea most likely to hurt you, so read [`docs/04-loops.md`](../docs/04-loops.md) before installing one. The short version of that chapter is one rule:

> **Do not build a producer without a consumer.**
> Every loop names, in its own header comment, the thing that reads its output. If you cannot name one, you have built a component that will run forever, look healthy, and change nothing.

## The three loops

| Loop | Reads | Writes | Consumer | Install it |
|---|---|---|---|---|
| [gap-detection](gap-detection/) | `state/whiffs.log` (written by the recall hook) | `proposals/gaps-<date>.md` | you, then the memories you write | first — the signal is free |
| [reality-reconcile](reality-reconcile/) | `eve:check` markers you put in memories | `proposals/reconcile-<date>.md`, and with `--apply` one reversible comment line | you, plus the model seeing the marker inline | second — only if your memories assert checkable facts |
| [outcome-reweight](outcome-reweight/) | outcomes you record on decisions | `proposals/outcomes-<date>.md`, optionally `state/weights.tsv` | you, reading what reality has not voted on | last — needs a habit, not a script |

Install in that order, one at a time, with a few weeks between. Three loops installed on the same afternoon produce three reports you have no routine for reading, which is the failure this whole chapter is about.

## Properties every loop here holds to

1. **Standalone.** Each script is a single file with no shared library. They duplicate about thirty lines of config parsing between them, on purpose: you can copy one out of this repo and it still runs.
2. **Dry-run means zero writes.** Not "no important writes". Zero. A state file created by a `--dry-run` is a bug, and was one.
3. **Proposals, not actions.** Default output is a markdown file for a human. Only reality-reconcile can write into a memory at all, only with `--apply`, only after a repeated failure, and only a comment line.
4. **Every automatic write is backed up and logged with a working undo command.**
5. **Nothing deletes a memory.** No flag, no threshold, no configuration. There is no code path.
6. **POSIX sh.** No bash 4, no `jq`, no `python3`, no network unless you pass `--net`.
7. **Exit 0.** Only a usage error exits non-zero (64), and only a developer sees it.

## Try them without installing anything

`example-store/` is a complete fictional memory store — eight memories about a made-up shipping-manifest API, a whiff log, and a config. Every loop runs against it read-only:

```sh
EVE_HOME=loops/example-store sh loops/gap-detection/eve-gap-detect.sh   --dry-run --since 3650
EVE_HOME=loops/example-store sh loops/reality-reconcile/eve-reconcile.sh --dry-run
EVE_HOME=loops/example-store sh loops/outcome-reweight/eve-outcome-rank.sh --dry-run --stale-days 30
```

Each loop's README reproduces the output of those commands. Dates are the one
thing that will differ: the reports stamp the day they were generated, and the
gap window is computed from it. Everything else — the terms, the counts, the
ordering — is deterministic, so if a row is missing or a number has moved,
something really has changed.

The example store has no `bin/eve` in it, so gap-detection falls back to a
word-bounded `grep` for its coverage probe and says so in the report. That is
the loops degrading honestly rather than pretending, and it is what you would
see on a store where the CLI was not installed.

## Installing one for real

```sh
mkdir -p "$EVE_HOME/loops"
cp -R loops/gap-detection "$EVE_HOME/loops/"
chmod +x "$EVE_HOME/loops/gap-detection/eve-gap-detect.sh"
```

Run it by hand for a few weeks before you consider scheduling it. If you do schedule it, schedule the read-only form, and put the report somewhere you already look — a loop whose output lands in a directory you visit twice a year has no consumer, whatever its header comment claims.

## Config keys

All optional, all in `$EVE_HOME/config`, all overridable by an environment variable of the same name and by a command-line flag:

```
# gap detection
EVE_GAP_MIN_HITS=3               # whiffs before a term is a gap
EVE_GAP_MIN_DAYS=2               # ...spread over this many distinct days
EVE_GAP_SINCE_DAYS=30            # window

# reality reconcile
EVE_RECONCILE_STREAK=3           # consecutive failing runs before --apply acts
EVE_RECONCILE_MIN_GAP_SECS=3600  # minimum spacing for a run to count
EVE_RECONCILE_MAX_FAIL_PCT=50    # above this, the run is inconclusive
EVE_RECONCILE_CONTROL_HOST=example.com

# outcome reweight
EVE_OUTCOME_STALE_DAYS=90        # a decision is "waiting" after this long
```

## Turning one off

Delete the directory, or stop running it. There is no daemon, no registration, no state outside `$EVE_HOME`, and nothing else in Eve reads a loop's output. Removal cannot break retrieval, because retrieval never depended on it.

Do turn one off when it stops earning its place. That is a normal outcome, not a failure of nerve.
