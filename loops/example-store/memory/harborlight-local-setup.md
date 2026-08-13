---
title: Harborlight runs locally from a checkout, not from a container
type: reference
tags: [harborlight, dev-env]
created: 2026-02-11
updated: 2026-06-02
status: active
---

Harborlight is run locally straight from the checkout. There is no dev
container and the compose file in the repo is for CI only.

**Setup:** the service reads its config from an absolute path, and the manifest
fixtures live outside the repo so they survive a clean clone.

<!-- eve:check file /etc/hosts -->
<!-- eve:check dir /tmp -->
<!-- eve:check cmd awk -->
<!-- eve:check cmd harborctl -->
<!-- eve:check file /opt/harborlight/fixtures/manifests.jsonl -->

The `harborctl` helper wraps the migration and seed commands. If it is not on
PATH, the checkout is incomplete rather than broken.
