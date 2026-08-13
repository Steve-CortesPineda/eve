# 02 · The memory format

*One fact per file. This chapter is the whole product; everything else is
plumbing that reads it.*

The format is deliberately small. It is a markdown file with YAML front matter,
readable in any editor, greppable, diffable, and useful to a human who has never
heard of this repo. Nothing about it requires the tools in this repo to work.

---

## 1. The unit is one claim

**One file states one thing.** Not one topic, not one project, not "everything I
know about deploys." One claim, with its evidence and its application.

This is not a style preference. The file is simultaneously three units:

| It is the unit of… | which breaks if a file holds two claims |
|---|---|
| retrieval | a query matching claim A drags claim B into your context |
| update | you cannot edit A without touching B's timestamps |
| retirement | you cannot mark A dead without killing B, so you leave both |

That last row is the one that bites. A file holding four loosely related facts
can never be retired, because one of the four is still true. So it stays, and
the three dead facts keep getting retrieved, forever. Splitting is what makes
forgetting possible.

The test: **if you would ever want to mark half of this file dead, it is two
files.** An `## Also` heading about something unrelated is the same signal.

Size follows from that. Most memories are 10 to 25 lines. If yours is 80, it is
probably a document — leave the document where it lives and write a memory that
states the claim and links to it.

---

## 2. Anatomy

```markdown
---
id: harborlight-manifest-ingest
title: Harborlight ingests manifests through exactly one writer
type: project
status: current
tags: [harborlight, ingest, architecture]
source: harborlight ingest worker + design review notes, 2026-01-20
created: 2026-01-22
updated: 2026-06-18
verified_on: 2026-06-18
confidence: high
---

Every carrier manifest enters Harborlight through a single queue consumer.
Exactly one process writes to the `shipments` table.

**Why:** Delivery is at-least-once, so the same manifest arrives more than once
under retry. Dedupe is keyed on the carrier's `manifest_id`, never on our own
row id -- our id is assigned at insert time, so a duplicate gets a fresh one and
looks new. The first version had two writers, each doing its own dedupe, and
produced duplicate shipments for four months before a customer noticed.

**How to apply:**
- Do not add a second process that writes `shipments`. New consumers read.
- Any consumer must be idempotent on `manifest_id`. Assume at-least-twice.
- If throughput is the problem, partition the single writer. Adding a second
  writer is the failure mode, not the fix.
- Retry behaviour depends on how the carrier signals throttling, which is not
  what you would guess. See [[reference-carrier-throttle-returns-200]].
```

Four worked examples, one per family, are in
[`memory/examples/`](../memory/examples/). The blank template is
[`memory/TEMPLATE.md`](../memory/TEMPLATE.md); `scripts/new-memory.sh` fills it
in and adds the index line.

---

## 3. Field reference

Front matter is **optional** at the margins — a file with none at all should
still be found and read, with the title falling back to the filename. But every
field below earns its place, and a store where they are filled in is a store you
can audit.

| Field | Meaning |
|---|---|
| `id` | The filename stem, written down. Redundant on purpose: the id survives a copy, an export, or a paste into a chat. |
| `title` | One line, sentence case, **stating the conclusion**. This is the line that gets injected into context; if it is a topic label, retrieval was pointless. |
| `type` | `feedback`, `project`, `decision`, `reference`, `note`. Drives ranking and grouping, nothing else. |
| `status` | `current`, `draft`, or `superseded`. `superseded` is a tombstone — see §7. (Some older stores write `active` for `current`; only `superseded` changes any behaviour, so both are read as "live".) |
| `tags` | Lowercase, kebab-case, flow list. Coarse. Do not build a taxonomy; you will not maintain it. |
| `source` | Where the claim came from: `you`, a person, a file, a vendor doc plus the date you read it. **An unattributed claim is indistinguishable from an invented one.** |
| `created` / `updated` | `YYYY-MM-DD`. When it was first written; when the text last changed. |
| `verified_on` | The last date a human checked this is *still true*. Different from `updated`: fixing a typo changes `updated`, not `verified_on`. This is the field that decides whether an agent may assert the claim flatly or must hedge it. |
| `confidence` | `high`, `medium`, `low`. Be honest. `low` is useful; wrong is not. |
| `supersedes` | List of ids this memory replaces. |
| `superseded_by` | The id that replaced this one. Set together with `status: superseded`. |

### Title discipline, because it is 80% of the value

The title is what a reader sees in the index and what an agent sees in a recall
snippet. Nine times out of ten nothing else gets read.

