---
id: carrier-throttle-returns-empty-200
title: The carrier tracking API signals throttling with an empty 200, not a 429
type: reference
status: current
tags: [carrier-api, external, retries]
source: carrier developer documentation, read 2026-05-02; behaviour observed in staging traffic the same day
created: 2026-05-02
updated: 2026-05-02
verified_on: 2026-05-02
confidence: medium
---

The carrier tracking API allows sixty requests a minute per key. Over that limit it answers HTTP 200 with an empty body — not 429, and not an error object.

**Why:** Retry logic keyed on the status code never fires, so a throttled run
looks identical to a run where every shipment legitimately had no tracking
events. The failure is silent and the data it produces looks plausible, which
is why it survived two releases.

**How to apply:**
- Treat a 200 with an empty body as throttling, not as "no events found".
- Back off before retrying. An empty response is not evidence the request was
  cheap.
- Re-check this before relying on it. It is vendor behaviour watched on one
  day and the vendor can change it without announcing anything.
