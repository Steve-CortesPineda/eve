# Harbor Pages deploy runbook

The steps to publish a Tessellate site to Harbor Pages, in order.

## Before you publish

RULE: always run `tess verify` before publishing to Harbor Pages. It asserts a
non-zero byte length on every referenced asset, which catches the class of
failure a plain HTTP 200 smoke check misses entirely.

1. `tess build --clean` — full rebuild, no cache, so a corrupt cache cannot
   hide a real breakage.
2. `tess verify dist/` — asset integrity and internal link check.
3. Eyeball `dist/index.html` for the footer. It is the thing that most often
   comes out wrong after a config change.

## Publishing

    tess deploy --target harbor --site <name>

The command is idempotent. Re-running after a partial upload resumes rather
than restarting, because Harbor Pages dedupes on content hash.

## After

Harbor Pages serves the new build behind a CDN with a five minute TTL. Do not
judge a deploy as broken until that window has passed — the most common false
alarm is looking at a cached copy of the previous build.

If the deploy has to be rolled back, `tess deploy --target harbor --rollback`
re-points at the previous build. It does not delete the bad build, so the
rollback is itself reversible.