| Bad (topic) | Good (claim) |
|---|---|
| Deploy notes | Deploys to staging are blocked after 18:00 UTC |
| Pagination | Harborlight uses cursor pagination, not offset |
| Thoughts on the queue | The ingest path has exactly one writer, on purpose |
| Carrier API | The carrier API signals throttling with an empty 200, not 429 |

If you cannot write the title as a sentence with a verb, you do not yet know
what you learned. Write the body first and come back.

### The filename is the id

Lowercase, kebab-case, `.md`. It is what `[[links]]` point at, so **renaming is
a breaking change**. Choose a name that describes the claim, not the date you
wrote it: `harborlight-manifest-ingest`, not `2026-01-22-notes`.

---

## 4. The four families, and why splitting them matters

Four kinds of thing are worth keeping. They look similar on disk and behave
completely differently over time.

| Family | Holds | `type` | Half-life | Failure if you get it wrong |
|---|---|---|---|---|
| **Who you are** | durable facts about you and your situation that change how work should be done by default | `feedback` | years | never written down at all, so it is re-explained every session |
| **How to work** | corrections: what went wrong once, and what to do instead | `feedback` | years, until the underlying cause moves | applied literally in a situation it was never about |
| **Project state** | how one of your systems is actually built, and the calls you made building it | `project`, `decision` | months | **goes stale fastest and lies most confidently** |
| **Reference** | external facts you cannot derive from your own code: vendor behaviour, API quirks, limits | `reference` | unknown — the world changes without telling you | asserted as current when it was true once, a year ago |

Two of the four share `type: feedback`. That is deliberate: `type` exists to
rank, and both families are standing rules that should outrank background
facts. The distinction between them matters to *you*, not to the ranker, so it
lives in the filename prefix (`you-…`, `feedback-…`) and the tags.

**Why splitting matters at all:** the four have different half-lives, and a file
that mixes them cannot be maintained. Put "you are the only maintainer" and "the
carrier allows 60 requests per minute" in the same file and you have created
something that is permanently half-stale: re-verifying the vendor number means
touching a file whose other half never needed checking, and marking the vendor
number dead means killing a fact about you that is still true.

They also have different **verification rules**, which is the practical
consequence:

- *Who you are* and *How to work*: verified by you saying so. No expiry.
- *Project state*: verify against the code before asserting it. The code is the
  source of truth; the memory records the intent and the reasoning, which the
  code cannot.
- *Reference*: verify against the vendor before relying on it, and quote the
  date you last checked. Never assert a vendor's current behaviour from a
  memory alone.

---

## 5. Body shape

Three parts, in this order.

**Line 1: the claim, flat.** The first body line is what gets shown as the
snippet. Throat-clearing there ("This note covers our approach to…") makes the
retrieval worthless. Write the sentence you would say out loud.

**`**Why:**` — the evidence.** What actually happened. Dates, counts, the
incident, the thing that broke. This section is what lets the rule generalise:
an agent that knows *why* deploys are blocked after 18:00 can reason about a
hotfix at 18:05, and an agent that only knows the rule cannot.

Omit it and you get the classic failure: the rule applied to a situation it was
never about, confidently, with your own words as justification.

**`**How to apply:**` — triggers and actions.** Concrete. "Before proposing a
deploy, check the clock" is a trigger. "Be careful with deploys" is not.

Include the boundary of the rule here: what it does *not* cover, and what would
make it obsolete. The example memories all end with one line of that.

> If you cannot write the "How to apply" section, you are writing reference
> material, not a memory. That is fine — file it as `type: reference`, or leave
> it in your docs and write a one-line memory that points at it.

### Cross-references

Link with `[[filename-stem]]`. Plain text, no tooling required, renders as a
link in Obsidian-style editors and as literal text everywhere else — which is
fine, because the stem *is* the filename.

Link only to ids that exist. A dangling `[[link]]` asserts that something was
written down when it was not, and an agent will cheerfully report that "your
notes cover this" when they do not.

Keep links sparse. Two or three per memory. A memory that needs six links is a
document.

### Memories are data, not instructions

Everything in a memory file gets injected into a model's context. Write claims,
not commands aimed at the agent's behaviour in general, and be aware that
**anything with write access to your store has write access to your agent's
context**. That is a good reason to keep capture manual, keep the store in a
directory you own, and never point retrieval at a directory something else
writes into.

---

## 6. The index

One file listing every memory, one line each, stating the claim:

```markdown
- [Harborlight ingests manifests through exactly one writer](examples/harborlight-manifest-ingest.md) — project, verified 2026-06-18
```

The index exists so that a reader — human or agent — can see the whole store at
a glance and open only what matters. It is the entire Tier 0 mechanism: a
`CLAUDE.md` line that says "read the index before proposing an approach" gets
you most of the value with no code at all.

