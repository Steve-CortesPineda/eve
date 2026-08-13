---
title: Decided to drop offset pagination from the v3 API
type: decision
tags: [harborlight, api, decision]
created: 2026-02-28
updated: 2026-06-18
status: active
outcome: worked
outcome_date: 2026-05-02
---

We removed offset pagination in v3 rather than keeping both modes behind a
flag, accepting a breaking change for three internal callers.

**Why:** keeping both meant every list query needed two code paths and the
offset path was already returning duplicate rows under write load.

## Outcomes

- 2026-05-02 worked - duplicate-row reports went to zero and stayed there for
  six weeks.
- 2026-06-18 mixed - one caller had to be migrated by hand because it stored
  page numbers in a saved-search table nobody knew about.
