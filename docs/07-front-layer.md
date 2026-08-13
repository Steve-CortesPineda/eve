# The front layer

An agent that knows what you were doing beats one that asks.

Tiers 0 and 1 give the agent a memory store and make it search that store on
every prompt. That fixes "what do I know?" It does not fix "what were we in the
middle of?" So every session still opens the same way: you re-type the branch
you are on, the file you were editing, the thing you were blocked by. It is
thirty seconds of typing, it is the same thirty seconds every time, and it is
thirty seconds you spend before any work starts.

Your machine already knows most of it. The branch is in `.git/HEAD`. The files
you touched have modification times. The last session left a log. The front
layer reads those cheap local signals on an interval and composes a short,
factual briefing, so the session opens with the answer already in it:

```
Where you left off -- last 12h of local activity, as of 2026-08-13T19:17:41Z.
- harborlight [feat/cursor-pagination, 3 uncommitted] docs/pagination.md, src/api/manifest.go (just now)
- In flight: Replacing offset pagination in /v3/manifests with an opaque cursor; Rye is reviewing the migration script
- Unresolved: Whether v2 clients get a deprecation window or a hard cutover
- Last session 2026-08-12: 2 entries
```

That is 415 characters. It is not a summary of your work; it is the five facts
you would otherwise have typed.

**This layer is optional and off until you configure a root.** Tiers 0 and 1 are
the product. This is the convenience on top, and it is the piece that costs the
most trust, so it is also the piece documented in the most detail.

---

## The three pieces

| Piece | What it is | When it runs |
|---|---|---|
| `eve-sample` | takes one sample of local signals and appends what changed to a log | on an interval, from launchd or cron |
| `eve-brief` | composes the briefing from that log plus your memory store | on the same interval, or on demand |
| `eve-front` | the CLI: `brief`, `recall`, `remember`, `sync`, `doctor`, `sample`, `sampler` | when you type it |

The SessionStart hook does not run either of the first two. It reads
`~/.eve/state/brief.md` if that file is fresh, and ignores it otherwise. **No
work happens on the prompt path.** A hung sampler, a slow disk, or a local model
that takes nine seconds cannot delay a single prompt, because none of them are
on it.

---

## Exactly what is collected

Everything below is written to `~/.eve/state/activity.log` and nowhere else.
Nothing is sent anywhere. There is no network call in this layer at all.

| Signal | Default | Recorded | Never recorded |
|---|---|---|---|
| changed files | on | repository-relative paths and a count: `src/api/manifest.go` | file contents, diffs, sizes, anything outside your configured roots |
| git state | on | branch name, number of uncommitted files, short commit id | commit messages, author, remote URLs, diffs |
| frontmost app | **off** | the application name: `Terminal` | window titles, document names, URLs, tab titles, anything typed |

A real log looks like this. Tab-separated, one line per observation:

```
1786648645	2026-08-13T19:17:25Z	git	harborlight	feat/cursor-pagination	0	34ab141
1786648653	2026-08-13T19:17:33Z	git	harborlight	feat/cursor-pagination	3	34ab141
1786648653	2026-08-13T19:17:33Z	files	harborlight	2	docs/pagination.md	src/api/manifest.go
```

Fields are `epoch`, `iso8601`, `kind`, `scope`, then payload. You can read it,
`grep` it, and delete it. It is a text file you own.

### What it does not do, on purpose

- **It never scans your disk retroactively.** The first run creates a marker
  file and reports nothing at all. Every later run reports only files newer
  than that marker. Install it today and it knows nothing about yesterday.
- **It never reads window titles**, only application names. A window title is
  the name of the document you have open, the subject of the message you are
  reading, or the URL you are on. An app name is "you were in a terminal." The
  second is enough to write a useful brief; the first would turn the log into a
  record of what you looked at.
- **It never leaves the configured roots.** `/` and `$HOME` are refused as
  roots. `find` is invoked without `-L` and matches `-type f`, so a symlink
  inside a root cannot walk out of it.
- **It skips the usual noise** — `.git`, `node_modules`, `.venv`, `target`,
  `dist`, `build`, and a dozen more (`EVE_SAMPLE_IGNORE`).
