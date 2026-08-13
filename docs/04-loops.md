# 04 · Learning loops

*Tier 2, and the chapter that is mostly warnings. Read it before you install one.*

A learning loop is any component that watches the memory system and produces something intended to improve it: a report of what is missing, a check of what has gone stale, a ranking derived from recorded outcomes. Three reference implementations ship in [`loops/`](../loops/), each small enough to read in one sitting.

They are optional, off by default, and separated from the rest of Eve for one reason: **this is the tier where a memory system starts doing things to itself.** Tier 1 retrieves what you wrote. Tier 2 forms opinions about it. A retrieval bug shows you the wrong file and you notice in seconds. A loop bug quietly rewrites your relationship with your own notes over a period of months, and it is designed to run while you are not watching.

Everything below is a constraint on that. The general engineering statements live in [`05-design-laws.md`](05-design-laws.md); this chapter is what they mean when you are about to schedule something.

---

## 1. The law: do not build a producer without a consumer

Every loop in `loops/` names its consumer in a header comment, on the first line after the description, in capitals. That is not documentation. It is an admission requirement — you have to be able to finish the sentence *"the thing that reads this output is ___"* before you are allowed to write the thing that produces it.

The test has three parts, and a real consumer passes all three:

1. **Name the reader.** A person, a script, or a specific prompt path. "The system" is not a reader. "Future analysis" is not a reader.
2. **Name the artifact it reads and the effect that follows.** If the effect is "I feel more informed", there is no effect.
3. **Name the last time it actually read one.** This is the part that fails. The first two are answerable on the day you build the loop, when your enthusiasm is doing the answering.

If you cannot pass all three, you have not built a learning loop. You have built a component that runs forever, emits healthy-looking metrics, and changes nothing.

### The worked example

A system very much like this one ran a nightly analysis loop for several months. Its job was to compare what the memory store asserted against what the system had since observed, and to record every discrepancy it found as a structured "finding" row.

It worked. It was reliable. It never crashed. Over its life it produced **more than a thousand findings**, and it reported its own health in exactly the terms you would design if you wanted to be reassured: rows written last night, total rows accumulated, uptime, zero errors. On any dashboard it was the healthiest component in the system.

Not one of those findings was ever read. Not by a person, not by a prompt, not by another job. The consumer had been described at design time as "the reconciliation step will pick these up", and the reconciliation step was never built. Nothing pointed at the table. Nothing queried it. The findings accumulated, correctly formatted and completely inert.

The cost was not the disk. It was:

- **A nightly model call**, every night, for months, to analyze and phrase findings nobody read. Multiply your own per-run token cost by ninety and you have the bill.
- **A permanently misleading health signal.** The loop's row count went up every day, so the subsystem containing it always looked alive. That masked a *different* component in the same subsystem that had genuinely stopped working, because the aggregate metric everyone glanced at was dominated by rows the healthy-looking loop was producing.
- **Months of the improvement not happening.** This is the real cost and the easiest to miss. The team believed the store was being reconciled against reality. It was not. Every week that belief held was a week nobody did it by hand — and the whole point of the loop had been to make sure it got done.
- **A cleanup that was harder than the build.** By the time it was found, other things read *around* it. Deleting it required checking every one.

The failure was not in the implementation. The implementation was good. The failure is that the metric it emitted (**rows written**) was not the metric that mattered (**rows read**), and nothing in the design ever forced those two numbers into the same room.

### What Eve does about it

- Each loop's header names its consumer, and each README repeats it as the first line, above the description. If you skim, the consumer is what you see.
- Each loop's default output is a **markdown file addressed to a person**, not a row in a store. A report you did not read is visibly stale in a way a table is not: it sits there with last month's date on it.
- Gap detection ships with `--ignore`, so *declining* a finding is a recorded action. A loop with no way to say "no" produces a backlog that only grows, and a backlog that only grows stops being read — which is the same failure by a slower route.
- No loop writes into a path that another part of Eve depends on. Turning one off cannot break retrieval, because retrieval never read it.

### The forced choice

Put a date on it. Thirty days after you install a loop, and every thirty days after that, answer one question:

> Since the last review, did the output of this loop change anything I did?

There are exactly two valid answers.

**Yes** — name the change. A memory you wrote, a claim you corrected, a decision you closed out. Keep the loop.

**No** — you have two options, and "leave it running and see" is not one of them:

| Option | What it means in practice |
|---|---|
| **Give it a consumer** | Change the loop so its output lands where you already look, or shrink it until acting on it takes under a minute. Then re-review in thirty days. |
| **Stop it** | Delete the directory. Nothing else breaks. Write a two-line memory saying you tried it and what it cost, so you do not rebuild it in six months. |

