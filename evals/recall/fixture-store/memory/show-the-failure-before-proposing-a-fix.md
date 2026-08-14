---
id: show-the-failure-before-proposing-a-fix
title: Show the real failure output before proposing a fix
type: feedback
status: current
tags: [debugging, evidence, working-style]
source: you (correction, 2026-01-16; repeated 2026-02-20)
created: 2026-01-16
updated: 2026-02-20
verified_on: 2026-02-20
confidence: high
---

Quote the actual assertion, stack frame or status code before suggesting anything that would change it.

**Why:** On 2026-01-16 a fix was proposed from a test's *name* alone. The real
assertion showed a different field was wrong, and the suggested change would
have made the test green while leaving the defect untouched. A month later the
same shortcut turned a name resolution failure into a confident recommendation
to tune timeouts.

**How to apply:**
- Run the failing thing and paste what it printed. If you cannot run it, say so
  in one sentence and label the diagnosis a guess.
- Quote the source line the failure comes from, with its file and line number.
- One counter-example kills a hypothesis. Say which one died rather than
  quietly switching theories.