- **It writes a change log, not a heartbeat.** If nothing changed, nothing is
  written. Two thousand lines cover months of real use.

---

## Turning each signal off

All of it is off until you name a root, and each signal has its own switch in
`~/.eve/config`:

```sh
# The whole layer. Empty (the default) means nothing is watched at all.
EVE_SAMPLE_ROOTS=/Users/you/src/harborlight:/Users/you/src/harborlight-docs

EVE_SAMPLE_FILES=1     # 0 = never record file paths
EVE_SAMPLE_GIT=1       # 0 = never record branch or dirty state
EVE_SAMPLE_APPS=0      # 1 = record the frontmost app name (macOS, opt-in)

# How much of a path is recorded:
#   full   src/api/manifest.go     (default)
#   dirs   src/api                 (directory only -- filenames can be sensitive)
#   count  nothing but "4 files changed"
EVE_SAMPLE_PATHS=full
```

`EVE_SAMPLE_PATHS=dirs` is the setting to reach for on a work machine where
filenames leak more than you want (`src/customers/northwind-migration.sql` is a
fact about a customer). `count` keeps only the shape of the day.

To stop everything without uninstalling anything: `EVE_DISABLE=1` in the config,
or delete the schedule. To erase what has been collected:

```sh
rm ~/.eve/state/activity.log ~/.eve/state/sampler.marker ~/.eve/state/brief.md
```

Nothing else in Eve depends on those files. Deleting them costs you one brief.

`EVE_SAMPLE_APPS=1` triggers a macOS Automation consent prompt the first time it
runs. If you decline it, the sampler records no app names, forever, and nothing
else changes. On Linux the signal does not exist and the code path is skipped.

---

## Install

The front layer ships in `eve/` and installs itself into `$EVE_HOME/bin`:

```sh
./eve/bin/eve-front install
```

That copies four files (`eve-front`, `eve-sample`, `eve-brief`,
`front-common.sh`) plus two scheduling templates into `~/.eve`. It touches
nothing else, and re-running it prints `unchanged` for every file that already
matches. Installing into `$EVE_HOME` matters because a scheduled job needs a
path that survives you moving or deleting the clone.

Then name your roots and take a first sample:

```sh
printf 'EVE_SAMPLE_ROOTS=%s\n' "$HOME/src/harborlight" >> ~/.eve/config
~/.eve/bin/eve-front sample --verbose     # first run only sets the marker
~/.eve/bin/eve-front sample --verbose     # after this, changes show up
```

If you want one command instead of two, symlink it. The passthrough is
self-aware and will not call itself:

```sh
ln -s ~/.eve/bin/eve-front ~/bin/eve     # only if you did not install the core `eve`
```

---

## Scheduling

Ten minutes is a good interval. The sample costs one directory walk over your
project roots and a couple of `git` calls.

### macOS (launchd)

```sh
eve-front sampler plist > ~/Library/LaunchAgents/local.eve.sampler.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.eve.sampler.plist
```

`eve-front sampler plist` fills the placeholders in
`eve/templates/sampler.plist` with your real paths. Read it before you load it.
`RunAtLoad` is deliberately false: the first sample after a reboot has nothing
useful to say, and a login-time job that walks directories is a bad neighbour.

To also refresh the brief on the same tick, schedule a second job running
`eve-front brief --write --quiet`, or call it from the same wrapper.

### Linux, or macOS without launchd (cron)

```sh
eve-front sampler cron            # inspect it first
crontab -l > /tmp/ct 2>/dev/null || true
eve-front sampler cron | grep -v '^#' >> /tmp/ct
crontab /tmp/ct
```

The generated line sets `PATH` inline. Cron runs with a nearly empty
environment, and without that the sampler silently loses `git` — branch and
dirty state quietly vanish from the brief while every exit code still says
success.

### Uninstall

launchd:

```sh
launchctl bootout gui/$(id -u)/local.eve.sampler
rm ~/Library/LaunchAgents/local.eve.sampler.plist
```

cron:

```sh
crontab -e        # delete the eve-sample line
```

