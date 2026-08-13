# Loop 2 — reality reconcile

**Consumer: you, reading `$EVE_HOME/proposals/reconcile-<date>.md` and deciding what to rewrite. Second consumer: the model, which sees an `eve:stale` marker inline when it opens or retrieves a file whose check failed.**

Those are the only two. If you never read the proposal and never run `--apply`, this is a cron job that warms your CPU.

**Producer: you**, by putting a check marker in a memory that asserts something checkable:

```markdown
<!-- eve:check file /opt/harborlight/fixtures/manifests.jsonl -->
<!-- eve:check dir  /srv/harborlight -->
<!-- eve:check cmd  harborctl -->
<!-- eve:check host staging.harborlight.internal -->    (needs --net)
<!-- eve:check url  https://staging.harborlight.internal/healthz -->
```

A memory with no markers is never checked. The loop verifies the claims you chose to make checkable — not everything you wrote, and not anything it inferred.

## The problem it addresses

A memory store decays in a specific way: it does not become wrong all at once, it becomes wrong one sentence at a time, silently, while continuing to be retrieved and believed. The host gets decommissioned. The fixture path moves. The helper leaves the repo. Nothing announces this, and the memory that says otherwise keeps ranking first because it is well written and matches your query.

## It never executes anything from a memory file

`cmd harborctl` resolves the name with `command -v`. It does not run the program, with or without arguments. Markers containing a shell metacharacter, a path, or an unknown kind are reported in the "Markers not run" section and skipped.

This matters more than it looks. A memory file is an ordinary file. Anything with a write tool can append to it — including a prompt injection that got that far — and if a marker were a command to run, "put a memory file in the store" would be a remote code execution primitive with a cron job attached. **A marker is a request to look, never a request to run.**

Network checks are off by default for a related reason: a laptop on the wrong network would otherwise "discover" that production has been decommissioned.

## The two gates

Everything here exists to make an automatic write hard to earn.

**1. The streak gate.** A failure has to repeat on `--streak N` consecutive runs (default 3) before anything is written, and runs closer together than `--min-gap` seconds (default 3600) do not count as separate looks. Without the time gate, `for i in 1 2 3; do ...; done` is indistinguishable from three days of evidence, and the streak stops meaning anything.

**2. The premise check — this is the one people skip.** A streak is only evidence if the runs were capable of passing. Repeating a probe against a broken premise does not converge on the truth; it converges on a confident wrong answer, and three runs from the same broken state produce a streak of three, which this loop treats as permission to write. So before any failure is counted:

- **Control probes.** If `/` does not test as a directory or `sh` is not on `PATH`, the machine is not in a state where a negative result means anything. Nothing is counted.
- **A network control host** (`--net` only, default `example.com`). If the control does not resolve, this machine is offline; network checks become `skip`, not `fail`.
- **The mass-failure guard.** If more than `EVE_RECONCILE_MAX_FAIL_PCT` (default 50) of checks fail in one run, the run is inconclusive. An unmounted volume, a fresh clone, the wrong machine — all of them fail most checks at once. One claim going stale is news. All of them going stale in the same instant is a story about the observer.

When a run is inconclusive, streaks are frozen exactly where they were and no edit is made.

## Every write is reversible, and logged as such

With `--apply`, the loop makes exactly two kinds of edit:

- **Mark:** insert one `<!-- eve:stale ... -->` comment directly beneath a check that has cleared the gate.
- **Unmark:** remove that comment when the check passes again.

The loop closes in both directions, which is what keeps the marker meaningful instead of a stain that only accumulates. It never edits frontmatter, never touches prose, never deletes a memory, and never proposes one be deleted.

Before the first edit to a file in a run, the file is copied to `state/reconcile-backups/`. Every edit appends a line to `state/reconcile-audit.log` ending in a literal command you can paste:

```
2026-08-13T13:17:34	mark-stale	harborlight-local-setup.md	cmd harborctl (streak 4)	undo: cp '/…/state/reconcile-backups/harborlight-local-setup.md.20260813T131734.12345.bak' '/…/memory/harborlight-local-setup.md'   # restores the file to its state before this run
```

Verified: running that command restores the file byte-identical to its pre-run state.

## Run it