The reason "leave it running" is excluded: a loop nobody acts on does not stay neutral. It accrues cost, it inflates a health signal, and it occupies the slot in your attention labelled *"the store is being maintained."* That last one is what makes it expensive. Nothing else will get built to do the job, because as far as anyone can tell the job has an owner.

---

## 2. Deletion is never a consequence of a clock

The tempting design is elegant enough that most people arrive at it independently: give every memory an activation score, decay it over time, boost it when it is used, and have a cleanup job remove anything that falls below a floor. It self-tunes. It bounds the store. It mirrors how human memory is described in the literature. Under daily use it looks like it works, because under daily use the things you use keep getting boosted.

Then you take two weeks off.

Nothing gets used, so nothing gets boosted, and every score decays together. The cleanup job runs on its schedule — it has no notion of "the user was away", only of "below threshold" — and deletes what the system spent months learning. There is no recovery, because deletion was not a bug in that design. It was the design. The floor did exactly what it was configured to do.

The lesson generalizes past memory systems: **a decay clock measures elapsed time, not irrelevance.** An idle month is the input those two interpretations share, and only one of them is ever true. Bind an irreversible operation to that signal and you have built a system that punishes you for having a life.

### The rules Eve holds to

**Decay may reorder. It must never destroy.** Forgetting, in Eve, is a ranking operation and nothing else. An old memory sinks; it does not disappear. Retrieval's age multiplier bottoms out at 0.8 — it can lose a competition, never the store.

**Ranking and deletion are separate subsystems that never call each other.** No score, weight, or multiplier anywhere in Eve is an input to any removal decision. This is why the outcome loop's weight floor is 0.80 rather than 0: a multiplier that can reach zero is a deletion with extra steps, and the moment one exists someone will eventually add the cleanup job that consumes it. Keeping the floor high means that job would have nothing to act on.

**No code path deletes a file from `memory/`.** Not behind a flag, not behind a config key, not with `--force`. The capability does not exist. `eve review` proposes; you dispose, by hand, having read the file. That asymmetry is deliberate: proposals are cheap to ignore and deletions are not cheap to undo.

**Superseding is a tombstone, not a removal.** A replaced memory keeps its file and gains `status: superseded` and `superseded_by:`. Retrieval demotes it hard (x0.2) so it never outranks its replacement, but it stays findable. Deleting the old claim removes the only artifact that can stop it coming back — every later import, sync, or rebuild has nothing to contradict it, and it returns looking like fresh information. A tombstone is the record that a human already decided this, and it has to outlive the thing it marks.

**If you ever add automatic removal, it needs all four of these, not the first one:**

1. **A hard minimum age**, measured in months, that no score can override. Recency is the one thing a young memory is guaranteed to lack.
2. **Archive, not `DELETE`.** Move it to `archive/`, out of the searched tree. Same effect on retrieval; entirely different effect on the afternoon you realise you need it.
3. **A dry run that lists every candidate, and a human who reads the list.** Not a summary count — the list.
4. **A recovery path you have actually exercised.** Restore something from your archive on purpose, once, before you trust the mechanism. An untested restore is a belief, not a capability.

The shipped loops need none of this, because none of them removes anything.

---

## 3. Automatic correction needs two gates, and the second one is the one people skip

Reality-reconcile is the only loop that can modify a memory file, and only with `--apply`. What it may write is deliberately tiny — one comment line marking a claim as unverified. Even for something that small, two independent gates stand in front of it.

### Gate one: the streak

A failure must repeat across several consecutive runs before it counts, and runs closer together than an hour apart do not count as separate looks.

The time component is not padding. Without it, `for i in 1 2 3; do reconcile; done` is indistinguishable from three days of evidence — the streak counter cannot tell the difference, and a counter that a loop can trivially satisfy against itself is not a gate. The same applies to a scheduled job that fires more often than the world changes: five checks an hour apart are one observation repeated five times, not five observations.

### Gate two: the premise

This is the one that gets left out, and it is the one that matters.

**Repeating a probe whose premise is broken does not converge on the truth. It converges on a confident wrong answer.** Three runs against a machine with the volume unmounted produce three genuine failures and a streak of three. The streak gate is satisfied — correctly, by its own logic — and the loop marks a claim stale that was true the whole time. The repetition did not add information. It added confidence to a measurement that was never valid, which is strictly worse than a single failure, because a single failure looks like what it is: noise.

So before any failure is counted, the run has to establish that it was capable of passing:

