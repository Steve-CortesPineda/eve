# evals/recall — does the store give the memory back?

Full write-up: [`../../docs/10-evals.md`](../../docs/10-evals.md), section
"Second suite: retrieval recall".

```sh
sh evals/recall/run.sh              # score this repo's bin/eve  (~4s, offline)
sh evals/recall/run.sh -v           # every query and what came back
sh evals/recall/selftest.sh         # prove the gate still catches a regression
```

Exit **0** pass · **1** regression against the committed baseline · **2**
harness error. No network, no API key, no model. Requires `python3`, the same
dependency the sibling suite already has.

## Why this exists

The suite in [`../`](..) measures whether an agent *lies about a corpus*. This
one measures the step before it: whether the right memory is handed over at all.
They fail independently. A perfect hallucination score over an empty retrieval
is an agent that honestly says "not recorded" about something you wrote down
last week.

That is not hypothetical. Eve's retrieval is keyword scoring over a flat
directory, and the scorecard below is what that buys.

## The four tiers

A tier is a **measured property of the fixture**, not a label. `run.py`
re-derives it from bin/eve's own tokenisation and refuses to run if a committed
tier disagrees — so editing one word of a fixture memory cannot silently turn a
hard query into an easy one.

| tier | definition | what it tells you |
| --- | --- | --- |
| `verbatim` | 2+ surviving tokens land in the target's title, filename or tags | the ranker is wired up at all |
| `paraphrase` | 1+ token lands somewhere in the file, fewer than 2 in the high-weight fields | **the number that matters** — real mid-task questions live here |
| `disjoint` | no surviving token appears anywhere in the target | the ceiling of lexical matching. 0% is correct, not a bug |
| `out-of-scope` | nothing in the store answers this | anything returned is a false positive |

`disjoint` is not there to be fixed by tuning. No gate setting retrieves a file
that contains none of your words — it never becomes a candidate. It is there so
that the day someone adds embeddings or a synonym table, there is a number that
was 0% and is not any more. And it doubles as a precision trap: a change that
gets desperate about recall will start answering these with *wrong* memories.

## The three failures, which are not the same failure

| | what happened | cost |
| --- | --- | --- |
| `miss` | nothing came back | you lose the memory. Recoverable: `eve gaps` logs it |
| `misrank` | right memory returned, under a wrong one | mild — the hook injects the whole block |
| **`MISFIRE`** | non-empty block, right memory **nowhere in it** | the dangerous one |

A misfire hands the agent only wrong memories, carrying exactly the authority a
right one would have. Injecting an irrelevant memory with authority is this
project's stated anti-goal, so it gets its own column and its own gate.

## The regression gate

`baseline.json` is a committed floor, and it is a **measurement, not a target**.

- per tier, `recall@1` and `recall@3` may not fall
- per tier and overall, `MISFIRE` may not rise
- improvements pass, and print a reminder to re-record the floor

Both directions are load-bearing. The obvious way to lift paraphrase recall is
to lower `EVE_MIN_SCORE`, and it works — recall@1 goes 50% → 65%. It also takes
misfires from 3 to 11 and makes 3 of the 6 out-of-scope controls start
answering. `selftest.sh` performs exactly that change on a throwaway copy of
`bin/eve` and asserts this suite refuses to call it an improvement.

Deliberately changing the trade-off is allowed. Doing it without noticing is
not:

```sh
sh evals/recall/run.sh --update-baseline   # and say what you traded, in the commit
```

## Layout

| Path | What it is |
| --- | --- |
| `fixture-store/memory/` | 12 fictional memories. `EVE_HOME` points here; nothing writes to it. |
| `questions.json` | 45 pre-registered queries with their tier and expected target. |
| `baseline.json` | The committed floor. Regenerate only with `--update-baseline`. |
| `run.py` / `run.sh` | Runner, scorer, gate. |
| `lexicon.py` | A faithful copy of how `eve search` tokenises and matches. |
| `classify.py` | Which tier would this query land in? Use before adding one. |
| `selftest.sh` | Breaks the ranker five ways and asserts the suite notices. |

## Adding a query

1. `python3 evals/recall/classify.py --query "..." --target some-memory-id`
2. Add it to `questions.json` with the tier that printed.
3. `sh evals/recall/run.sh` — it will now fail, because the counts moved.
4. `sh evals/recall/run.sh --update-baseline`, and say so in the commit.

Watch step 1's output rather than trusting the tier name. The scorer matches
**substrings**, so `app` matches `capped` and `live` matches
`secrets-live-in-the-vault`. A query can land in `verbatim` on an accident like
that, and a tier earned by accident measures nothing.