```sh
# read-only. no proposal file, no streak update, no edits.
$EVE_HOME/loops/reality-reconcile/eve-reconcile.sh --dry-run

# normal run: check, update streaks, write the proposal. still no edits.
$EVE_HOME/loops/reality-reconcile/eve-reconcile.sh

# allow the two automatic edits
$EVE_HOME/loops/reality-reconcile/eve-reconcile.sh --apply

# include host/url checks
$EVE_HOME/loops/reality-reconcile/eve-reconcile.sh --net

# what is currently marked stale
$EVE_HOME/loops/reality-reconcile/eve-reconcile.sh --list-stale
```

`--apply` is opt-in per run on purpose. If you schedule this, schedule the version without it for a month first and read what it would have done.

## Verified output

Against the fixture store (8 memories, 7 markers). On this machine `/etc/hosts`, `/tmp` and `awk` exist; `harborctl` and the fixture path do not:

```
$ EVE_HOME=loops/example-store sh loops/reality-reconcile/eve-reconcile.sh --dry-run

<!-- generated by eve-reconcile.sh on 2026-08-13; regenerable -->

# Claims checked against reality - 2026-08-13

7 checks in 2 memories: 3 passed, 2 failed, 2 skipped.
Network checks: network checks not requested (--net)
Streak gate: 3 consecutive failing runs, at least 3600s apart.

## Failing, gate cleared (0)

Nothing has failed often enough to act on.

## Failing, still accumulating (2)

| memory | check | detail | runs so far |
|---|---|---|---|
| harborlight-local-setup.md | `cmd harborctl` | not on PATH | 1 of 3 |
| harborlight-local-setup.md | `file /opt/harborlight/fixtures/manifests.jsonl` | no such file | 1 of 3 |

A single failing run is a bad network, a half-finished checkout, a
volume that was not mounted yet. It is not news.


[dry run] no proposal file, no streak update, no edits.
Streaks shown above are what IS on disk, not what this run would write.
```

After three counted runs the same failures clear the gate, and with `--apply` the marker lands directly under its own check:

```
<!-- eve:check cmd harborctl -->
<!-- eve:stale 2026-08-13 cmd harborctl failed 4 consecutive runs; claim above is unverified -->
```

Fixing the world reverses it. With `harborctl` back on `PATH`:

```
## Recovered (1)

These failed before and pass now. Their streaks are reset and any stale marker was removed.

- harborlight-local-setup.md: `cmd harborctl`
```

And the premise check, exercised against a store whose claims describe a machine this is not (3 of 4 checks failing):

```
## RUN INCONCLUSIVE - no failure below was counted

3 of 4 checks failed in one run (over 50%), which is a statement about this machine, not about your memories.

Streaks were left exactly as they were and no edit was made. Repeating a
probe whose premise is broken does not converge on the truth, it converges
on a confident wrong answer -- three runs from the same broken state is a
streak of three, and a streak is what this loop treats as permission to
write. Fix the machine, then run again.
```

Four consecutive inconclusive runs with `--apply` produced zero streak rows and zero edits. Malformed markers in the same store were reported and skipped rather than run:

```
## Markers not run (3)

- wrong-machine.md:11 shell metacharacter in argument: cmd $(whoami)
- wrong-machine.md:12 cmd takes a bare name: cmd ../../bin/sneaky
- wrong-machine.md:13 unknown kind: smell /etc

Nothing in a memory file is executed. A marker that looks like it wants
a shell is reported and skipped.
```

## Bugs found while building this, all of the same family

Each of these produced correct-looking output:

- **Insertions used stale line numbers.** Two markers going into one file were inserted in ascending order, so the second landed one line late and attached itself to a claim it was not about. Edits now run descending by line within each file.
- **The undo did not undo.** Backups were stamped to the second and taken per edit; two edits to one file inside the same second wrote the same backup filename, and the second copy overwrote the first with the already-modified file. The audit log still printed an undo command, and it still ran, and it restored the wrong state. Now: one backup per file per run, taken before the first edit. An undo you cannot trust is worse than no undo, because it is what you reach for in a hurry.
- **`--dry-run` created a file.** A `touch` on the streak file, put there so the readers below had something to read, meant a dry run left state on disk. Dry run has to mean zero writes or it means nothing.
- **Removing that `touch` silently aborted the run.** `awk` exits 2 on a missing file, and under `set -eu` that ended the script two thirds of the way down — clean exit path, short report, exit status nobody was checking. Every state reader is now total: missing file, unreadable file, no match, all produce empty output and exit 0.
- **Patterns were built from strings out of the file.** A path is not a regular expression and a memory is allowed to contain one. Matching is now literal (`grep -F`, `index()`).
