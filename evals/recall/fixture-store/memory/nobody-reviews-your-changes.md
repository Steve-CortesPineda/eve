---
id: nobody-reviews-your-changes
title: Nobody reviews your changes, so keep them small
type: feedback
status: current
tags: [review, working-style, risk]
source: you (stated 2026-04-02, restated 2026-06-30)
created: 2026-04-02
updated: 2026-06-30
verified_on: 2026-06-30
confidence: high
---

There is no second pair of eyes on anything you merge. The size of a change is the only real control on its risk.

**Why:** Advice written for teams assumes review catches the obvious mistake.
Here nothing does. The two changes that caused real damage were both large,
both self-merged, and both contained one small error that any reader would
have caught in a minute.

**How to apply:**
- Prefer several small merges to one large one, even when the large one is
  tidier.
- Say plainly which part of a change is the risky part; there is no reviewer to
  work it out independently.
- Anything touching money or customer data gets a written rollback plan before
  it merges, not after.
