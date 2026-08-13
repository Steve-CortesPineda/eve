---
title: What tess verify actually checks
tags: [tessellate, verify, deploy]
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
