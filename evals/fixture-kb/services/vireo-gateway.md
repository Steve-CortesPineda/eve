---
kind: service
name: vireo-gateway
date: 2030-04-18
review_by: none
---

# vireo-gateway

> FICTIONAL FIXTURE. Nothing here describes a real system.

Edge HTTP service. Terminates TLS, checks auth tokens, and forwards to internal
services. Every external request enters through it; nothing else is reachable from
outside.

## Request timeout

The upstream request timeout is **8 seconds**. A request that has not received
headers from the upstream service in 8 seconds is cut and returns a gateway timeout
to the caller.

This number was picked to sit just under the client library's own 10 second
deadline, so that a timeout is always attributed to the gateway rather than to the
caller's socket.

## Request body limit

The maximum accepted request body is **2 MiB**. Larger bodies are rejected at the
edge without being buffered.

## Auth

Tokens are checked at the edge and the decoded subject is forwarded to the upstream
service in a request header. Upstream services do not re-check the token; they trust
the gateway.

## What is not here

Latency targets, error budgets and alerting thresholds are not recorded in this
file, and as of the reference date they are not recorded anywhere else either.
