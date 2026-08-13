# evals/ — the hallucination suite

Full write-up: [`../docs/10-evals.md`](../docs/10-evals.md).

```sh
sh evals/run.sh                     # offline, deterministic, ~2s, no API key
sh evals/run.sh --answerer naive -v # a real retriever with no abstention
sh evals/run.sh --answerer bad -v   # the negative control
sh evals/selftest.sh                # prove the suite still catches failure
python3 evals/check_fixture.py      # prove the fixture is internally consistent
```

Score your own agent:

```sh
sh evals/run.sh --cmd './my-agent-wrapper'
```

Your command is run once per question with `{"id", "question", "kb_root"}` on
stdin. Print an answer on stdout — JSON, `ANSWER:`/`CITE:` lines, or plain prose
with inline `path.md#anchor` references all parse. Point your agent's retrieval
at `kb_root`; it is passed on stdin and in `$EVE_EVAL_KB`.

Exit code is 0 if every gate passes, 1 if any fails, 2 on a harness error. A run
also fails if your command crashed or timed out on any question — a crash asserts
nothing, and asserting nothing would otherwise score as a clean abstention.
`--allow-answerer-errors` overrides that.

## Layout

| Path | What it is |
| --- | --- |
| `fixture-kb/` | An entirely fictional KB. See its own `README.md`. |
| `questions.json` | 20 questions in 4 categories, with the answer key. |
| `run.py` / `run.sh` | Runner. Spawns an answerer per question, scores, prints. |
| `scoring.py` | Response parsing, verdicts, rates, gates. |
| `kb.py` | KB reads, anchor resolution, the citation check. |
| `check_fixture.py` | Asserts the fixture and question set stay consistent. |
| `selftest.sh` | Asserts the suite can still tell good from bad. |
| `answerers/reference.py` | The ideal answer, from a fixture answer key. |
| `answerers/naive_keyword.py` | Honest tf-idf retrieval, no abstention. |
| `answerers/bad.py` | Negative control: guesses and fabricates citations. |

Requires `python3` and a POSIX shell. Nothing else.

## The one thing to understand

The seven `ABSENT` questions matter more than the thirteen answerable ones. They
ask things that are *not in the fixture KB and never were*, phrased to sit right
next to things that are. Any retriever will return a passage for them, because
retrieval always returns its best match. Only a system with an abstention
discipline returns nothing.

`--answerer naive` demonstrates this in about two seconds: honest retrieval,
several answerable questions correct, and **0 of 7** correct abstentions.
