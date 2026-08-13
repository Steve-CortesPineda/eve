# 09 · The knowledge-base layer

*Two tiers, two jobs. The handful of memories that gate behaviour, and the deep store
the agent searches on demand.*

Everything so far has been about **memories** — small, durable, always in play. This
chapter is about the other half: the knowledge base. Architecture notes, project
docs, session logs, research, decision records. The material that makes an agent
knowledgeable rather than merely well-behaved.

They are not the same thing, they fail differently, and the single most common way to
wreck a memory system is to build one store and use it for both.

---

## Two tiers

|  | **Atomic memory** (`memory/`) | **Knowledge base** (`kb/`) |
|---|---|---|
| Job | gate behaviour | answer questions |
| Size | one claim per file, a few lines | as long as the subject needs |
| Reaches the model | always, or on nearly every request | only when retrieved |
| Volume | tens of files. Dozens, not hundreds | thousands is fine |
| Failure if missing | the agent does the wrong thing | the agent says *I don't know* |
| Read by | the front layer, every session | `kb search`, on demand |
| Example | *Never deploy Tessellate to Bracket Cloud* | the four-stage build pipeline, and why stage 3 is single-threaded |

An atomic memory is a **standing instruction**. Its value is that it is present at the
moment of the decision, without anyone having thought to go looking for it. You do not
know in advance that you are about to deploy to the wrong host — that is exactly why
the rule has to be resident rather than retrievable.

A KB document is **reference**. Its value is being correct, complete, and findable.
Nobody needs the render-pool concurrency rationale in context while renaming a
variable.

---

## Why conflating them fails

The two mistakes are symmetrical, and both are quiet.

**Everything in memory.** Every session now pays context for material almost none of
it needs. That cost is the obvious part, and it is the smaller part. The real damage
is that retrieval gets noisy: when four hundred files compete, the ones that match a
query on vocabulary alone crowd out the ones that match on meaning, and the rule that
actually gated the decision arrives ranked ninth. You did not lose the memory. You
diluted it until it stopped changing behaviour, which is the same thing with better
paperwork.

**Everything in the KB.** Now the behaviour-gating facts only reach the model when
retrieval happens to surface them. Retrieval is query-shaped, and the deploy rule is
needed precisely when nobody types the word *deploy* — the agent is "just fixing the
config", it never issues a query, and the rule sits in a perfectly good file that
nothing consulted. A rule that reaches the model 80% of the time is not 80% of a rule.
It is a rule you cannot rely on, which means you have to check anyway, which means it
bought you nothing.

The split exists because **"always present" and "arbitrarily large" cannot both be
true.** Pick which property each fact needs and file it accordingly.

---

## The decision rule

You should be able to apply this in five seconds, at capture time, without deliberating:

> **Would you want this sentence in front of the model on every request, even for
> unrelated work?**
>
> **Yes** → `memory/`.  **No** → `kb/`.

Three tie-breakers for when it is genuinely close:

- **Does it change what the agent *does*, or what it *says*?** Changes behaviour → memory. Provides an answer → KB.
- **Can you state it in one sentence without losing the point?** No → KB. A fact that needs three paragraphs of context is reference material, and truncating it into a memory produces a rule that gets misapplied.
- **Would you be angry if the agent violated it while not thinking about the topic?** Yes → memory. That anger is the definition of a standing instruction.

Worked examples:

| Fact | Tier | Why |
|---|---|---|
| *Never deploy Tessellate to Bracket Cloud* | memory | Needed at a moment nobody will search for it |
| *Bracket Cloud's sandbox flattens symlinks, so theme assets became empty files, which is why we left* | kb/decisions | The reasoning. Needed when the decision is questioned, not before |
| *Cache keys must be content hashes, never mtime* | memory | Gates an implementation choice, one line |
| *What invalidates a cache entry, and the three cases deliberately excluded* | kb/notes | An answer to a question. Nobody needs it resident |
| *You want the failing case shown before the fix* | memory | A standing rule about how to work with you |
| *What happened in Tuesday's postmortem* | kb/sessions | Raw material. Some of it may later become a memory |

