# The grounded answer template

The shape of an answer that can be checked. Four parts: **claim, citation, confidence,
gaps.** Doctrine behind it: [`docs/08-grounding.md`](../docs/08-grounding.md).

This is a shape, not a form to fill in. A one-line answer with one path is a complete
grounded answer. The parts are what must be *present when they apply* — not sections to
emit every time.

---

## Skeleton

```
<direct answer, first sentence, no preamble>   [memory/<id>.md]

<supporting specifics, each with its own path>
<verbatim quote of any line that will be pasted or acted on>

[inferred: <path> → <the reasoning step>]      ← anything derived, marked as derived
as of YYYY-MM-DD (N days old)                  ← anything time-sensitive
verify: <one-line command>                     ← anything you'll act on

Not in the KB: <the specific sub-question you couldn't answer>
→ logged to state/whiffs.log as `missing`
```

Ordering rule: **answer first, apparatus after.** Confidence and provenance are decoration
on a sentence the reader has already understood. An answer that opens with three lines of
hedging gets skimmed, and skimming defeats the citations.

---

## Contrast

**Ungrounded** — everything wrong in one paragraph:

> You're running the job runner on Postgres now, I think after some issues with Redis
> persistence last spring. Deploy is the usual push command against the runner host —
> should be `--edge` or similar. Retries default to 3 unless you changed it.

Four failures, none visible without going and checking:

- no path anywhere — "I think" is the only provenance signal, and it is not one
- "last spring" — a date reconstructed from a vibe
- "should be `--edge` or similar" — a specific offered as an approximation, which is the
  worst possible register for a flag
- "retries default to 3" — pure invention, delivered in the same voice as the parts that
  happen to be true

**Grounded** — same underlying knowledge, honestly delivered:

> Job state is in Postgres [`memory/decision-postgres-for-job-state.md`] — switched on
> 2026-03-11 after the cache node was recycled and took 1,400 queued jobs with it
> [same file].
>
> Deploy, **as of 2026-01-08** (217 days old, budget 30d):
>
> ```
> lighthouse push --edge --host runner-3.svc.example
> ```
>
> [`memory/lighthouse-deploy.md`] — past budget, and it names a flag and a host, the two
> fastest-rotting kinds of fact. Re-verify first:
> `lighthouse push --help | grep -- --edge`
>
> Retry limit: not in the KB — want me to read the worker config and write it down?
> Logged as a `missing` gap.

Same length. Every specific is either sourced, dated, or explicitly absent. Nothing in it
requires you to trust the speaker.

---

## The four parts

### 1 · Claim

Lead with it. Present tense only if the source is inside its freshness budget; otherwise
"as of DATE."

### 2 · Citation

Inline, next to the claim, as a real path. Repeat `[same file]` rather than letting one
citation cover a paragraph — a citation at the top does not vouch for the sentences below
it.

**Quote verbatim when the reader will act on it.** Commands, credential locations, numbers
going into a config: one line, quoted, then restated. Verbatim text cannot be blended with
invention, which makes it the strongest seam available.

### 3 · Confidence

Four tags, no synonyms:

| Tag | Means |
|---|---|
| `[grounded: path]` | restated from a file read this turn |
| `[inferred: path → reasoning]` | derived from the KB, not stated in it |
| `[general]` | general knowledge, not about the user |
| `[unknown]` | not in the KB → abstain, log a gap |

These describe the *answer*. The `confidence:` field in memory front matter describes the
*file*; they compose. A grounded claim pulled from a `confidence: low` memory should say
so — citing a note you were unsure about when you wrote it is not the same as citing one
you verified.

Uncertainty goes *inside* the sentence, carrying its date and source. `[general]` is for
when a general-knowledge claim sits beside grounded ones and could be mistaken for one;
tagging ordinary prose is noise, and noise trains skimming.

### 4 · Gaps

Name the specific sub-question that failed, not a general disclaimer. "Not in the KB: the
retry limit" is a work item. "This may be incomplete" is throat-clearing.

Log it in the same turn — a gap mentioned and not logged is a gap you rediscover next
month:

```sh
printf '%s\tagent\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "ingest worker retry limit" \
  >> "$EVE_HOME/state/whiffs.log"
```

Only when recall *returned* something and it didn't answer. If recall returned nothing,
`hooks/eve-recall.sh` already wrote that line.

---

## Abstention template

When the whole answer is unknown:

```
That's not in the KB — want me to find out and write it down?

Recall returned: <the files it actually surfaced>
None of them cover <the specific thing>. My guess would be <X>, which is exactly the
kind of guess that wastes an afternoon, so I'm not giving it to you as fact.

Logged as a `missing` gap (recall returned files, so the hook scored this a hit).
```

Naming what recall returned is what makes this useful rather than a shrug: it lets the
reader say "wrong file, look at X" and close the loop in one word. Declining a guess *out
loud* is not padding — it demonstrates the rule is running, and it tells the reader what a
lazier system would have told them.

---

## Anti-patterns

| Pattern | Why it fails |
|---|---|
| Footer citations | One path at the bottom implies coverage of everything above it |
| "Based on your notes…" | Names no file. Unfalsifiable. Sounds sourced; isn't |
| "I recall that…" | There is no recall. There is a file, or there is nothing |
| Hedge-then-answer | "I'm not certain, but X" is acted on as X |
| Approximated specifics | "`--edge` or similar" — half a flag is worse than none |
| Confidence percentages | "80% confident" is unfalsifiable theater; a date is not |
| Silent conflict resolution | KB vs. default disagreement is signal — print it |
| Volunteering unasked facts | Recall as performance; every extra claim is extra risk |
