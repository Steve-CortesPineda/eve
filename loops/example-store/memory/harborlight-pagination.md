---
title: Harborlight uses cursor pagination, not offset
type: reference
tags: [harborlight, api]
created: 2026-02-28
updated: 2026-05-06
status: active
---

Every list endpoint on Harborlight returns an opaque `next_cursor`. Offset
pagination was removed in v3 because manifests are inserted continuously and
offsets skipped rows under write load.

**How to apply:** never suggest `?page=` or `?offset=` for a Harborlight
endpoint. Pass the cursor back verbatim; it is a string and must not be
decoded, incremented, or compared.