Note the first two rows. They are the same subject at two altitudes, and both belong
in the system — the rule so it fires, the reasoning so the rule can be re-examined
rather than obeyed forever. Link them: the memory carries a `[[2026-05-19-drop-bracket-cloud]]`
reference to the decision record.

---

## Layout

```
kb/
  notes/       durable facts and how-tos not owned by one project
  projects/    how one system of yours is built, and why
  sessions/    what happened on a given day
  decisions/   a call you made, with the reasoning that made it
  research/    material from outside your head; always carries a source
  proposals/   NOT knowledge — consolidation output awaiting review
```

Five directories, and the count is the point. Every extra bucket is a decision the
writer makes at capture time, and buckets that make people hesitate do not get used —
an unfiled note is worth nothing regardless of how elegant the taxonomy was. These
five survive because each has a different **provenance and decay profile**, which is
the only distinction that earns a directory:

- `sessions/` is append-only and **never edited after the fact**. A session log is a record of what you believed on a day. Editing it destroys the audit trail that makes promotion trustworthy.
- `decisions/` is the one place where a superseded document is *more* valuable than a deleted one. A reversed decision plus the reasoning that reversed it is how you avoid relitigating the same call every eight months.
- `research/` is the only directory whose contents you did not author, so it is the only one where `source` is load-bearing rather than a formality — and the only one that can carry text written by someone trying to manipulate the agent (see the injection section of [08 · Grounding](08-grounding.md)).
- `projects/` and `notes/` split on ownership: if a system of yours changes, exactly one project doc goes stale; a note is not owned by anything and rots on its own schedule.

`proposals/` is not knowledge. It is an outbox. The distinction is enforced —
`kb search` never indexes it.

Deeper nesting is allowed (`kb/projects/tessellate/pipeline.md`) and searched. Adding
a sixth top-level directory is a real decision; make it deliberately.

---

## Front matter

The KB uses the **same schema as `memory/`**. One vocabulary, two tiers — so a fact
that gets promoted keeps its provenance instead of being re-typed and quietly losing
its source.

