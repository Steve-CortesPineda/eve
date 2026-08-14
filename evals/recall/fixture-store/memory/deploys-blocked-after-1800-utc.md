---
id: deploys-blocked-after-1800-utc
title: Deploys to production are blocked after 18:00 UTC
type: decision
status: current
tags: [deploy, release, oncall]
source: you (team decision, 2026-02-11)
created: 2026-02-11
updated: 2026-05-03
verified_on: 2026-05-03
confidence: high
---

Production deploys are blocked after 18:00 UTC on weekdays and all weekend. The pipeline refuses; there is no override flag.

**Why:** Two of the three worst outages started with a late deploy that nobody
was awake to watch. The 2026-01-29 incident ran for six hours because the
person who pushed the change had gone to bed and the on-call engineer did not
know the change had landed. The window is not about the risk of the change, it
is about whether a human is available to notice it going wrong.

**How to apply:**
- Check the clock before starting anything that ends in a release. If the work
  will not be finished and watched inside the window, park it for the morning.
- A revert is not a deploy for this purpose. Rolling back is always allowed.
- If something genuinely cannot wait, page the on-call engineer first and get
  them watching before the pipeline runs, not after.
