---
kind: decision
date: 2031-03-09
status: active
supersedes: services/vireo-gateway.md#request-body-limit
---

# Raise the gateway request body limit to 10 MiB

> FICTIONAL FIXTURE. Nothing here describes a real system.

## Decision

The `vireo-gateway` maximum request body is now **10 MiB**, raised from 2 MiB.

This **supersedes** the 2 MiB figure stated in
`services/vireo-gateway.md#request-body-limit` and in
`decisions/2030-04-18-adopt-vireo-gateway.md`. Those files have not been edited;
this record is newer and wins.

## Why

Bulk document submission was being chunked client-side purely to fit under 2 MiB,
and the chunking logic was the source of most of the malformed-payload errors we
saw. Raising the ceiling deleted the chunking layer entirely.

## Consequences

- The edge now buffers up to 10 MiB per in-flight request. Memory headroom at the
  gateway was rechecked before the change and is adequate at current concurrency.
- The upstream request timeout is unchanged at 8 seconds. A 10 MiB body on a slow
  connection can now exhaust that timeout where a 2 MiB body could not.