```yaml
---
id: tessellate-cache-keys
title: Tessellate cache keys are content-addressed
type: note
status: current
tags: [tessellate, cache, build]
source: you
created: 2026-06-11
updated: 2026-07-28
verified_on: 2026-07-28
confidence: high
supersedes: [tessellate-cache-mtime]
---
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Filename stem. Unique KB-wide. Written down so it survives a copy |
| `title` | yes | The conclusion in one line, not the topic |
| `type` | yes | `note` / `project` / `session` / `decision` / `research` |
| `status` | — | `current` / `draft` / `superseded`. Default `current` |
| `tags` | — | lowercase, kebab-case, flow list |
| `source` | yes | Where this came from: `you`, a URL, `session:<date>`, `export:<name>` |
| `created` | yes | First written |
| `updated` | — | Last edited |
| `verified_on` | yes | **Last date someone checked this is still true** |
| `confidence` | yes | `high` / `medium` / `low` |
| `supersedes` | — | ids this replaces |
| `superseded_by` | — | Set automatically by `kb doctor --fix` |
| `source_sha256` | — | Set by `kb ingest`; the idempotency key |

Four of these carry the weight.

**`source`** separates a fact from an invention. An unattributed document is
indistinguishable from something the model produced in a confident mood, and once one
of those is in the KB it is citable — which is how a hallucination acquires a
footnote.

**`verified_on`** is not `updated`. Fixing a typo is an update; re-checking the claim
against reality is a verification. This field decides whether the agent may state
something flatly or must hedge, and it is what [08 · Grounding](08-grounding.md) means
by shipping the claim's age with the citation. `--format ground` emits it:

```
[kb/examples/sample-kb/decisions/2026-05-19-drop-bracket-cloud.md:31, verified_on 2026-08-04 — 9 days old, confidence high]
> RULE: never deploy Tessellate to Bracket Cloud — its build sandbox drops symlinks and shared theme assets resolve to empty files.
```

**`confidence`** should be honest rather than flattering. `low` is useful; wrong is
not. Confidence multiplies the search score, so a hedged document loses to a solid one
on an equal match, which is the ranking you want.

**`supersedes`** is how the KB forgets without deleting. See [rot](#keeping-it-from-rotting).

> The parser reads a deliberately small YAML subset — scalars, quoted scalars, flow
> lists, block lists, comments. No nested maps, no block scalars. Unsupported
> constructs are reported with a line number rather than silently misread. That is
> what buys zero dependencies: no PyYAML, no install step, and front matter that
> stays flat enough for `grep` to be a legitimate second opinion.

---

## Ingestion

You already have notes. `kb ingest` files them in and adds provenance without
touching the originals.

```sh
kb ingest ~/notes/exports --type notes --source export:old-wiki --confidence medium
kb ingest ~/journal/2026-08-11.txt --type sessions --created 2026-08-11
```

Three guarantees, in priority order:

**1. The original is never mangled.** Sources are copied, not moved, unless you pass
`--move`. The body is preserved exactly; ingestion only adds a block above it. If a
source already has front matter, its `title` and `tags` win and only the missing
provenance keys are filled in.

**2. It is idempotent.** Identity is the SHA-256 of the body, stored as
`source_sha256` — so a file that was renamed or relocated upstream is still recognised
as already ingested:

```
$ kb ingest kb/examples/incoming --root kb/examples/sample-kb --type notes
unchanged  sessions/2026-08-11-render-pool-timeout.md
unchanged  notes/harbor-pages-runbook.md
unchanged  notes/tess-verify-checks.md
3 unchanged (kb/examples/sample-kb)
```

Note the first line: that file was originally ingested as a *session*, and re-running
with `--type notes` did not duplicate or move it. Content identity beats the flag,
which is the behaviour you want from anything you might run twice in a cron job.

**3. Provenance is not optional.** Every ingested document gets `source`, `created`,
`verified_on` and `confidence`. Defaults are conservative: `confidence: medium` and
`verified_on: today`, meaning *this was filed today*, not *this was checked today* —
so run `kb doctor` after a bulk import and be honest about what you actually verified.

A same-id-different-content collision stops rather than guessing:

```
conflict  notes/harbor-pages-runbook.md
          ^ same id, different content -- rerun with --update to replace
```

Use `--dry-run` first on anything large.

---

## Search

Retrieval returns **passages, not documents**, and every passage carries a
`path:line` anchor. That is structural, not cosmetic. The grounding doctrine says a
claim the agent cannot cite is a claim it should not make — which only works if the
retrieval layer hands back an anchor by construction. If citations are something the
model assembles afterwards, they are something it can assemble incorrectly.

```
$ kb search cache invalidation --root kb/examples/sample-kb -n 3

kb search "cache invalidation" -- 3 passages from 2 documents in kb/examples/sample-kb

1. kb/examples/sample-kb/sessions/2026-08-09-cache-invalidation.md:16   score 12.10
   Session -- cache invalidation on config change
   [sessions | verified 2026-08-09 | confidence high | tags tessellate, cache, build]
   Chased a report that changing the site footer did not take effect until the cache directory was deleted by hand.

2. kb/examples/sample-kb/sessions/2026-08-09-cache-invalidation.md:21   score 8.99
   Session -- cache invalidation on config change  >  Diagnosis
   [sessions | verified 2026-08-09 | confidence high | tags tessellate, cache, build]
   The config hash was computed from the *user-supplied* config file, not the resolved config. Defaults merged in at load time were therefore invisible to the hash, so a change that only altered a default did not invalidate anything.

3. kb/examples/sample-kb/notes/tessellate-cache-keys.md:31   score 7.71
   Tessellate cache keys are content-addressed  >  What invalidates an entry
   [notes | verified 2026-07-28 | confidence high | tags tessellate, cache, build]
   Deliberately *not* invalidating on config keys a page does not read: the dependency tracking needed to know which keys a page touched costs more than the rebuilds it saves.
