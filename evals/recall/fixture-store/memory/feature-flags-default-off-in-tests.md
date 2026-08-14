---
id: feature-flags-default-off-in-tests
title: Feature flags default to off in tests, whatever production says
type: decision
status: current
tags: [testing, feature-flags, ci]
source: you (decision, 2026-03-27)
created: 2026-03-27
updated: 2026-03-27
verified_on: 2026-03-27
confidence: high
---

The test harness starts every flag off and ignores the production flag service entirely. A test that needs a flag on turns it on itself, in the test.

**Why:** Reading live flag state made the suite pass or fail depending on what
somebody had toggled that morning, and the failure appeared in whichever test
happened to run first. A test that depends on a value it does not set is not a
test, it is a report on the environment.

**How to apply:**
- Turn the flag on inside the test that needs it, and turn it off after.
- Never read the flag service from a test, not even to assert a default.
- When a flag is fully rolled out, delete it and the branch behind it. A flag
  that is never off in production is dead code with a switch attached.