Three rules:

1. **The line states the claim, not the topic.** Same discipline as the title,
   for the same reason: the index is often the only thing read.
2. **The index is derived, never the source.** It is regenerable from the files.
   If the index and a file disagree, the file wins — and you should be able to
   rebuild the index from scratch to prove it.
3. **Superseded memories do not appear in it.** They stay on disk; they leave
   the index. See §7.

### An index that lies is worse than no index

An index that lies is not a stale document. It is an **assertion that outlives
its own correction**.

Here is the mechanism, because it is not obvious. The index asserts something. A
session later establishes the opposite, and the detail file is updated — but the
index still carries the old claim. Now every read of the index re-introduces the
dead claim, and each re-introduction looks like fresh evidence rather than an
echo. If any tooling regenerates *from* the index, or syncs it somewhere, the
dead claim gets copied forward. The system unlearns your decision, repeatedly,
and the source is very hard to find because nothing is obviously broken.

The fix is structural, not diligence:

- Generate the index. A hand-maintained index drifts the first week you are
  busy, and drift is silent.
- Mark it as generated, in the file: `<!-- generated -->`.
- Never edit the index to change a claim. Edit the memory and regenerate.
- When something is reversed, leave a tombstone in the source (§7). Deleting the
  old claim removes the only thing that could stop it coming back.

The starter index at [`memory/MEMORY.md`](../memory/MEMORY.md) is hand-written
because the repo ships exactly four examples and a generated file would tell you
less about the conventions. Your store should generate it.

---

## 7. Tombstones

**When a decision is reversed, do not delete the memory. Mark it dead.**

Deletion feels correct and is the single most expensive mistake in this format.
The reason is not sentimentality about history:

> A deleted claim leaves nothing behind that contradicts it. The claim still
> exists — in an old index, in a synced copy, in a doc that references it, in
> the transcript where you first decided it, in your own half-memory of having
> decided something. Every one of those is a path for it to come back, and none
> of them knows it was reversed. **The tombstone is the only artifact that
> outlives the claim and says "no."**

### How to reverse a decision

Both files change. The old one:

```markdown
---
id: harborlight-manifests-kept-forever
title: Harborlight keeps every manifest indefinitely
type: decision
status: superseded
superseded_by: harborlight-manifest-retention-18-months
updated: 2026-07-09
verified_on: 2026-07-09
---

SUPERSEDED 2026-07-09 by [[harborlight-manifest-retention-18-months]]. The
claim below was true until then. It is kept because the reasoning still
explains why the original choice was made, and that reasoning will come up
again.

Manifests are never deleted…
```

The new one:

```markdown
---
id: harborlight-manifest-retention-18-months
title: Harborlight deletes manifests after 18 months
type: decision
status: current
supersedes: [harborlight-manifests-kept-forever]
created: 2026-07-09
verified_on: 2026-07-09
---

Manifests older than 18 months are deleted by the retention job…

**Why:** keeping everything was correct while the table was small. At 400 GB
the reconciliation job's index no longer fit in memory and nightly runs went
from 20 minutes to over three hours…
```

Rules:

- **Never edit the old claim away.** The old file keeps saying what it said. You
  add a header, change `status`, and stop. Rewriting history destroys the only
  record of why the first choice was made, which is exactly what you need the
  next time someone proposes it again.
- **Both directions are recorded**: `superseded_by` on the old, `supersedes` on
  the new. A checker can then find a tombstone with no replacement, or a
  replacement pointing at nothing.
- **The tombstone leaves the index** and the replacement takes its place.
- **Nothing in this system deletes files from the store.** Age and status
  demote; they do not destroy. Forgetting is a ranking operation, not a
  filesystem operation. If you truly want a memory gone, deleting it is a manual
  act you perform yourself, with your eyes open.

`status: draft` is the same mechanism pointed the other way: something written
down but not yet decided. It is findable and should never win a ranking against
a `current` memory.

---

## 8. Keeping memories from going stale

Staleness is the failure mode that kills trust, and it is invisible: a stale
memory reads exactly like a fresh one.

**Date anything that can decay.** Numbers, limits, versions, prices, team
composition, "we currently use X". If it has a number in it, it needs a date.

**Absolute dates, never relative ones.** "Last week", "recently", "currently",
"for now", "the new API" — all of these were true when typed and are lies
afterwards, and there is no way to tell how long afterwards. Write `2026-05-02`.
This applies inside the body, not just in the front matter.

