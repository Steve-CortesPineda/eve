# 13 · Retrieval engines

Eve ships one retrieval engine: `grep` to narrow the store, `awk` to score what
survives, no index. [Chapter 03](03-hooks.md) explains it and publishes its
numbers. This chapter is about the question those numbers raise.

**How do we know that is the right shape for *your* machine?**

We do not. The default engine's constants — a 300-file candidate cap, a 400-line
read limit, a relevance floor — were chosen against measurements taken on one
fast laptop with a warm page cache. On an older Intel machine, a spinning disk,
an encrypted or network filesystem, or a box under load, every one of those
numbers moves, and nothing in Eve notices.

So this chapter does two things. It ships a tool that measures the machine you
are actually on, and it ships an alternative engine for the case where the
measurement says the default one has run out of road.

---

## The constraint is latency, and it is not disk

Start by dismissing the thing people optimise first.

| | |
|---|---|
| 2,000 memories on disk | **7.8 MB** |
| the FTS5 index over them | **3.1 MB** |
| both together | **under 11 MB** |

A store far larger than any curated store should ever be fits in about a tenth
of the space of one phone photo. The per-file caps already in the code — 40
lines read for an index entry, 400 for scoring, 2,000 whiff-log lines kept —
bound the individual files too. If you have a gigabyte free you have roughly two
orders of magnitude more room than the largest realistic store, and if you have a
hundred gigabytes free you have four.

**There is no disk quota feature in Eve and there should not be one.** Anything
you spend on managing store size is spent on the wrong problem.

The real constraint is stated in [chapter 03](03-hooks.md) and it is worth
repeating in its blunt form: **a hook that adds a second to every prompt gets
uninstalled, and the memory system dies with it.** `eve-recall.sh` runs before
every single turn. That is the budget. Everything below is about spending it.

---

## Measure your own machine

```sh
engines/sqlite/bench.sh              # latency, maintenance, agreement, and nine checks
engines/sqlite/bench.sh 200 2000     # just those store sizes
engines/sqlite/bench.sh --proofs     # correctness only, no timing
```

It builds its own synthetic store, its own copy of `bin/eve` and its own hooks in
a temporary directory, measures both engines through the real
`UserPromptSubmit` hook, and deletes everything on exit. It never touches your
`$EVE_HOME` and never modifies the repository.

Every number in this chapter came out of that script. None of them are estimates.

**Where they were taken:** an Apple Silicon laptop, APFS on internal NVMe, warm
cache, otherwise idle, `sqlite3` 3.51.0. Ten prompts per data point, one session
id throughout — which is the shape of a real session and, as it turns out,
matters a great deal (see "where the time actually goes").

---

## What the measurement says

### Latency per prompt, end to end

Process startup, JSON parse, retrieval, dedupe bookkeeping. Nothing stubbed out.

| memories | default (grep+awk) | sqlite FTS5 | index build | index size | store on disk |
|---:|---:|---:|---:|---:|---:|
| 10 | 66 ms | 54 ms | 202 ms | 60 K | 40 K |
| 50 | 110 ms | 85 ms | 192 ms | 120 K | 200 K |
| 200 | 183 ms | 134 ms | 263 ms | 372 K | 800 K |
| 500 | 260 ms | 165 ms | 396 ms | 840 K | 2.0 M |
| 1,000 | 328 ms | 190 ms | 457 ms | 1.6 M | 3.9 M |
| 2,000 | 486 ms | 250 ms | 776 ms | 3.1 M | 7.8 M |

The build is a one-off. At 2,000 memories it costs 776 ms once, and after that
the index is maintained incrementally.

### What the index costs to keep honest

The steady-state row is the easy number to publish and the least interesting
one. An index is only worth having if the query *after* you change something is
still fast — that is the query you make right after writing a memory, and "fast
until you use it" is how a benchmark lies.

2,000 memories. One run of three, printed as the script printed it:

```
steady state, nothing changed                  238 ms
first query after one memory edited            255 ms  (+17)
first query after one memory added             260 ms  (+22)
first query after one memory deleted           256 ms  (+18)
```

Across the three runs the steady state was 236–242 ms and the penalties ranged
+17 to +33 ms. The worst repair path on the largest store still lands well under
the default engine's *steady state* of 486 ms.

That was not true of the first implementation. Reconciling a deletion by
rebuilding a live-path table inside SQLite — 2,000 INSERTs to answer a question
about one file — cost **+139 ms**, which made the query after any add or delete
*slower* than the engine it was supposed to beat. Replacing it with a path-set
diff through `comm` brought it to +18. **Measure the repair path, not just the
happy one.**

### Where the time actually goes

The most useful measurement in this chapter, and the one that stops the
comparison being oversold. At 2,000 memories:

