---
id: tess-verify-checks
title: What tess verify actually checks
type: note
status: current
tags: [deploy, tessellate, verify]
source: export:runbooks
created: 2026-08-13
verified_on: 2026-08-13
confidence: high
source_sha256: 34ed68c192bf7897cc8fc921a30f020180aaf0730bb083eeaa5395bc058427a7
---

`tess verify` runs five checks against a built `dist/` directory. It is a
post-build gate, not a linter — it never looks at source.

1. **Asset byte length.** Every asset referenced from HTML must exist and be
   non-empty. This is the check that catches a symlink-flattening sandbox.
2. **Internal links.** Every internal href must resolve to a file in `dist/`.
   External links are not fetched.
3. **Duplicate output paths.** Two manifest entries rendering to the same path
   is a config error and fails the build.
4. **Config hash marker.** `dist/.tess-build` records the resolved config hash.
   If it is missing, the build came from an unknown Tessellate version.
5. **Encoding.** Every emitted HTML file must be valid UTF-8.

Exit code is 0 or 1. There is no partial-success mode on purpose: a deploy gate
that can be half-passed gets ignored.
