# Documentation

Eve is a curated store of markdown files, retrieved automatically on every
prompt, so a coding agent stops starting from zero every session.

**If you read two chapters, read [01](01-why.md) and [02](02-memory-format.md).**
Everything after those is optional machinery. **If you read one, read
[02](02-memory-format.md)** — the format is the product; the code is a
convenience.

## The chapters

| | | Read it when |
|---|---|---|
| [01 · Why](01-why.md) | The failure this exists to fix, why a bigger context window is not the answer, and what the obvious alternatives cost. | Before deciding whether any of this is worth your time. |
| [02 · The memory format](02-memory-format.md) | **The core.** One claim per file, the field schema, title discipline, the four families, tombstones, staleness, and what must never go in a memory. | First. This is the part worth stealing even if you write your own code. |
| [03 · Tier 1 — the hooks](03-hooks.md) | The three hooks, the retrieval engine and its weights, hook contracts, security of injected content, measured performance, portability, and the config keys. | When you want retrieval to happen without the model choosing to. |
| [04 · Learning loops](04-loops.md) | The rules a loop has to obey to be allowed to exist: name your consumer, never delete on a clock, two gates before automatic correction. | Before writing any automation over the store. |
| [05 · Design laws](05-design-laws.md) | Twelve laws, each from a specific failure, with the general lesson rather than the war story. | The most portable chapter. Useful even if you never install Eve. |
| [06 · Adoption](06-adoption.md) | Day 1, week 1, month 1. Migrating an existing pile of notes. How to tell it is working, and when to stop growing it. | When you have decided to try it. |
| [07 · The front layer](07-front-layer.md) | Optional Tier 2: sample cheap local signals, compose a session brief. Exactly what is collected and how to turn each signal off. | Only if "what was I doing" is a real cost for you. |
| [08 · Grounding](08-grounding.md) | Keeping an agent from laundering a guess into a citation: the seam, seven rules, a claim taxonomy, confidence vocabulary. | When the store is big enough that you start trusting what it says. |
| [09 · The knowledge-base layer](09-kb-layer.md) | Optional heavier tier: provenance, ingestion, consolidation, search over long documents. When to use it instead of an atomic memory. | Only when atomic memories genuinely stop fitting. |
| [10 · Evals](10-evals.md) | A hallucination eval over a fictional fixture store: four question categories, the citation check, reading the scorecard, and its limits. | When you want a number instead of an impression. |

## The tiers

| | What it is | Where |
|---|---|---|
| **Tier 0** | The file format, an index, and a rule block in `CLAUDE.md`. No code at all. | [02](02-memory-format.md), [06](06-adoption.md) |
| **Tier 1** | Three hooks and the `eve` CLI: recall on every prompt, a brief at session start, a log at session end. | [03](03-hooks.md) |
| **Tier 2** | Optional and off by default: the front layer, the learning loops, the KB layer. | [07](07-front-layer.md), [04](04-loops.md), [09](09-kb-layer.md) |

Tier 0 gets you most of the value. Tier 1 is the idea worth stealing even if you
write your own version: **move the discipline out of the model and into the
harness.**

## Also in the repo

| | |
|---|---|
| [`../memory/TEMPLATE.md`](../memory/TEMPLATE.md) | The blank memory, with the field rules inline. |
| [`../memory/examples/`](../memory/examples/) | Four worked memories, one per family. All fictional — read them, do not copy them into your store. |
| [`../prompts/`](../prompts/) | Paste-ready grounding blocks for agents that are not Claude Code. |
| [`../evals/`](../evals/) | The eval suite from chapter 10, and the fixture store it runs against. |
| [`../loops/`](../loops/) | The three learning loops. Reference implementations, not products — read [04](04-loops.md) before running one. |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | What a change has to satisfy, including the rule that nothing personal or machine-specific goes in. |
