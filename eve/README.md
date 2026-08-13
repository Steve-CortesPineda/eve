# eve/ — the front layer

Optional. Off until you configure a root. Tiers 0 and 1 are the product; this is
the convenience on top.

An agent that knows what you were doing beats one that asks. This layer samples
cheap local signals on an interval — which files changed under the project roots
you named, what branch you are on, whether the tree is dirty — and composes a
short factual briefing so a session opens already knowing where you left off.

Full documentation, including the complete privacy posture and how to turn each
signal off: **[../docs/07-front-layer.md](../docs/07-front-layer.md)**.

## Files

| Path | What it is |
|---|---|
| `bin/eve-front` | the CLI: `brief`, `recall`, `remember`, `sync`, `doctor`, `sample`, `sampler`, `install` |
| `bin/eve-sample` | one sample of local signals, appended to `$EVE_HOME/state/activity.log` |
| `bin/eve-brief` | composes the briefing; writes `$EVE_HOME/state/brief.md` |
| `lib/front-common.sh` | config parser and portability helpers, sourced by all three |
| `templates/sampler.plist` | launchd agent, placeholders filled by `eve-front sampler plist` |
| `templates/sampler.cron` | crontab line, placeholders filled by `eve-front sampler cron` |

## Quick start

```sh
./bin/eve-front install                                   # copies into ~/.eve/bin
printf 'EVE_SAMPLE_ROOTS=%s\n' "$HOME/src/yourproject" >> ~/.eve/config
~/.eve/bin/eve-front sample --verbose                     # first run sets a marker
~/.eve/bin/eve-front sample --verbose                     # later runs report changes
~/.eve/bin/eve-front brief
~/.eve/bin/eve-front doctor
```

Then schedule it: `eve-front sampler plist` (macOS) or `eve-front sampler cron`
(Linux). Uninstall instructions are in the doc.

## Ground rules these scripts follow

- POSIX `sh`. No bash 4 syntax (macOS ships bash 3.2), no `eval`, no
  `timeout(1)`, no non-portable `stat`, `realpath`, or `readlink -f`. Verified
  under `dash` as well as macOS `/bin/sh`.
- Paths and counts, never file contents. No network calls anywhere in this
  layer.
- Nothing here deletes a memory. The only deletions are derived copies inside
  `$EVE_HOME/mirrors`, and only files carrying the header that put them there.
- Every producer names its consumer in its header comment. A log nothing reads
  is a bug, not a feature.
