---
title: Staging for Harborlight is a single host, not a cluster
type: reference
tags: [harborlight, infra, deploy]
created: 2026-01-22
updated: 2026-04-30
status: active
---

Staging is one machine. There is no load balancer in front of it, so a restart
is user-visible to anyone testing against it.

<!-- eve:check host staging.harborlight.internal -->
<!-- eve:check url https://staging.harborlight.internal/healthz -->

Both checks above are network checks and are skipped unless the reconcile loop
is run with `--net`. On a machine outside the office network they will not
resolve, which is why the loop treats a whole-run failure as inconclusive
rather than as evidence that staging was decommissioned.