| | default | sqlite |
|---|---:|---:|
| `eve search` alone, no hook | 195 ms | **54 ms** |
| the hook, fresh session id each prompt | 244 ms | 114 ms |
| the hook, one session id (a real session) | 486 ms | 250 ms |
| the hook with `EVE_DISABLE=1` | 14 ms | 14 ms |
| a bare `sh -c true` | 5 ms | 5 ms |

Retrieval gets **3.6× faster**. The end-to-end prompt gets **1.9× faster**. The
difference between those two numbers is the part an engine cannot fix, and it is
worth naming precisely, because at 2,000 memories it is more than half the cost:

- **`eve_store_count` walks the store in shell** — about 55 ms at 2,000 files.
  `hooks/eve-recall.sh` calls it to size the cross-turn dedupe window, so it is
  paid on every prompt after the first of a session.
- **A miss costs two searches.** When the dedupe list is non-empty and the search
  comes back empty, the hook re-runs it once without exclusions to decide whether
  it has found a real gap. That is a deliberate and well-argued design
  ([chapter 03](03-hooks.md)) and it doubles the retrieval cost of a miss —
  195 ms becomes 390 ms on the default engine, 54 becomes 108 on this one.

Both numbers scale with the store, both live in the hook rather than in an
engine, and both are why the "fresh session" row is half the "real session" row.
An index makes the half it owns four times cheaper. It cannot touch the rest.

---

## So when is it worth it?

Honestly: **for most people, never.**

The sqlite engine is faster at every size measured, including ten memories. But
at 10 to 50 the gap is 12 to 25 ms, which no one perceives, and you have bought
it with a second source of truth. [Chapter 06](06-adoption.md) puts a healthy
curated store at twenty to a couple of hundred memories. At 200 the default
engine costs 183 ms and this one costs 134 ms — a 49 ms saving on a prompt that
takes seconds to answer.

Turn it on when one of these is true, and not before:

1. **The default engine has crossed your own threshold.** Chapter 03 suggests
   ~150 ms as the point where something is wrong. On the machine measured here
   the default engine crosses 150 ms somewhere between 50 and 200 memories
   (110 → 183) and 300 ms between 500 and 1,000 (260 → 328). On yours those
   numbers are different, which is the entire argument for running `bench.sh`
   instead of trusting this table.
2. **Your machine is the slow part, not your store.** Every measurement here is
   dominated by process startup — about ten `fork`/`exec` pairs per prompt. A
   machine where those cost three times as much has a default engine three times
   slower at the same store size, and the index buys back the part of it that
   scales.
3. **You are past 500 memories and still growing.** By 2,000 the default engine
   costs 486 ms a prompt and this one 250 ms, and the gap keeps widening.

If none of those is true, the right answer is the default engine — and the
better use of the time is [chapter 04](04-loops.md), pruning the store so it
does not get to 2,000 in the first place.

---

## Why it is opt-in

The original design rejected an index as the default, and the reason was not
performance. **An index is a second source of truth for a directory the tool does
not own.** You edit a memory in your editor, delete one with `rm`, pull a
colleague's store from git — and the index knows none of it. The classic failure
of every "just add an index" patch is a deleted file still ranking as a top hit:
a confident answer citing a path that is not there.

The rule this implementation is built around is stated in its own source:

> **A wrong-but-fast answer is worse than a slow-but-right one.**

Four mechanisms enforce it. The first three are about the store; the fourth is
about the engine's own code.

### 1. Staleness is checked on every query, and it is nearly free

One `find`, two answers:

```
a *.md file newer than the stamp   -> that memory was edited
the DIRECTORY newer than the stamp -> something was added, deleted or renamed
```

The directory is the part people leave out, and it is the part that catches a
rename: `mv old.md new.md` does not touch either file's mtime, so no per-file
scan can see it. It is also what makes an editor's atomic save — write a temp
file, rename over the original — visible.

The stamp file does two jobs with one inode. Its **mtime** is what `find -newer`
compares against; its **contents** are the memory count, which the shell reads
with no forks at all. And it is written *before* each scan, deliberately: a
memory edited while the index is building then looks newer than the stamp and is
picked up by the next query, instead of being silently missed until something
else happens to change.

### 2. A stale index is repaired inline, incrementally

Only the files that actually changed are re-read. The common case — you edited
one memory since the last prompt — costs one file open. Deletions and renames go
through a path-set diff between the index and the store; no memory is read to
work out what vanished.

### 3. Every hit is checked against the filesystem before it is printed

Redundant with the two guards above, and that is the point: it is the one
guarantee that does not depend on the index being right. An index can be wrong.
A file either exists or it does not. The check runs *before* the limit is
applied, so a row for a deleted file costs nothing rather than costing a slot.