```

Every line number resolves, and it points at the line the quoted words are **actually
on** — not at the enclosing heading, not at the top of the passage:

```
$ sed -n '31p' kb/examples/sample-kb/notes/tessellate-cache-keys.md
Deliberately *not* invalidating on config keys a page does not read: the
```

That precision is worth the trouble. An anchor that lands two lines off is one the
reader has to verify by hand, and a citation nobody trusts is decoration.

### Ranking

BM25 over passages, with four adjustments that matter for a knowledge base and not
for a general search engine:

- **Field weighting.** Title, tags, enclosing heading and path are indexed at higher weight, so *the note about X* beats *a note that mentions X once*.
- **Freshness decay.** Score halves per year since `verified_on`, floored at 0.4. Stale is not the same as wrong, so an old document is demoted, never hidden.
- **Confidence.** `high` 1.0, `medium` 0.88, `low` 0.72.
- **Supersession.** `status: superseded` is excluded by default; `--include-superseded` brings it back at a quarter weight and flags it in the output.

Two behaviours worth knowing because they are unusual:

**Per-document cap** (`--per-doc`, default 2). Field weighting boosts every passage in
a matching document equally, so a document that matches at all tends to match
*everywhere* — and without a cap one well-titled note takes most of the slots while
the note that actually answers the question never appears. The same query at `-n 5`,
with and without the cap:

```
$ kb search cache invalidation --root kb/examples/sample-kb -n 5 --per-doc 0
kb search "cache invalidation" -- 5 passages from 2 documents
1. sessions/2026-08-09-cache-invalidation.md:16   score 12.10
2. sessions/2026-08-09-cache-invalidation.md:21   score 8.99
3. notes/tessellate-cache-keys.md:31              score 7.71
4. sessions/2026-08-09-cache-invalidation.md:30   score 7.67
5. sessions/2026-08-09-cache-invalidation.md:35   score 7.67

$ kb search cache invalidation --root kb/examples/sample-kb -n 5
kb search "cache invalidation" -- 5 passages from 3 documents
1. sessions/2026-08-09-cache-invalidation.md:16   score 12.10
2. sessions/2026-08-09-cache-invalidation.md:21   score 8.99
3. notes/tessellate-cache-keys.md:31              score 7.71
4. notes/tessellate-cache-keys.md:27              score 5.38
5. notes/tessellate-cache-mtime.md:25             score 3.20
```

Four of five slots from one session log, versus evidence from three documents
including the note that owns the topic. Cap first, then backfill from the leftovers
only if there is room.

**Prefix variants.** The stemmer only strips plurals, deliberately — aggressive
stemming produces matches nobody can explain. That leaves a real gap: `invalidation`
does not match `invalidates`. So query terms also match vocabulary sharing a
five-character prefix, at 0.6 weight. Five is long enough that `content` and `context`
stay apart (they share four) while `deploy` still reaches `deployment`. Result 3 above
exists because of this rule.

### Output formats

| Flag | Use |
|---|---|
| `--format text` | reading (default) |
| `--format cite` | one line per hit, for pasting into an answer |
| `--format ground` | the [08 · Grounding](08-grounding.md) citation shape, with claim age |
| `--format json` | programmatic; includes both relative and absolute paths |

Filters: `--type decisions`, `--tag deploy`, `-n`, `--include-superseded`.

No index file is written; the KB is scanned per query. That is a deliberate trade —
zero moving parts and no staleness bugs, up to roughly ten thousand documents, which
is well past the point where a human-curated KB stops being human.

---

## Sessions become durable knowledge

This is the pipeline the whole layer exists to run:

```
  session log  ──►  kb/sessions/   ──►  kb consolidate  ──►  kb/proposals/
   (raw, dated)      (never edited)      (heuristics)         (you approve)
                                                                    │
                                                                    ▼
                                                               memory/
                                                          (gates behaviour)
```

**Write session logs with promotion in mind.** Mark durable claims explicitly with
`RULE:`, `FACT:`, `GOTCHA:`, `CONSTRAINT:`, `PREF:` or `LESSON:`, or put them under a
`## Durable` heading. This costs three seconds while writing and is the difference
between consolidation finding your rules and consolidation guessing at them.

