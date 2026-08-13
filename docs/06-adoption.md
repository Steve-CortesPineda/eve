# 06 · Adoption

*What to actually do, in what order, and how to tell whether it is working.*

The honest version: **day 1 is thirty minutes and gets you most of the value.**
Everything after that is making the thing survive your own inattention.

---

## Day 1 — the format, and three memories

No installation. No hooks. You are creating a directory and writing three files.

### 1. Make the store

```sh
mkdir -p ~/.eve/memory
cp memory/TEMPLATE.md ~/.eve/memory/
```

Any directory you own will do — `~/.eve/memory` is used here because it is
where the Tier 1 hooks look by default, so nothing has to move later. Put it in
a git repo if you want history; it is plain markdown and diffs beautifully.

### 2. Write exactly three memories

Not thirty. Three. Pick them like this:

1. **The correction you have typed more than twice.** The thing you find
   yourself saying in most sessions. Write it as `type: feedback`, with the
   incident that caused it in the `**Why:**`.
2. **The one architectural fact you re-explain every time.** The non-obvious
   shape of your system — the constraint that makes the agent's first
   suggestion wrong. `type: project`.
3. **The decision you are tired of re-litigating.** Something you evaluated and
   rejected, with the reason. `type: decision`. This one pays for itself the
   first time the agent proposes the rejected thing and you can say "read
   `<id>`" instead of re-arguing it.

Use the scaffolder if you like:

```sh
scripts/new-memory.sh -s ~/.eve/memory -t feedback \
  "Show the failing assertion before proposing a fix"
```

Then fill in `**Why:**` and `**How to apply:**`. A memory without those two
sections is a slogan, and slogans get misapplied. The format rules are in
[02-memory-format.md](02-memory-format.md); the four worked examples in
[`memory/examples/`](../memory/examples/) are meant to be copied.

### 3. Write the index

One line per memory, stating the claim, in `~/.eve/INDEX.md`. Three lines. This
is the file the agent reads first.

### 4. Point your agent at it

Add this to your `CLAUDE.md` (or the equivalent always-loaded instructions for
whatever agent you use):

```markdown
## Memory

Durable knowledge lives in ~/.eve/memory, one claim per markdown file, indexed
in ~/.eve/INDEX.md.

- Before proposing an approach, read ~/.eve/INDEX.md and open anything relevant.
- Before asserting a fact about my systems or my preferences, search
  ~/.eve/memory. If it is not there, say you are guessing.
- Quote a memory with the date it was last verified. If the claim is about a
  vendor, an external service, or a number, verify it before relying on it.
- When I correct you on something that will be true again next week, say so and
  offer to write it down.
```

That is Tier 0 in full. It depends on the model choosing to look, which it will
do inconsistently — but the store is now real, and everything else is an
improvement on the retrieval step, not a rewrite.

### 5. Verify — by looking, not by asking

Ask the agent something adjacent to one of your three memories and see whether
the answer reflects it.

**Do not ask the agent whether it read your memory files.** It will say yes.
That is not a measurement; it is a sentence. Measure the artifact: does the
answer contain the constraint that is only in the file? If yes, it worked. If
no, it did not, regardless of what it claims.

---

## Week 1 — hooks, and the capture habit

Two things happen this week.

**Automate retrieval.** Tier 0's weakness is that "check your memory first"
competes with every other instruction in the context window and loses whenever
the conversation gets interesting. Hooks move retrieval out of the model's
judgement and into the harness: the relevant memory arrives with the prompt
whether or not anyone remembered to look for it.

```sh
./install.sh --dry-run    # read the plan first
./install.sh
```

It merges three hook entries into your Claude Code settings and leaves anything
already in `~/.eve/memory` untouched.

After installing, verify the same way as before — run the retrieval command
yourself and read the bytes:

```sh
~/.eve/bin/eve-doctor             # every check, plus a live end-to-end probe
~/.eve/bin/eve search "deploy staging"
```

If a probe returns your memory, retrieval works. If the agent *says* retrieval
works, you have learned nothing.

**Start the capture habit.** One rule:

> When you type a correction for the second time, stop and write the memory.

Not the first time — the first time might be a one-off. The second time is
evidence of a pattern, and the correction is already written in your last
message, so the memory costs a copy-paste plus the `**Why:**`.

Expect five to fifteen memories by the end of week one. If you have forty, you
are transcribing sessions rather than recording decisions, and the store will be
unreviewable by month two. If you have one, you are not noticing your own
corrections — read back three recent sessions and look for what you repeated.

**What not to do this week:** do not bulk-import your notes (below), do not
build a loop, do not add types or tags beyond what the format ships with. The
store is small and every structural decision you make now is one you will have
to maintain forever.

---

