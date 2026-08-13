# prompts/

Paste-ready artifacts that implement the grounding doctrine. The reasoning behind every
line is in [`docs/08-grounding.md`](../docs/08-grounding.md); this directory is the part
you install.

| File | What it is | When |
|---|---|---|
| [`grounding-rules.md`](grounding-rules.md) | **The `CLAUDE.md` block.** Seven rules, ~60 lines | Install first |
| [`system-prompt.txt`](system-prompt.txt) | Same doctrine, plain text, for a local or non-Claude model | Driving another model |
| [`grounded-answer.md`](grounded-answer.md) | The shape of a good answer: claim, citation, confidence, gaps | Reference / teaching |
| [`citation-audit.md`](citation-audit.md) | Self-audit pass, per-sentence | Before acting on a long answer |
| [`grounding-eval.md`](grounding-eval.md) | Manual 10-minute spot-check, incl. injection | After install, and after any rules change |

For the scored version, use [`evals/`](../evals/) — 20 questions over a fictional fixture
KB, gated. The manual spot-check exists alongside it because two of the behaviors that
matter most (over-abstention, and injection resistance) need an out-of-scope or poisoned
input, which a KB question set cannot provide.

## Install

```sh
grep -q '^## Grounding rules' CLAUDE.md 2>/dev/null \
  || cat prompts/grounding-rules.md >> CLAUDE.md
```

That file *is* the block, verbatim — appending produces valid `CLAUDE.md`, and the guard
makes a second run a no-op. The leading HTML comment is invisible when rendered and tells
the next reader where the doctrine lives.

## Paths to adjust

The artifacts assume Eve's default store. If yours differs, change these and nothing else:

- **memories** — `memory/<id>.md` in citation examples
- **gap ledger** — `$EVE_HOME/state/whiffs.log` in rule 4, the same file
  `hooks/eve-recall.sh` writes and `loops/gap-detection/` reads

Nothing in the doctrine depends on either path.

## Why the rules block is short

A rules file nobody reads is a failed rules file, and a long one degrades faster under
context pressure — the tail of a 500-line block competes with your actual conversation for
the model's attention. Everything explanatory lives in `docs/`; the block holds only what
must be in context on every turn.

If you extend it, add mechanisms rather than prose. A rule that no file, hook, or shell
check enforces is a wish, and wishes do not survive turn 40.
