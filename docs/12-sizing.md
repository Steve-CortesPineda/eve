# 12 · Sizing: is this tuned for *your* computer?

No. Not yet.

Every constant in this repo — the 3-memory recall limit, the 1,200-character
injection budget, the 300-candidate cap, the 400-line-per-file scan bound — was
chosen on one machine, by one person, watching one set of numbers. That is a
starting point, not evidence about your laptop. This chapter exists so you can
stop trusting those numbers and go get your own, and so that the two questions
people actually ask get answered with measurements instead of reassurance:

1. **Will this fill my disk?** No. Not close. Skip to
   [Disk is not the constraint](#disk-is-not-the-constraint) for the numbers.
2. **Will this make every prompt slower?** Yes, by a bounded amount that depends
   on your machine far more than on your store. That is the rest of the chapter.

Everything below was measured while writing it. Where a number is missing, it is
missing because the measurement was not run — not filled in with an estimate.

---

## The rule this chapter serves

From [chapter 3](03-hooks.md):

> A hook that adds a second to every prompt gets uninstalled, and the memory
> system dies with it.

`eve-recall.sh` runs before every turn you take. Everything else in Eve is
optional or occasional; this one thing is on the critical path of your typing.
So the only performance question that matters is: **what does one prompt cost on
this computer, right now, with what I actually have running?**

---

## The measured curve

Ten prompts per point, fed through the real `UserPromptSubmit` hook — process
startup, JSON parse, retrieval, dedupe bookkeeping, output cap, all of it.
Nothing stubbed. Default `grep`+`awk` engine, warm page cache, synthetic stores
whose files average 1,523 bytes (the four example memories in this repo are
1,327–1,435 bytes, so the fixtures are the right shape).

| Memories | Run 1 | Run 2 | Store on disk |
|---:|---:|---:|---:|
| 10 | 71.5 ms | 71.3 ms | 40 KB |
| 50 | 84.0 ms | 82.4 ms | 0.20 MB |
| 200 | 128.5 ms | 132.0 ms | 0.78 MB |
| 500 | 183.0 ms | 192.5 ms | 1.95 MB |
| 1,000 | 258.2 ms | 245.9 ms | 3.91 MB |
| 2,000 | 359.1 ms | 364.7 ms | 7.81 MB |

Machine: Apple Silicon desktop, 16 cores, APFS on internal NVMe, `/bin/sh` is
bash 3.2, `jq` present. **Load average 4–5 for the entire run** — real work was
happening on the box at the same time.

That last sentence matters more than any row above it, and here is why.

### These numbers disagree with chapter 3, and that is the lesson

[Chapter 3](03-hooks.md) publishes 201 ms for a 2,000-memory store, measured on
an Apple Silicon *laptop* at 30 iterations per row. This chapter measured 360 ms
for the same store, running the same code, on a desktop at 10 iterations per
row, under load.

Different machine, different iteration count, different background activity. I
did not reproduce chapter 3's conditions and I will not tell you which of those
three explains the gap. What I can do is measure one of them and show that it is
big enough to swallow the whole discrepancy on its own. A 500-memory store, with
sixteen busy-loop processes started and stopped between runs:

```
500 memories, load ~4 (as-is)                167.0 ms/prompt
500 memories, +16 CPU spinners               261.7 ms/prompt      +57%
500 memories, spinners gone                  187.6 ms/prompt
```

**+57% from nothing but contention**, and the run after the spinners were killed
had not fully recovered either. If you run builds, containers, a test suite, or
another agent while you work — and you do — then a benchmark taken on a quiet
machine is describing a computer you do not own.

Two published tables, same repo, differing by 80%. Neither is wrong. That is
what "the constants were chosen on one machine" costs you, and it is the entire
reason this chapter ends with a script instead of a recommendation.

---

## The ~70 ms floor, and what it actually is

At 10 memories the hook already costs 71 ms. Ten memories is nothing; a `grep`
over 15 KB is not 71 ms of work. So most of the cost at the small end has
nothing to do with searching, and no index, no cache, and no cleverer ranking
will move it.

Decomposed, 20 iterations each, same machine and same load:

| What ran | Time |
|---|---:|
| `/bin/sh -c :` — one bare fork+exec, the price of existing | 4.7 ms |
| Hook with `EVE_DISABLE=1` — startup + config parse, then exit | 10.5 ms |
| Hook on a slash command — adds the JSON parse, then exits | 15.5 ms |
| Hook on a too-short prompt — same path | 16.2 ms |
| `eve search` alone against a 10-memory store | 33.6 ms |
| **Hook, full run, 10-memory store** | **71 ms** |

And the unit cost of a single child process, on the same box:

```
one jq field extract      3.7 ms
cat from a pipe           3.2 ms
awk one-liner             3.3 ms
tail -40                  3.0 ms
bare $(printf) subshell   1.6 ms
```

**The floor is process creation.** The hook forks roughly a dozen times, and it
calls `eve search`, which is itself a shell script that forks `find`, `xargs`,
`grep`, `awk`, `sort` and friends. At three to four milliseconds apiece that
arithmetic lands on seventy before any memory has been read.

Three consequences worth internalising:

- **On a small store, a faster search engine buys you nothing.** The retrieval
  child costs 34 ms of the 71 — and almost none of *that* is reading files,
  because at ten memories there are 15 KB of files to read. It is a second shell
  script starting up and forking its own helpers. This is why chapter 3 is so
  insistent about `${f##*/}` over `basename` and about assigning to `$_eve_r`
  instead of using `$(...)`: on this path, forks *are* the program.
- **The floor scales with how expensive a process is on your OS**, not with how
  much memory you have or how fast your disk is. A machine with slow
  `fork`/`exec` — heavy security tooling, an EDR agent inspecting every
  execution, a container with a cold filesystem layer — pays it on every line.
- **`EVE_DISABLE=1` costs 10 ms, not 0.** Turning Eve off does not remove the
  hook from the harness. If you want zero, unregister it.

### The one floor component you can actually remove

The JSON on stdin is parsed by a fallback chain: `jq`, then `python3`, then
`sed -E`. Timed in isolation, both fields (`prompt` and `session_id`), 20
iterations, by forcing each tier:

| Parser tier | Cost per prompt |
|---|---:|
| `jq` | 7.1 ms |
| `python3` | 40.3 ms |
| `sed -E` | 6.5 ms |

`python3 -c pass` alone measured **20.3 ms** on this machine, and the hook calls
it twice.

**If `jq` is not installed, you are paying about 33 ms on every prompt for a
Python interpreter start.** That is a bigger, cheaper win than any tuning
constant in the config file:

```sh
brew install jq        # macOS
sudo apt install jq    # Debian/Ubuntu
```

The `sed` tier is fast because it does almost nothing — it is a
degrade-gracefully path with real limits (it finds the *last* occurrence of a
duplicated key and only undoes common escapes). It is correct enough to keep a
session working, not something to choose on purpose.

---

## Disk is not the constraint

Say it plainly: **you will never run out of disk because of Eve, and there is no
disk-quota feature in this repo because building one would be solving a problem
nobody has.**

The whole store, measured:

| Memories | Content (`wc -c`) | On disk (`du`) |
|---:|---:|---:|
| 200 | 0.29 MB | 0.78 MB |
| 1,000 | 1.45 MB | 3.91 MB |
| 2,000 | **2.91 MB** | **7.81 MB** |

Two thousand curated memories — an enormous store, ten times what a healthy one
looks like — is **7.8 MB**.

For scale, the volume this was measured on had 29.2 GB free — a small, fairly
full boot disk — and that is **3,800 times** the largest store above. A laptop
with 100 GB free has roughly **13,000 times** the headroom: four orders of
magnitude between what Eve can plausibly consume and what is already lying
around unused.

### The one disk fact that is genuinely interesting

Content and allocation are not the same number: 2.91 MB of markdown occupies
7.81 MB of blocks. Memories average 1,523 bytes and the filesystem allocates in
4 KB units, so **roughly 60% of Eve's disk footprint is the rounding**, not the
text.

This matters nowhere for the store and everywhere for the residue directories,
where files are tiny and numerous. A year of `state/seen-<session_id>` files is
959 KB of content and **6.5 MB of blocks**. That is why
[`scripts/housekeeping.sh`](../scripts/housekeeping.sh) reports both numbers
instead of picking the flattering one.

### What the per-file caps already do

Individual files cannot run away, because the code that writes them truncates
them:

| File | Cap | Enforced in |
|---|---|---|
| `state/seen-<session_id>` | last 40 lines | `hooks/eve-recall.sh` |
| `state/whiffs.log` | trimmed to 2,000 lines at 5,000 | `hooks/eve-recall.sh` |
| `state/recall.log` | trimmed to 500 lines at 2,000 | `hooks/lib/common.sh` |
| memory content read per search | `EVE_MAX_LINES`, default 400 | `bin/eve` |
| injected block | `EVE_RECALL_MAX_CHARS`, default 1,200 | both |

What is *not* capped is the **number** of files. That is the next section.

---

## What actually grows: file counts

Three directories gain a file and never lose one:

| Directory | One file per | A year of daily use |
|---|---|---|
| `state/seen-<session_id>` | session | ~1,100 files |
| `sessions/YYYY-MM-DD.md` | day | 365 files |
| `proposals/*.md` | loop run | ~470 files, if you run the loops |

Simulated: 365 days, 3 sessions a day, daily gap reports plus weekly reconcile
and outcome reports, alongside 200 memories and 40 KB documents. Total:
**2,250 files, 8.8 MB.**

Still not a disk problem. It is a *tidiness* problem, and — measured, because
"unbounded file counts slow directory scans" is the kind of claim that sounds
true and deserves a number — it is a small latency problem too.

A 200-memory store, hook run 20 times per block, three interleaved rounds:

```
round 1:  clean state/                       114.0 ms/prompt
          state/ + 1,095 dead seen-files     132.3 ms/prompt
round 2:  clean state/                       120.7 ms/prompt
          state/ + 1,095 dead seen-files     129.3 ms/prompt
round 3:  clean state/                       116.3 ms/prompt
          state/ + 1,095 dead seen-files     128.2 ms/prompt
```

**About +13 ms per prompt, roughly 11%, in the same direction all three rounds.**
The recall hook creates, appends to, truncates and renames a file in `state/` on
every hit, and those operations get more expensive in a directory holding a
thousand entries. Listing the directory went from 2.6 ms to 6.5 ms.

Eleven percent for files that were dead the moment their session ended is not a
crisis. It is just sloppy, and it is free to fix.

### The cleaner

[`scripts/housekeeping.sh`](../scripts/housekeeping.sh) prunes by age, with one
rule at the top that is not negotiable:

> **`memory/` and `kb/` are never garbage-collected.** Not by age, not by count,
> not behind a flag, not with `--force`. The capability does not exist.

Same asymmetry as [chapter 4](04-loops.md): a cleaner you cannot leave on a
schedule is a cleaner nobody runs. It is enforced in three places — every target
is a hardcoded subdirectory name, every candidate must match a fixed filename
pattern, and any directory that *resolves* into a `memory/` or `kb/` tree is
refused outright.

Defaults: `state/` residue 14 days, `sessions/` 180 days, `proposals/` 30 days.
Backups are opt-in and off by default, because they are the last thing standing
between a bad automated edit and a lost memory.

`install.sh` does not copy it into `$EVE_HOME` yet, so run it from the repo, or:

```sh
cp scripts/housekeeping.sh ~/.eve/bin/eve-housekeeping
chmod +x ~/.eve/bin/eve-housekeeping
```

Against the simulated year, `--dry-run`:

```
eve-housekeeping  (dry run -- nothing will be deleted)
store: ~/.eve

  state/seen-*                 1053 files     959 KB  older than 14 days
  state/*.tmp*                    3 files       24 B  interrupted writes
  state/guard-active.*            2 files        0 B  orphaned markers
  sessions/*.md                 185 files     185 KB  older than 180 days
  proposals/*.md                431 files     324 KB  older than 30 days
  state/backups (kept)           53 files       8 KB  opt in with --backups
  state/reconcile-backups        13 files       6 KB  opt in with --backups

  never touched: memory/ (200 files), kb/ (40 files)
                 knowledge is not garbage-collected, at any age.

[dry run] nothing was deleted. Drop --dry-run to remove 1674 files
          (1.4 MB of content, 6.5 MB of disk blocks).
```

Then for real, and then again:

```
$ eve-housekeeping -q
eve-housekeeping: removed 1674 files, 1.4 MB of content, 6.5 MB of disk blocks

$ eve-housekeeping -q
$
```

The second run prints nothing because there is nothing left outside a retention
window; it is idempotent, which is what makes it safe on a schedule. Measured
either side of the first run, the simulated store went from **2,250 files / 8.8
MB** to **576 files / 2.3 MB**.

The SHA-256 of every file under `memory/` and `kb/` is byte-identical before and
after, including after `--older-than 0 --backups`, which selects everything the
script is capable of selecting. Pointed directly at `memory/`, at `kb/`, or at a
subdirectory of either, it exits 2 and removes nothing. If `sessions/` is a
symlink into `memory/`, it exits 2 rather than relying on `find` not descending —
that one is worth knowing about, because on this platform:

```
$ find "$store/sessions"  -maxdepth 1 -type f -name '*.md' | wc -l   ->  0
$ find "$store/sessions/" -maxdepth 1 -type f -name '*.md' | wc -l   ->  2
```

A trailing slash is the difference between a no-op and deleting somebody's
memories, so the guard resolves the physical path instead.

**You do not have to run it.** A year of not running it costs a few megabytes
and about 11% of a hook that takes a tenth of a second. Run it when the file
counts start bothering you, or weekly from cron with `-q`, which prints one line
when it removed something and nothing when it did not.

---

## What actually differs between machines

Ranked by how much they moved the number here, all measured above:

| Factor | How it shows up | Measured effect |
|---|---|---|
| **CPU contention** | Everything scales at once; numbers move between runs | +57% at 500 memories under 16 spinners |
| **`jq` absent** | Flat penalty on every prompt, size-independent | +33 ms/prompt via `python3` |
| **Store size** | Grows the `grep`+scan portion, not the floor | 71 ms → 360 ms from 10 → 2,000 |
| **Dead file count** | Slows the hook's own bookkeeping writes | +13 ms after a year unpruned |
| **Filesystem speed** | Modifier on the scan, not the driver | see below |
| **Process creation cost** | Sets the floor everything else sits on | 4.7 ms per bare fork here |

### Filesystem: less than you would guess, on a warm cache

The 2,000-memory store, copied onto a RAM disk so that *no* I/O reaches storage,
against the same store on APFS/NVMe:

```
2000 memories, APFS/NVMe          295.9 ms/prompt
2000 memories, RAM disk           262.7 ms/prompt
2000 memories, APFS/NVMe (again)  370.3 ms/prompt
2000 memories, RAM disk (again)   272.4 ms/prompt
```

Removing storage from the picture entirely still leaves ~265 ms. **On a warm
cache the work is CPU and process creation, not I/O** — which is the good news
for a spinning disk or a slow SSD, because the page cache absorbs a 7.8 MB store
after the first read.

The bad news is the cases where the cache cannot help you. Every prompt asks
`grep` to open every file in the store. On a **network filesystem** (NFS, SMB, a
synced folder that intercepts reads) or an **encrypted volume that decrypts per
open**, that is thousands of round trips or thousands of decryptions per prompt,
and it does not amortise the way local page cache does. This is the one profile
where store size hurts nonlinearly, and it was **not measured here** — no such
volume was available. Do not take a number for it from this page; take one from
the recipe below, on your own mount. If `$EVE_HOME` is on a network or synced
path, move it to a local disk first and measure second.

### The tuning knob, and its honest ceiling

`EVE_CANDIDATE_CAP` (default 300) bounds how many files the scorer may read.
Interleaved A/B, seven blocks of 10 prompts per arm, alternating to cancel drift,
on the 2,000-memory store:

```
EVE_CANDIDATE_CAP=300 (default)    median 360.2 ms  (min 283.8, max 362.5)
EVE_CANDIDATE_CAP=60               median 316.5 ms  (min 311.8, max 324.6)
delta: -43.7 ms (-12%)
```

Twelve percent. Useful, but far less than the knob's name suggests — and reading
[`bin/eve`](../bin/eve) explains why:

```sh
find "$MEMDIR" -maxdepth 1 -type f -name '*.md' -print0 |
    xargs -0 grep -ril -E -e "$PAT" |
    sort >"$TMPD/cand.all"
# ... the cap is applied to cand.all, after this
```

**The `grep` touches every file in the store before the cap exists.** The cap
bounds the scoring pass, not the part that scales with store size. So on a large
store the knob trims the tail and leaves the head, and the real lever is fewer
files or a different engine — not a smaller cap.

### And the cap is a correctness knob, not just a speed knob

Turn it down and you do not get the same answers faster. You get *different
answers*. Same query, same store, one fresh session per run:

```
cap=300  -> harborlight-manifest-ingest-1133  harborlight-manifest-ingest-0477  harborlight-manifest-ingest-0385
cap=100  -> harborlight-cache-warming-1061    harborlight-cache-warming-1942    harborlight-auth-handshake-0019
cap=60   -> boxcar-manifest-ingest-0072       boxcar-manifest-ingest-0356       boxcar-manifest-ingest-1107
```

Three disjoint result sets. The cap is applied *before* scoring, so a memory
outside it cannot be returned however well it matches — `bin/eve` mitigates this
by letting filename matches jump the queue, but when more files match the
filename than the cap allows, the cap itself decides the answer.

Two honest caveats. This fixture is synthetic and deliberately repetitive — a
dozen fictional project names crossed with twenty subjects — so term overlap is
far heavier than in a real store of distinct claims, and the effect is
correspondingly amplified. And the search is genuinely ambiguous: on 2,000
memories about ingest and retries, "which three" was never well defined.

The mechanism is real regardless, and it is the reason to be suspicious of a
recommendation to "just lower the cap for speed." If you turn it down, check
that `eve search` still returns what you expect for the queries you care about.
Twelve percent of 360 ms is not worth a store you can only see part of.

A first attempt at this measurement, six configurations run once each in
sequence, produced a nonsense ordering: `EVE_MAX_LINES=120` came out *slower*
than 400, and a repeat of the defaults landed 58 ms away from its first run.
Under load, a single 10-prompt run has more noise in it than the effect being
measured. If you tune, interleave the arms and take medians, or accept that you
are reading noise.

---

## Machine profiles

Pick the row that matches your box. Every recommendation is either a measurement
from this page or an instruction to go take one.

| Profile | What you will probably see | Do this |
|---|---|---|
| **Fast desktop, mostly idle** | Roughly chapter 3's table: 63 ms at 50 memories, 90 at 200 | Nothing. The defaults were tuned on a machine like yours — which is a description of the problem, not a compliment. |
| **Modest laptop** (older, 4–8 cores, SSD) | A higher floor: forks cost more, so every row shifts up together | Install `jq` (33 ms, free). Then measure. If a normal store lands under 150 ms, stop. |
| **Loaded machine** (builds, containers, other agents) | +50% or more, and numbers that move between runs | Measure *while working*, not on a quiet box. Interleave A/B arms. Do not chase 20 ms you cannot reproduce. |
| **Huge store** (1,000+ memories) | 250 ms+, dominated by the whole-store `grep` | First ask whether the store should be that big — see [chapter 6](06-adoption.md) on when to stop growing it. `EVE_CANDIDATE_CAP=60` buys ~12% and changes which memories are reachable; verify your real queries before keeping it. |
| **Slow / network / synced filesystem** | Unknown, and potentially much worse — thousands of file opens per prompt with no page-cache relief | Move `$EVE_HOME` to a local disk. If you cannot, measure before and after with the recipe below; this page has no number for you. |
| **Low-memory box** | The store stops fitting in page cache; the RAM-disk result above stops applying and I/O reappears | Keep the store small, run housekeeping, and re-measure — a cold-cache curve is a different curve. |
| **`jq` not installed** | A flat ~33 ms tax on every prompt regardless of store size | Install `jq`. Highest-value change on this page. |
| **Anything over ~150 ms with a normal store** | Something specific is wrong, not "slow computer" | One enormous file in `memory/`, `$EVE_HOME` on a network mount, a `python3` on the parser path, or a year of unpruned `state/`. Check in that order. |

---

## Measure your own

Do not trust this page. It is one machine, and it was busy.

**The tool:**

```sh
eve bench
```

It times the real hook against your real store, reports p50 and p95 rather than
a mean (a hook that is usually 80 ms and occasionally 900 ms reads as "sometimes
it hangs", and its mean looks fine), and separates the fixed floor from the part
your store size explains. On the 200-memory fixture used throughout this
chapter it printed:

```
-- where the time goes (at p50)
  floor        71 ms   51%  process startup, forks, config and JSON parse
  search       68 ms   49%  attributable to your 200 memories
```

Note the floor: **71 ms**, from a harness written independently of the one that
produced the table at the top of this chapter, which measured 71.5 and 71.3 ms.
Two separate measurement paths landing on the same number is the closest thing
to confirmation available here.

Everything below is the dependency-free version — useful if you are on a machine
without the CLI installed, and the only way to get a *curve* rather than a point.

**The 20-second version** (also in [chapter 3](03-hooks.md)):

```sh
time (i=0; while [ $i -lt 20 ]; do
  printf '{"prompt":"how do we handle retries","session_id":"bench"}' \
    | ~/.eve/hooks/eve-recall.sh >/dev/null
  i=$((i + 1))
done)
```

Divide by 20. That is your real per-prompt cost, on your machine, with whatever
you have running right now — which is the only number that matters.

**A curve of your own**, if you want to know where *your* store size starts to
hurt. This copies your real memories into a throwaway store and duplicates them
up to each size, so the file shapes are yours, not synthetic:

```sh
#!/bin/sh
# Latency vs store size, using your own memories as the fixture.
set -u
SRC=${EVE_HOME:-$HOME/.eve}/memory
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/memory" "$TMP/state"
cp "${EVE_HOME:-$HOME/.eve}/bin/eve" "$TMP/bin/eve"

for n in 10 50 200 500 1000; do
  rm -f "$TMP"/memory/*.md
  i=0
  while [ "$i" -lt "$n" ]; do
    for f in "$SRC"/*.md; do
      [ -f "$f" ] || continue
      [ "$i" -lt "$n" ] || break
      cp "$f" "$TMP/memory/copy$i-${f##*/}"
      i=$((i + 1))
    done
    [ "$i" -gt 0 ] || break          # empty store: nothing to measure
  done
  printf '{"prompt":"warm the cache please","session_id":"w"}' \
    | EVE_HOME="$TMP" ~/.eve/hooks/eve-recall.sh >/dev/null 2>&1
  printf '%5s memories: ' "$n"
  s=$(date +%s)
  j=0
  while [ "$j" -lt 20 ]; do
    printf '{"prompt":"how do we handle retries in the ingest path","session_id":"b%s"}' "$j" \
      | EVE_HOME="$TMP" ~/.eve/hooks/eve-recall.sh >/dev/null 2>&1
    j=$((j + 1))
  done
  e=$(date +%s)
  echo "$(( (e - s) * 1000 / 20 )) ms/prompt"
done
```

Second-resolution `date` over 20 iterations gives you ±50 ms, which is fine for
finding the knee and useless for measuring a 12% config change. For that, use
the interleaved approach above and take medians.

**Then check the three things that are usually the actual answer:**

```sh
command -v jq  ||  echo "no jq: you are paying ~33 ms/prompt for python3"
ls ~/.eve/state | wc -l                      # thousands? run housekeeping
df -h ~/.eve | tail -1                       # a network mount here is the problem
```

If your own numbers come out materially different from this chapter's, the
chapter is the thing that is wrong about your computer. Open an issue with the
`eve bench` output — a second machine profile is worth more to this page than
anything else in it.

---

## What this chapter is not

It is not a claim that Eve is fast. Measured here it is 71 ms at ten memories
and 360 ms at two thousand, on the critical path of every prompt you type,
forever — and whether that is worth it depends on how often the memory saves you
from re-explaining something. The eval in [chapter 10](10-evals.md) is the other
half of that trade.

It is also not a promise that these numbers hold anywhere but here. That is the
entire point of publishing the method alongside the results: **the constants in
this repo were chosen on one fast machine, and one machine is not evidence.**
Run the benchmark. If your curve disagrees with this table, your curve is right.
