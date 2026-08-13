---
id: reference-carrier-throttle-returns-200
title: The carrier tracking API signals throttling with an empty 200, not 429
type: reference
status: current
tags: [carrier-api, external, retries]
source: carrier developer docs "Rate limits" section, read 2026-05-02; empty-body behaviour observed in staging traffic the same day
created: 2026-05-02
updated: 2026-05-02
verified_on: 2026-05-02
confidence: medium
---

The carrier tracking API allows 60 requests per minute per key. Over the limit it returns HTTP 200 with an empty body — not 429, and not an error object.

**Why:** Retry logic keyed on the status code never fires, so a throttled run
looks exactly like a run where every shipment legitimately had no tracking
events. The failure is silent and produces plausible-looking data, which is why
it went unnoticed through two releases.

**How to apply:**
- Treat a 200 with an empty body as throttling, not as "no events found".
- Back off before retrying. An empty response is not evidence that the request
  was cheap.
- Verify before relying on this. It is vendor behaviour observed on a single
  day, and a vendor can change it without announcing it. If the answer matters,
  re-read their docs and say when you last checked.
- `confidence: medium` is deliberate: the rate limit came from documentation,
  the empty-200 behaviour came from watching traffic. Half of this claim is
  better evidenced than the other half.