- **Control probes.** Check something that must be true — the root directory is a directory, `sh` resolves on `PATH`. If a control fails, this machine is not in a state where a negative result means anything, and nothing is counted.
- **A control for each external dependency.** Network checks are gated on resolving a control host. If the control does not resolve, the machine is offline: those checks become `skip`, never `fail`. Absence of evidence and evidence of absence are different results and must be different values in the code, not the same value with a comment.
- **A mass-failure guard.** If more than half the checks fail in a single run, the run is inconclusive. An unmounted volume, a fresh clone, the wrong host, a VPN that dropped — every one of these fails most checks at once. **One claim going stale is news. All of them going stale in the same instant is a story about the observer, not the world.**

When any of those trips, streaks are frozen exactly where they were. Not reset — frozen. Resetting would let an intermittent problem erase real accumulated evidence; freezing means an inconclusive run contributes nothing in either direction, which is the honest accounting for a measurement that did not happen.

### The generalization

Any automated correction, in any system, needs an answer to: *what would have to be true for this negative result to be meaningful, and did I check it?* A retry loop that hammers a failing endpoint, a health check that restarts a service, an anomaly detector that pages someone — all of them fail the same way, by treating "my measurement said no" as equivalent to "the world says no." The measurement has preconditions. Check them first, and count nothing when they do not hold.

---

## 4. Every automated write is reversible, or it is not permitted

A loop that can edit files must leave a way back. Not a plan for one — a mechanism you have used.

**Before the first edit to a file in a run, copy the file.** Once per file per run, taken before anything changes. The version of this that takes a backup per *edit*, with a filename stamped to the second, has a bug you will not notice: two edits to the same file inside the same second write the same filename, and the second copy overwrites the first with the already-modified content. The audit log still shows an undo command. The command still runs. It restores the wrong state. **An undo you cannot trust is worse than no undo, because it is the thing you reach for in a hurry.**

**Every write appends a line to an audit log**, and the line contains all five of:

| Field | Why |
|---|---|
| timestamp | when |
| action | `mark-stale`, `unmark-stale` — a verb, not a status code |
| target | which file |
| reason | which check, which streak count — the evidence, so you can judge the write later without re-deriving it |
| **undo** | a literal command line you can paste |

That last field is the requirement. Not a backup ID, not "restore from `state/`" — the exact command, with the exact paths, quoted. If reversing an automated write requires a human to reconstruct anything, it will not be reversed at three in the afternoon when it matters.

**Then test it.** Run the loop, apply an edit, paste the undo command, and `diff` against the original. The reconcile loop's undo has been exercised this way and restores files byte-identical. Until you have done that, "reversible" is a design intention, and design intentions do not restore files.

**And close the loop in both directions.** Reality-reconcile removes a stale marker when the check passes again. A loop that only ever adds markings produces files that slowly fill with warnings nobody trusts, because nothing ever retracts one. Automatic marking is only credible if automatic unmarking exists.

---

## 5. Before you ship a loop

A loop passes when every line here is true. Each maps to something that has already gone wrong.

- [ ] **Its consumer is named in the file**, and I can say when that consumer last read its output.
- [ ] **`--dry-run` writes nothing at all.** Not "nothing important" — verify with a file count before and after. A dry run that creates a state file is a dry run you cannot trust for the writes you care about.
- [ ] **It exits 0** on a missing store, an empty store, a malformed input, and a first run. Loops run unattended; a non-zero exit is a notification nobody asked for.
- [ ] **Every state reader is total.** Missing file, unreadable file, no matching row: empty output, exit 0. Under `set -eu`, one reader that can fail is a script that silently stops halfway with a plausible-looking partial report.
- [ ] **A parse that finds nothing is distinguishable from a store that contains nothing.** These produce identical output and opposite meanings. If the input had usable lines and the analysis produced no records, report *that*, and refuse to print a clean bill of health. A loop that says "all clear" when it has crashed gets believed.
- [ ] **It has been run against a fixture where the answer is known and non-zero.** That is what [`loops/example-store/`](../loops/example-store/) is for. Every bug found while building these three was found this way, and every one of them produced well-formatted, confident, wrong output rather than an error.
- [ ] **Nothing it reads is executed.** Memory files are ordinary files that anything with a write tool can append to. A marker is a request to look, never a request to run.
- [ ] **It cannot delete a memory.** Check by reading the code, not by reasoning about the flags.
- [ ] **If it writes, the write is backed up, logged with a pasteable undo, and I have run that undo once.**

The last three are not negotiable. The rest are how you avoid spending a month reading confident output that was never computed.
