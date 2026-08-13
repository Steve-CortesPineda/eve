---
kind: decision
date: 2030-04-18
status: active
---

# Adopt vireo-gateway as the single edge

> FICTIONAL FIXTURE. Nothing here describes a real system.

## Decision

Put every external request through `vireo-gateway`. Retire the per-service edge
configuration that each service was carrying.

## Why

TLS termination and auth checking were implemented three times, slightly
differently, in three services. Two of the three were wrong in ways nobody noticed
until they disagreed. Doing it once, in one place, at the edge, removes the class of
bug rather than the instances.

The cost is a hard dependency: nothing is reachable without the gateway, so the
gateway is now the thing that has to not fall over.

## Configuration set at adoption

- Upstream request timeout: 8 seconds.
- Maximum request body: 2 MiB.

Both numbers are recorded in `services/vireo-gateway.md`. If a later decision
record changes one of them, that later record wins over this one and over the
service file.
