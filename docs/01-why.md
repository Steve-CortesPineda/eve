# 01 · Why

*The problem, stated concretely, and why the obvious fixes do not solve it.*

---

## The failure

Open a new session with your coding agent. It knows the contents of your files
and nothing else. It does not know:

- that you were burned by a migration last month and now want a rollback stated
  before any schema change;
- that the ingest path has exactly one writer *on purpose*, and that its first
  suggestion — add a second consumer — is the exact mistake that produced four
  months of duplicate rows;
- that you already evaluated the library it is about to recommend, and rejected
  it for a reason that has not changed;
- that when it proposed this same fix three weeks ago you told it to show the
  failing assertion first.

So you type it again. You type it in a slightly different way than last time,
because you are reconstructing it from memory too, and the agent gets a slightly
different picture than it had before. Then the session ends and all of it is
gone. The next session starts from the same zero, and you pay the same cost.

The cost is not mainly the typing. It is that **your agent repeats mistakes it
has already made once**, and each repeat is expensive in a way the transcript
never shows — you review a fix that was already rejected, or worse, you do not,
because it looks reasonable and you have no record that you already thought
about it.

## Why this is not a model problem

Context is per-session by construction. When the process exits, everything the
model "learned" in that session exits with it. A larger context window makes a
single session hold more; it does nothing about the boundary between sessions,
because the boundary is not a capacity limit. It is a lifetime.

So the question is not "how does the model remember?" but "**what writes things
down, and what reads them back?**" That is a systems question, and it has a
boring systems answer: files, plus a retrieval step that runs whether or not
anyone remembers to run it.

## What does not work

**A bigger `CLAUDE.md`.** This works, and it keeps working, right up until the
file is 600 lines. After that every instruction competes with every other
instruction for attention, you stop being able to tell which line is doing work,
and you stop adding to it because you cannot predict what a new line will
displace. A single always-loaded file cannot grow linearly with what you know.

**RAG over your whole repo or note pile.** Retrieval over undifferentiated text
returns *topically similar* passages. What you need is the *decided* thing, and
decisions are exactly what is not in the codebase: the code says what you did,
never what you rejected or why. A vector search over 4,000 notes will happily
return four plausible neighbours and none of the one rule that mattered.

**Asking the model to remember.** It cannot, across sessions, and a prompt that
says "remember this for next time" produces agreement and no mechanism.

**Archiving your chat logs.** Transcripts are a record of everything that
happened, including everything you tried and abandoned. Searching them returns
your own wrong turns with the same confidence as your conclusions. A log is
evidence; a memory is a verdict. You need the verdict.

## What a memory is here

One durable claim, in one file, written by a human, stating:

1. the claim, flat, in the first line;
2. **why** — the evidence that produced it;
3. **how to apply** — the trigger and the action.

That is the whole format. The `why` is not decoration: it is what lets a rule
survive contact with a situation it was not written for. A rule without its
reason gets applied literally and wrongly, which is how a memory store starts
producing worse answers than no memory store.

See [02-memory-format.md](02-memory-format.md) for the full schema.

## The two halves, and why only one of them is automatic

**Retrieval must be automatic.** If finding the relevant memory depends on the
model deciding to look, it will not happen reliably — "check your memory first"
is one more instruction competing with everything else in the context window.
Moving retrieval into a hook takes it out of the model's judgement and makes it
part of the harness. This is the single highest-leverage idea in this repo:
*move the discipline out of the model and into the harness.*

**Capture must not be automatic.** The moment anything can write into the store,
the store becomes a log. Logs are dominated by machine residue — hundreds of
near-duplicate observations that bury the six rules that actually change
behaviour. A store where every file was put there deliberately by a human stays
small enough to be searched by brute force, reviewed by eye, and trusted.

That split has a filesystem consequence worth stating plainly, because it is
what keeps the retrieval side simple:

> **Curated memories and generated session logs live in different directories.**
> Only the curated directory is searched.

If generated notes lived in the searched tree, retrieval would need
shape-penalties, path-penalties and recency-penalties to stop machine output
from outranking hand-written rules — and you would spend the rest of the
project tuning them. Separate the trees and the whole ranking problem
disappears.

## What it costs

- One file per correction you would otherwise repeat. Two minutes to write.
- A few hundred characters of context per prompt, on prompts that match.
- A review habit: every month or so, retire what is no longer true.

That is the honest bill. If you are not willing to pay the third item, the
store will rot into a pile of confident, out-of-date assertions, which is
strictly worse than nothing — see [08-grounding.md](08-grounding.md).

## What it will not do

It will not make the model better at programming. It will not fix a codebase
nobody can explain. It will not remember things you never wrote down, and it
has no way to know that something it holds became false. **A memory that lies is
worse than no memory**, because a lie retrieved from your own store arrives with
the authority of something you wrote.

Everything in this repo is built to make that specific failure loud rather than
silent: dates on decaying facts, provenance on every claim, tombstones instead
of deletions, and an index that is generated rather than maintained by hand.

## Where to go next

- [02-memory-format.md](02-memory-format.md) — the format. Start here; it is
  the part that works with no code at all.
- [06-adoption.md](06-adoption.md) — day 1, week 1, month 1, and how to tell it
  is working.
- [08-grounding.md](08-grounding.md) — how to keep an agent from laundering a
  guess into a citation.