Proved, not asserted — this is `bench.sh --proofs`, check 3, verbatim:

```
== 3. the staleness guard ==
top hit:        harborlight-queue-backpressure-0105.md
still indexed:  1 row(s)
after rm:       not returned  OK
index rows now: 0
```

### 4. If `eve` itself changes, the engine stops trusting itself

This is the objection the design cannot argue its way out of, so it is worth
stating plainly: **the scorer in the engine is a transcription of the one in
`bin/eve`.** `bin/eve` embeds its ranking inline and there is no library to
share, so the formula lives in two places, and the day someone improves one of
them the other silently starts answering a different question.

That is not hypothetical. It happened three times while this engine was being
written. The default scorer moved to inverse document frequency, then to
word-boundary matching and a light stemmer, then to a different IDF again — and
each time the transcription here went on cheerfully returning the *old* ranking,
in perfect agreement with itself.

So the same `find` that watches the store also watches `bin/eve`. If `bin/eve` is
newer than the index, this engine falls back to the program it copied. Degrading
to the canonical implementation is always safe; quietly ranking differently from
it is not. Re-arm with `eve index --engine sqlite`.

```
== 7. eve itself changing disarms the engine ==
fell back to the default engine  OK
and re-arms after a rebuild: 1/1 queries agree (1 of 1 returned hits)
```

And two ways to check the copy yourself, both in `bench.sh`:

- **`--proofs` check 0** extracts every line of scoring arithmetic from both
  files, strips comments and indentation, and diffs the sequences. A dozen
  queries can miss a changed constant; a diff cannot. Current state:
  `identical: 16 scoring lines`.
- **`eve-engine-sqlite verify`** runs a query list through both engines and
  prints every disagreement, on *your* store rather than a synthetic one.

### 5. Anything else at all falls back, silently

No `sqlite3`, no FTS5 support, an unreadable or corrupt index, a query that will
not run, a repair that fails: re-exec `eve search` on the default path and say
nothing. A UserPromptSubmit hook that reports errors reports them on every prompt
for the rest of the session.

```
== 6. fallback with no sqlite3 in PATH ==
sqlite3 present: no
output identical to the default engine, 3 hit(s)  OK

== 8. a corrupt index falls back too ==
output identical to the default engine  OK
```

---

## Does it return the same memories?

Same queries, both engines, ids compared in order. The second number is the one
that keeps the first honest — two engines agreeing that a query has no answer is
agreement about nothing.

| store | result |
|---:|---|
| 50 | 17/17 agree (12 of 17 returned hits) |
| 200 | 17/17 agree (12 of 17) |
| 400 | 17/17 agree (12 of 17) |
| 700 | 17/17 agree (11 of 17) |
| 1,000 | 17/17 agree (8 of 17) |
| 2,000 | 17/17 agree (7 of 17) |

The queries are half hand-written and half derived from titles in the store being
measured, so most of them have an answer by construction. The earlier version of
this check used a fixed list of invented questions, and eleven of fifteen
returned nothing from *either* engine: "15/15 agree" was fifteen agreements about
silence. If you take one thing from this section, take that one.

### Where they can legitimately differ

The prefilters are not the same, and cannot be:

- The default engine greps for a token as a **substring anywhere in the raw
  file**. Query token `out` therefore matches `timeout`, `rollout` and `about` —
  on the 1,000-memory synthetic store, all 1,000 files.
- This engine matches it as a **word prefix in the index**. `out*` matches
  nothing, because no word in that store starts with "out".

Both then hand their candidates to the *same* scoring rules, which match at a
word boundary — so those extra files score zero and are dropped either way. The
difference is not in ranking, it is in **which files got a seat**: the default
engine spends slots from its 300-candidate cap on files that cannot score, and
on a large store that can push a real match past the cap.

This only becomes visible when the cap binds, which needs more than 300 files
matching one query. Below that both engines see everything and the rankings are
identical. Above it they are choosing different 300s. In the measured range they
still agreed on every query, but the mechanism is real and you should know it is
there.

Two smaller ones, both bounded:

- **The body is indexed as its distinct words, not its text.** The scorer only
  ever asks whether a term appears *somewhere* in the body — it counts
  occurrences and then throws the count away — and matches at a word boundary,
  so a set of distinct words answers identically. It is also far smaller, which
  is what keeps the index bounded. `EVE_SQLITE_MAX_WORDS` (600) caps it; the
  build prints a warning if any memory hits the cap.
- **Index-time config is baked in.** `EVE_MAX_LINES` and `EVE_SQLITE_MAX_WORDS`
  are applied when the index is built. Change either and `eve-engine-sqlite
  status` tells you to rebuild.

---

## Does the index grow forever? No, and here is the number