**Then run the ritual**, weekly or at session end:

```sh
kb consolidate --since 14
```

It scores claims on three signals:

| Signal | Weight | Rationale |
|---|---|---|
| Explicit marker | 3.0 | The writer already said this was durable |
| Recurrence across documents | ×1.5 per extra doc | Repetition is the best available proxy for *this keeps mattering* |
| Behaviour-gating language | 1.0 | *always / never / must / prefer / avoid* — atomic memory exists to gate behaviour, so that is the shape worth promoting |

Claims are clustered by token similarity so the same rule written three ways proposes
once. Real output from the sample KB:

```
### P1. never deploy Tessellate to Bracket Cloud — its build sandbox drops symlinks and shared th…

- **proposed memory:** `never deploy Tessellate to Bracket Cloud — its build sandbox drops symlinks and shared theme assets resolve to empty files`
- **score:** 11.25 (2 explicit markers; recurs in 2 documents; recorded as a decision; behaviour-gating language)
- **evidence:**
  - `kb/examples/sample-kb/decisions/2026-05-19-drop-bracket-cloud.md:31` — never deploy Tessellate to Bracket Cloud — its build sandbox drops symlinks and shared theme assets resolve to empty files
  - `kb/examples/sample-kb/sessions/2026-08-02-deploy-postmortem.md:38` — never deploy Tessellate to Bracket Cloud — the build sandbox drops symlinks and shared theme assets silently resolve to empty files

### P3. cache keys must be content hashes, never mtime

- **proposed memory:** `cache keys must be content hashes, never mtime`
- **score:** 9.00 (2 explicit markers; recurs in 2 documents; behaviour-gating language)
- **evidence:**
  - `kb/examples/sample-kb/notes/tessellate-cache-keys.md:17` — cache keys must be content hashes, never mtime
  - `kb/examples/sample-kb/sessions/2026-08-09-cache-invalidation.md:35` — cache keys must be content hashes, never mtime — and the config half of the key has to be the *resolved* config, after defaults are merged
```

Note P3: two phrasings, one proposal, and the **shorter** one becomes the proposed
memory while the longer sits in the evidence. Short is the right default for a rule
that has to survive being read out of context.

Already-promoted facts are filtered out by comparing against `memory/` (read-only),
so re-running does not re-propose what you have already accepted:

```
## Already covered by atomic memory (1)
- never deploy Tessellate to Bracket Cloud — its build sandbox drops symlinks… — matches `memory/deploy.md`
```

### It proposes; you promote

Nothing is written to `memory/` automatically, and this is not caution for its own
sake. An atomic memory is a standing instruction that shapes **every future session**.
Auto-promotion means a heuristic that cannot read the room gets to write your operating
rules — and the failure is self-reinforcing, because a bad memory shapes the sessions
that generate the next round of proposals. One misread sentence becomes a policy,
becomes a habit, becomes a pattern the loop then "confirms". Approval is a human
action because reversing it later requires noticing, and by then the evidence has been
contaminated by the rule itself.

Approve by copying the proposed line into a memory file (see
[`memory/TEMPLATE.md`](../memory/TEMPLATE.md)) and deleting the block. Reject by
deleting the block. **Leaving a block untouched means undecided** — it is proposed
again next run, which is the correct default for something you have not thought about
yet.

> An agent running this ritual will do better than the heuristics — it can read the
> surrounding context and judge whether a claim generalises. The script is the floor
> that works with zero model calls and no network, and it is what makes the ritual
> cheap enough to actually run.

---

## Keeping it from rotting

A KB that only grows becomes a confident museum: real files, real citations, all
describing a world that changed. Four mechanisms, in increasing cost.

### 1. Supersede, never delete

New document declares what it replaces:

```yaml
supersedes: [tessellate-cache-mtime]
```

`kb doctor --fix` closes the link from the other side — setting `superseded_by` and
flipping `status` on the old document. It is purely additive; nothing is deleted.

