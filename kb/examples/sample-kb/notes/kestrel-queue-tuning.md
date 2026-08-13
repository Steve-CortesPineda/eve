---
id: kestrel-queue-tuning
title: Kestrel queue tuning for the render pool
type: note
status: current
tags: [kestrel, queue, performance]
source: you
created: 2024-10-28
updated: 2024-11-04
verified_on: 2024-11-04
confidence: medium
---

# Kestrel queue tuning for the render pool

Notes from tuning the Kestrel queue that feeds Tessellate's render workers.

## Settings that mattered

- Prefetch of 1 beat every larger value. Render jobs have a long tail, and any
  prefetch above 1 lets a worker sit on a queued job while another worker is
  idle.
- Visibility timeout at 5x the median render time. Below 3x, slow pages got
  redelivered and rendered twice.
- Batch acknowledgement was a loss. The ack round trip is not the bottleneck
  and batching made redelivery-after-crash much worse.

## Numbers

Measured on the old four-core runner against a 12k-page fixture. Median render
was 40 ms, p99 was 1.9 s, and the long tail was almost entirely pages with
large embedded tables.

These numbers are from the previous hardware and an older Kestrel release. They
have not been re-measured since.