## Month 1 — a loop, but only if you have a signal

Two things are worth adding once the store is real.

### A review pass

Once a month, twenty minutes:

- Open anything whose `verified_on` is older than a quarter and is a `project`
  or `reference` memory. Re-check it or mark it `draft`.
- Find memories that have never once been useful. Ask what is wrong with them:
  usually the title is a topic rather than a claim, so nothing ever matched it.
- Tombstone what has been reversed (§7 of the format doc). Do not delete.
- Regenerate the index.

This is the whole maintenance cost of the system, and skipping it is how a
memory store becomes a confident liar.

### A loop — only with evidence

The tempting move is to automate improvement. Resist it until you have a
measured signal, because a loop that runs and does nothing is worse than no loop
— it produces activity, dashboards and row counts, and zero behaviour change.

The cheapest real signal is **gap detection**: log the prompts where retrieval
found nothing, then look at which terms recur. Terms that show up in ten
substantive prompts and match no memory are exactly the memories you have not
written yet.

The rule for any loop you add:

> **Name the consumer, in a comment, in the file.** If you cannot say what reads
> this output and what changes as a result, delete the producer.

If your gap log is empty after a month, you do not have a gap problem, and
building the loop would be building a thing to solve a problem you do not have.

---

## Migrating an existing pile of notes

You have a wiki, a notes folder, or four years of scattered markdown. The
instinct is to import all of it. Do not.

A store you did not curate is a store you do not trust, and a store you do not
trust is one you stop reading — at which point you have a large searchable pile
that occasionally injects out-of-date claims into your prompts, which is the
one outcome worse than starting from zero.

The process that works:

1. **Inventory without importing.** List what you have. Most of it is
   documentation (how something works, written at length). Documentation stays
   where it is.
2. **Extract claims, not documents.** For each source doc ask: *is there a
   sentence in here that changes what an agent should do?* If yes, that sentence
   becomes a memory whose body links back to the document. One doc frequently
   yields one memory, sometimes zero.
3. **Split anything that holds more than one claim.** This is where the work is.
   A note titled "Deployment" holding six facts becomes at most six memories,
   usually two.
4. **Date everything at import.** `created` is when it was first written if you
   know it, otherwise the import date. `verified_on` is *not* the import date
   unless you actually re-checked it — importing is not verifying, and pretending
   otherwise poisons the one field that tells you what to trust.
5. **Set `confidence: low` on anything you did not check.** Then it is findable
   and honest, and the review pass has a queue.
6. **Cap the batch at twenty.** Import twenty, live with them for a week, see
   which ones surface and which are noise. Then do another twenty if it is still
   worth it. It usually is not, and that is the useful finding.

The triage rule that resolves most cases: **if you cannot write the "How to
apply" section, it is not a memory.** File it as `type: reference` with a link,
or leave it in your docs.

---

## How to know it is working

**The signal to watch for:** your agent cites a decision you made weeks ago,
correctly, without you mentioning it. Somebody proposes the library you rejected
in March and the agent says "you rejected that in March because of the symlink
problem — has that changed?" That is the whole product working. The first time
it happens is usually inside week two.

Other real signals:

- You stop re-explaining the same architectural constraint. Count how many times
  you type it; it should go to roughly zero.
- The agent asks a *better* question instead of a generic one, because it knows
  the constraint that makes the obvious answer wrong.
- You start saying "write that down" instead of re-explaining, and it takes ten
  seconds.

**Negative signals, and what each one means:**

| Symptom | Diagnosis |
|---|---|
| Store keeps growing, retrieval almost never fires | Your titles are topics, not claims. Rewrite ten titles as sentences and watch it change. |
| The same three files match every prompt | Those memories are too broad. Split them. |
| The agent cites a memory that is wrong | You have a staleness problem, not a retrieval problem. Run the review pass and start filling in `verified_on`. |
| You have not written a memory in three weeks | Either nothing is being corrected (unlikely) or the habit did not stick. The trigger is "I have typed this correction twice", not "I should maintain my store". |
| You stopped reading the index | It has drifted from the files. Regenerate it, and stop hand-editing it. |

**A measurement worth taking once:** for a week, keep a tally of corrections you
give the agent. Mark each one as new or repeated. If repeats are more than a
third of the total, the store is not covering what you actually correct — and
the tally tells you exactly which memories to write next.

---

## When to stop growing it

A personal store levels off somewhere between 40 and 150 memories. Past that,
one of three things is true: you are recording transcripts instead of
decisions, you have stopped retiring things, or you genuinely have several
projects and should split the store by project and point the agent at one root
per project.

Growth is not the goal. A store of 30 memories you trust completely beats 300
you half-believe, because the value is not in having written things down — it is
in being able to act on what is there without checking it first.
