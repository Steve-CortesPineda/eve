---
id: secrets-live-in-the-vault-not-the-image
title: Secrets live in the vault and are never baked into an image
type: feedback
status: current
tags: [security, build, credentials]
source: you (correction, 2026-03-04)
created: 2026-03-04
updated: 2026-03-04
verified_on: 2026-03-04
confidence: high
---

Every credential is read from the vault at process start. Nothing is written into a build artifact, an environment file that ships, or a layer of an image.

**Why:** A build layer is permanent. On 2026-03-02 a token was added to a
Dockerfile "just for the staging build" and the layer was pushed to the shared
registry, where it stayed readable long after the token was rotated out of the
running service. Rotating the credential does not remove it from the artifact,
and the artifact is what an attacker gets.

**How to apply:**
- Do not put a credential in a Dockerfile, a build argument, a committed config
  file, or a test fixture, even temporarily.
- Read them at start-up from the vault client. A missing credential should
  crash the process loudly, never fall back to a default.
- If one does leak into a layer, rotating is not enough. The artifact has to be
  deleted from the registry too.
