# kb — the knowledge-base layer

The deep store. Long-form reference the agent **searches on demand**, as opposed to
the handful of atomic memories in [`../memory/`](../memory/) that are always present
and gate behaviour.

Full explanation: [`../docs/09-kb-layer.md`](../docs/09-kb-layer.md).

## The five-second rule

> **Would you want this sentence in front of the model on every single request,
> even for unrelated work?**
>
> Yes → `memory/`. No → `kb/`.

## Layout

```
kb/
  notes/       durable facts and how-tos that are not about one project
  projects/    how one system of yours is built, and why
  sessions/    what happened on a given day — the raw material for promotion
  decisions/   a call you made, with the reasoning that made it
  research/    material from outside your head; always carries a source
  proposals/   NOT knowledge — consolidation output awaiting your review
```

## Commands

```sh
kb search <query...>   # ranked passages, each with a path:line citation
kb ingest <paths...>   # file existing notes in, with provenance front matter
kb consolidate         # propose promotions to atomic memory (never promotes)
kb doctor              # missing provenance, staleness, broken supersedes
```

`kb` is a POSIX `sh` script over stdlib `python3`. No packages, no index files, no
network. Point it anywhere with `--root` or `$EVE_KB_ROOT`.

## Try it without touching your own KB

```sh
kb/bin/kb search cache invalidation --root kb/examples/sample-kb
kb/bin/kb doctor --root kb/examples/sample-kb
kb/bin/kb consolidate --root kb/examples/sample-kb --since 36500 --stdout
```

`examples/sample-kb/` is a small fictional knowledge base — a made-up static-site
tool called Tessellate. It ships with two planted problems (one stale document, one
unclosed supersession chain) so `kb doctor` has something to find. `examples/incoming/`
holds raw un-ingested notes for trying `kb ingest`.

The sample carries fixed dates, so the wide `--since` window above is deliberate — on
your own KB the default (`--since 14`) is the one you want.