```
$ kb doctor --root kb/examples/sample-kb --fix
warn  kb/examples/sample-kb/notes/kestrel-queue-tuning.md:1  not verified in 647 days -- reconcile or lower confidence
fixed kb/examples/sample-kb/notes/tessellate-cache-mtime.md:1  marked superseded by tessellate-cache-keys
11 documents, 0 errors, 1 warning, 1 repaired
```

The old document then drops out of search by default but stays readable, and
`--include-superseded` shows it flagged:

```
2. kb/examples/sample-kb/notes/tessellate-cache-mtime.md:17   score 3.02
   Tessellate rebuild cache (mtime scheme)
   [notes | verified 2026-04-09 | confidence medium | STATUS SUPERSEDED | tags tessellate, cache, build]
```

Deleting the old note would have been worse. The chain is the record of *why the
current answer is the current answer*, and without it the same idea gets re-proposed
every year by someone who has forgotten it was tried.

### 2. Date everything, and decay on `verified_on`

Freshness decay means an unverified document quietly loses ground to a verified one
without anyone curating anything. It is the only rot defence that costs nothing
ongoing.

### 3. Lint

```sh
kb doctor              # report
kb doctor --fix        # close supersession chains
kb doctor --strict     # non-zero exit on warnings — for CI
```

It catches missing provenance, invalid dates and confidence values, duplicate ids,
supersedes pointing at ids that do not exist, self-supersession, documents outside the
five directories (invisible to search), and documents past the staleness threshold
(`--stale-days`, default 180).

It also treats **unparseable front matter as an error rather than a skip**. A document
that will not parse is invisible to search, which is the worst failure mode available:
the file exists, you believe it is working, and nothing says otherwise.

### 4. Reconcile

Lint is mechanical. Deciding whether a two-year-old claim is *still true* requires
checking it against the world, which is what [`loops/reality-reconcile`](../loops/reality-reconcile/)
does: re-check claims against the system they describe, stamp `verified_on` when they
hold, propose a superseding document when they do not. `kb doctor` produces its work
queue — the staleness warnings are exactly the list of claims worth re-checking.

The division of labour is worth stating plainly, because it is where most KBs fail:
**`kb doctor` finds documents nobody has checked. `reality-reconcile` checks them.**
A system with only the first accumulates warnings and ignores them.

---

## Commands

```sh
kb search <query...>    # ranked passages with path:line citations
kb ingest <paths...>    # file existing notes in, with provenance
kb consolidate          # propose promotions to atomic memory
kb doctor               # find rot
```

Every command takes `--root`, or reads `$EVE_KB_ROOT`, defaulting to `kb/` next to the
script. `kb` is POSIX `sh` over stdlib `python3` — no packages, no index files, no
network.

Try it against the shipped fictional KB before pointing it at yours:

```sh
kb/bin/kb search cache invalidation --root kb/examples/sample-kb
kb/bin/kb doctor --root kb/examples/sample-kb
kb/bin/kb consolidate --root kb/examples/sample-kb --since 36500 --stdout
```

`kb/examples/sample-kb/` ships with two planted problems so `kb doctor` has something
to find. `kb/examples/incoming/` holds raw notes for trying `kb ingest`. The sample has
fixed dates, hence the wide `--since` window; on your own KB the default of 14 days is
the one you want.

---

## What to take from this chapter

- **Two tiers, two jobs.** Memory gates behaviour and is always present; the KB answers questions and is searched. The properties are mutually exclusive — pick one per fact.
- **The five-second rule:** would you want this in front of the model on every request? Yes → `memory/`. No → `kb/`.
- **Provenance and freshness are fields, not habits.** `source` separates fact from invention; `verified_on` decides whether the agent may assert or must hedge.
- **Citations are structural.** Retrieval returns `path:line` by construction, so grounding is a property of the mechanism rather than a request in a prompt.
- **Consolidation is what keeps a KB from becoming a landfill** — and it proposes rather than promotes, because a standing instruction should require a human to say yes.
- **Supersede, never delete.** The chain is the record of why the current answer is current.