**Separate `updated` from `verified_on`.** Editing a sentence is not
verification. When you actually re-check a claim, bump `verified_on` even if you
changed nothing — that is the whole signal.

**Verify before recommending.** For `project` and `reference` memories, the
memory is a *pointer to where the truth lives*, not the truth. Before acting on
a vendor limit, re-read the vendor doc. Before asserting how a service behaves,
look at the service. Quote the memory with its date: "as of 2026-05-02 the
limit was 60/min" is a defensible sentence; "the limit is 60/min" is not.

**Do not touch files to boost them.** Modification time is a ranking signal in
most retrieval schemes. Opening and re-saving a file to make it surface is
fabricating evidence of freshness, and you will believe it later.

**Write the obsolescence condition into the memory.** The best line in the
deploy-window example is the last one: *if the reconciliation job moves, this
memory is stale.* Now the memory tells you when to kill it, and an agent
reading it can notice that the condition changed.

---

## 9. What not to store

**Anything git already records.** File contents, who changed what and when, the
diff, the commit message. The repo is the source of truth about the code; the
memory store is the source of truth about *decisions and preferences*. Writing
"the auth module is in `src/auth/`" creates something that will be wrong after
the next refactor and that nobody will fix, when `ls` was always going to be
right.

The distinction that matters: **the code says what. Memory says why, and what
you rejected.** If a claim can be answered by reading the repo, do not store it;
if it can only be answered by asking you, store it.

**Anything scoped to the current conversation.** Task lists, "next I will do X",
scratch plans, intermediate state. That is what the session is for. A memory
store full of last month's intentions retrieves last month's intentions.

**Secrets. Ever.** Tokens, keys, passwords, connection strings with credentials
in them. Memory files are plaintext, they are injected into a model's context by
design, and this store is the one directory in your system built to be read
aloud. Store the *fact* ("the deploy key lives in the password manager under
X"), never the value.

**Other people's private information.** Same reasoning: this content leaves your
disk every time it is retrieved into a prompt. Write "the platform lead owns the scheduler
rewrite", not anything you would not put in a shared doc.

**Volatile numbers you will not re-verify.** A metric that changes weekly, in a
file you will read in six months, is a trap. Either date it hard and treat it as
historical, or store the query that produces it.

**Anything you cannot state as a claim.** If you cannot write a title with a
verb in it, it is a document or a feeling. Documents belong in your docs.

---

## 10. Before and after

A real-shaped bad memory:

```markdown
---
title: Deploy stuff
---
Be careful deploying in the evening, the reconcile job can conflict.
Also we should probably move to blue/green at some point.
Rye mentioned the staging box is slow.
```

Three claims, no evidence, no trigger, one aspiration, one hearsay, a topic for
a title, and nothing datable. Retrieved, it tells an agent almost nothing it can
act on — and it can never be retired, because the middle line will be "true"
forever.

The same knowledge, done properly, is one memory:

```markdown
---
id: deploy-window
title: Deploys to Harborlight staging are blocked after 18:00 UTC
type: feedback
status: current
tags: [deploy, harborlight, process]
source: you, after the 2026-03-04 incident
created: 2026-03-04
updated: 2026-05-19
verified_on: 2026-05-19
confidence: high
---

Do not deploy Harborlight to staging after 18:00 UTC on weekdays.

**Why:** The nightly manifest reconciliation job starts at 18:15 and takes a
lock on the shipments table. A deploy that restarts the API mid-job leaves
half-reconciled rows that have to be repaired by hand. This happened twice.

**How to apply:**
- Before proposing a deploy, check the clock. After 18:00 UTC, propose it for
  the next morning rather than asking whether it is okay.
- Hotfixes are the exception, but say out loud that you are taking the
  exception and why.
- This is about the reconciliation job, not about the time of day. If the job
  moves, this memory is stale.
```

The other two lines are dropped: "move to blue/green" is a wish (it becomes a
memory when it becomes a decision), and "the staging box is slow" is an
undated, unattributed observation that will be wrong or irrelevant within a
quarter.

---

## 11. Checklist

Before you save a memory:

- [ ] The title is a sentence stating a conclusion.
- [ ] The first body line reads well on its own, out of context.
- [ ] There is a `**Why:**` with actual evidence in it.
- [ ] There is a `**How to apply:**` with a trigger in it.
- [ ] Exactly one claim. Nothing you would ever want to retire separately.
- [ ] `source` says where it came from. `verified_on` is today if you checked.
- [ ] Every date is absolute. No "recently", no "currently".
- [ ] No secrets, no credentials, nothing git already knows.
- [ ] Every `[[link]]` points at a file that exists.
- [ ] One line in the index, stating the claim.