Then, if you want the collected data gone as well:

```sh
rm -rf ~/.eve/state/activity.log ~/.eve/state/sampler.marker \
       ~/.eve/state/brief.md ~/.eve/state/sampler.err.log
rm -f  ~/.eve/bin/eve-front ~/.eve/bin/eve-sample ~/.eve/bin/eve-brief \
       ~/.eve/bin/front-common.sh
rm -rf ~/.eve/templates
```

**No uninstall step touches `~/.eve/memory`.** Nothing in this layer ever
deletes a memory; `eve-front sync` is the only command that deletes anything at
all, and only inside `~/.eve/mirrors`, and only files carrying its own generated
header.

---

## The CLI

```
eve-front brief              compose and print the briefing
eve-front brief --write      also update ~/.eve/state/brief.md
eve-front recall <query>     search the memory store
eve-front remember "<fact>"  write one durable memory
eve-front sync               export memory/ to a mirror for another agent
eve-front doctor             check whether any of this actually works
eve-front sample             take one sample now
eve-front sampler status|plist|cron
eve-front install            copy the front layer into $EVE_HOME/bin
```

Anything else is passed through to `$EVE_HOME/bin/eve`, so `eve-front index`
works when the core engine is installed.

`recall` is a thin wrapper over the retrieval engine documented in
[03-hooks.md](03-hooks.md#the-retrieval-engine-eve-search) — it does not
implement its own scoring.
Exit 0 with no output means nothing cleared the relevance gate, which is the
common case and not an error.

`remember` writes one memory file in the standard format
([02-memory-format.md](02-memory-format.md)) and is idempotent: the same fact
twice finds the existing file instead of creating a second one. It prints a
reminder to go add the evidence, because a rule without its "why" gets applied
literally and wrongly the first time the situation is slightly different.

```
$ eve-front remember --type feedback --tag deploy \
    "Deploys to Harborlight staging are blocked after 18:00 UTC. The nightly
     manifest reconciliation job takes a lock on the shipments table at 18:15."
wrote ~/.eve/memory/deploys-to-harborlight-staging-are-blocked-after.md
Add the evidence: why is this true, and what should change because of it?
```

---

## The working-state file

Two of the brief's lines come from your memory store, not from the sampler:

```markdown
**In flight:**
- Replacing offset pagination in /v3/manifests with an opaque cursor
- Rye is reviewing the migration script

**Unresolved:**
- Whether v2 clients get a deprecation window or a hard cutover
```

Put those sections in `~/.eve/memory/working-state.md` (rename it with
`EVE_FRONT_STATE_MEMORY`). It is an ordinary memory file — no new format, no new
parser, no new directory. If the file does not exist, those lines are simply
absent from the brief.

This is the part machines cannot infer. A sampler can see that you edited
`manifest.go`; it cannot see that you are waiting on a review, or that the
question you could not answer yesterday is still open.

---

## Verifying it works

Do not ask Claude whether it read the brief. Run the probe and read the bytes:

```
$ eve-front doctor
eve front layer 0.1.0 -- doctor

PASS  EVE_HOME exists: ~/.eve
PASS  memory store: 2 file(s)
PASS  front layer installed in ~/.eve/bin

      effective config:
        EVE_HOME=~/.eve
        EVE_DISABLE=0
        EVE_SAMPLE_ROOTS=/Users/you/src/harborlight
        EVE_SAMPLE_FILES=1
        EVE_SAMPLE_GIT=1
        EVE_SAMPLE_APPS=0
        EVE_SAMPLE_PATHS=full
        EVE_SAMPLE_MAX_PATHS=12
        EVE_FRONT_HOURS=12
        EVE_FRONT_MAX_CHARS=500
        EVE_FRONT_STATE_MEMORY=working-state
        EVE_FRONT_COMPOSER=(none)

PASS  sampler roots all exist
PASS  sampler ran just now
      schedule: launchd job local.eve.sampler is loaded
PASS  activity log: 102 line(s), ~/.eve/state/activity.log
PASS  brief composes: 415 chars, budget 500
PASS  brief.md is fresh (just now)
PASS  retrieval works; probe "working state" returned:
        2140	2	~/.eve/memory/working-state.md	Current working state
PASS  3 Eve hook(s) registered
        ok      ~/.eve/hooks/eve-recall.sh
        ok      ~/.eve/hooks/eve-session-end.sh
        ok      ~/.eve/hooks/eve-session-start.sh

No failures.
```

Two of those checks exist because of specific failures that are easy to ship and
hard to notice:

- **The effective config is printed as the scripts resolve it**, not as the file
  reads. A config value is only real if the process that needs it can print it.
  A key that is set but never reaches the process looks identical to a key that
  is working, right up until you notice the default was in effect all along.
- **The retrieval check runs a query and prints the result.** "Configured
  correctly" is not evidence. A call returning success only means the call
  returned. See [05-design-laws.md](05-design-laws.md).

`doctor` exits non-zero if anything FAILs, so it can gate a script.

---

## How it fails

| Situation | Behaviour |
|---|---|
| no roots configured | sampler exits 0, writes nothing. This is the default. |
| `$EVE_HOME` missing | every command exits 0 silently |
| `EVE_DISABLE=1` | sampler and brief exit 0 immediately |
| first ever run | marker created, nothing reported |
| root does not exist | skipped; `doctor` reports it as FAIL |
| root is `/` or `$HOME` | skipped; `doctor` reports it as FAIL |
| no `git` binary | branch still read from `.git/HEAD`; dirty count shown as `-` |
| two samplers at once | `mkdir` lock; the loser exits 0. A stale lock is broken after 10 minutes. |
| log grows | trimmed to the last 2,000 lines, write-temp-then-rename |
| nothing to report | brief prints nothing. Silence is a valid brief. |
| brief would be header-only | prints nothing rather than an empty briefing |
| brief is stale | SessionStart ignores a file older than two hours |
| composer fails, hangs, or is missing | the deterministic brief is used |
| filenames with spaces or non-ASCII | handled; NUL-separated enumeration throughout |
| a filename containing a tab | tab replaced with a space, so a path cannot forge a field boundary |

A stale brief is treated as worse than no brief. A briefing that asserts a
"current focus" from four days ago is confidently wrong, and confidently wrong
costs more than silent.

---

## Design notes

**Why a change log instead of a heartbeat.** Sampling every ten minutes and
recording state every time produces 144 near-identical lines a day and a log
that must be rotated aggressively. The sampler compares each signal against the
last recorded value and writes only on change, which makes the log a history of
what happened rather than a record of how often it looked.

**Why a marker file instead of a time window.** "Files modified in the last N
minutes" needs date arithmetic that differs between BSD and GNU `date`, and it
either double-reports or drops changes whenever a run is late. `find -newer
marker` is POSIX, has no timezone semantics, and self-corrects: if a run is
skipped, the next one covers the gap exactly once. It also means the tool
cannot look further back than its own installation, which is a privacy property
you get for free from the simpler design.

**Why no model on the prompt path.** `EVE_FRONT_COMPOSER` can pipe the brief
through a local model. It runs on the sampler's schedule and writes a file; the
SessionStart hook only reads that file. If the model is slow, absent, or broken,
the deterministic text stands and nothing about your session changes. This is
the difference between an optional dependency and a load-bearing one.

**Why one file writes `brief.md`.** If the Tier 2 brief loop and this layer both
write it, the file's contents depend on whichever ran last, and debugging that
means finding both writers first. One writer per path, named in the header
comment of the file that writes it. If you install both, disable one.

**Why the brief is capped and drops whole lines.** It is paid for on every
session start. `EVE_FRONT_MAX_CHARS` defaults to 500, and the budget is enforced
by dropping trailing lines, never by truncating one — half a fact reads exactly
like a whole fact.

**Why angle brackets are stripped.** The brief is injected into the model's
context inside a tagged block, and it contains file paths. Paths are the one
part of the brief that something other than you can influence. Replacing `<`
and `>` means no filename can close the block and start writing instructions.
The brief carries paths and counts, never file contents, which keeps that
surface as small as it can be.
