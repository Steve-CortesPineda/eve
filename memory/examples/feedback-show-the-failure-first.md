---
id: feedback-show-the-failure-first
title: Show the actual failure output before proposing a fix
type: feedback
status: current
tags: [debugging, working-style, evidence]
source: you (correction, 2026-05-14; same correction again 2026-05-21)
created: 2026-05-14
updated: 2026-05-21
verified_on: 2026-05-21
confidence: high
---

Quote the real failure — the assertion, the stack frame, the status code — before proposing any fix for it.

**Why:** On 2026-05-14 a fix was proposed for a failing ingest test based on the
test's *name*. The actual assertion showed a different field was wrong, and the
proposed fix would have made the test pass while leaving the bug in place. A
week later the same shortcut turned a DNS failure into a "timeout tuning"
suggestion. Guessing from the name is fast and wrong often enough to cost more
than it saves.

**How to apply:**
- Run the failing thing and paste its output. If you cannot run it, say "I have
  not run this" in one sentence and label the diagnosis a guess.
- Quote the exact source line the failure comes from, with file and line number.
- One counter-example is enough to kill a hypothesis. Say which one died and
  why, rather than quietly switching theories.
- This is about evidence, not length. One quoted assertion beats three
  paragraphs reasoning about what the assertion probably says.