Every incremental update leaves something behind. FTS5 records a deletion as a
marker rather than rewriting the segment it lives in, and SQLite does not return
free pages to the filesystem, so an index that is only ever patched grows even
when the store does not.

Measured on a 2,000-memory store:

| | bytes |
|---|---:|
| freshly built | 3,235,840 |
| after 100 edits | 3,739,648 (+15.6%) |
| of which reclaimable free pages | 332 K (81 pages) |

So most of it is real segment churn, not slack. Two statements fix it:

```sql
INSERT INTO ftx(ftx) VALUES('optimize');   -- 29 ms, merges the segments
VACUUM;                                     -- 32 ms, 4,329,472 -> 3,227,648
```

61 ms to come back to the freshly-built size. The engine runs both every
`EVE_SQLITE_COMPACT_EVERY` updates (default 200), which bounds the file at
roughly 1.3× its minimum and costs a third of a millisecond per edit amortised.

Proved on a 1,000-memory store with the threshold lowered to 20 so the loop
crosses it three times:

```
== 5. the index stays bounded under churn ==
fresh build:      1671168 bytes
after 60 edits:   1642496 bytes
and it still agrees: 17/17 queries agree (8 of 17 returned hits)
```

---

## Install

See [`../engines/README.md`](../engines/README.md) for the interface contract and
the exact patch a maintainer applies to `bin/eve` — three insertions,
twenty-two lines, no existing line modified.

```sh
mkdir -p ~/.eve/engines
cp engines/sqlite/eve-engine-sqlite ~/.eve/engines/
chmod +x ~/.eve/engines/eve-engine-sqlite

eve index --engine sqlite
printf 'EVE_ENGINE=sqlite\n' >> ~/.eve/config
```

Check it, and check it again in a month:

```sh
~/.eve/engines/eve-engine-sqlite status
~/.eve/engines/eve-engine-sqlite verify < my-real-questions.txt
```

Going back costs nothing — set `EVE_ENGINE=awk` and the index is inert. Delete
`~/.eve/state/eve-fts.db` and its `.stamp` and you have lost a cache. No memory
has ever lived anywhere but `~/.eve/memory`.

### Config

| key | default | what it does |
|---|---|---|
| `EVE_ENGINE` | `awk` | `sqlite` selects this engine. Anything unrecognised, or not installed, uses the default. |
| `EVE_SQLITE_DB` | `$EVE_HOME/state/eve-fts.db` | where the index lives |
| `EVE_SQLITE_MAX_WORDS` | `600` | distinct body words indexed per memory |
| `EVE_SQLITE_AUTOBUILD_MAX` | `400` | above this, a *missing* index is not built inline; the query falls back and waits for `eve index --engine sqlite` |
| `EVE_SQLITE_COMPACT_EVERY` | `200` | incremental updates between compactions |

`EVE_SQLITE_AUTOBUILD_MAX` deserves a sentence. Building an index is the one slow
thing here, and doing it inline on the prompt path is exactly the second-long
stall that gets a hook uninstalled. Below the threshold the build is cheap enough
not to matter (192 ms at 50 memories) and happens automatically; above it, the
query is served by the default engine and the build waits for you to ask.
Silence either way.

---

## Portability notes

Targets stock macOS and stock Linux, same as everything else in the repo: POSIX
`sh`, no bash 4 syntax, no `local`, no arrays, no `eval`, no `timeout(1)`, no
`realpath`, no non-portable `stat` flags. The only added dependency is `sqlite3`,
and its absence is a silent fallback rather than an error.

**One trap worth writing down, because it fails silently.** Current `sqlite3`
CLIs escape control characters in their text output modes. Joining columns with
`char(31)` — the same 0x1f separator the rest of Eve uses, chosen because it is
not IFS whitespace — arrives as the two printable bytes `^_`:

```
$ sqlite3 x.db ".mode list
  SELECT 'a' || char(31) || 'b';" | od -c
0000000   a   ^   _   b  \n
```

`awk` then splits nothing, every field but the first lands in one variable, and
the engine returns no hits while reporting perfect health. This engine uses
`.mode line` instead, which has no separator to escape, has been in the CLI
approximately forever, and lets one `awk` both parse and score. **Never build a
record format on a control character you did not put there yourself.**

### What has not been tested

One machine, one filesystem, one `sqlite3`. Everything above was measured on
Apple Silicon with APFS on internal NVMe and `sqlite3` 3.51.0, warm cache. Not
measured: spinning disks, network or encrypted filesystems, a loaded machine,
Linux, or older `sqlite3` builds — including ones without FTS5, where the
fallback path is exercised but the fast path never runs.

That gap is the whole reason `bench.sh` ships next to the engine rather than
just its output. If you are on any of those, the table above is a hypothesis
about your machine, and the script is how you replace it with a measurement.
