# Fixture KB — entirely fictional

**Nothing in this directory is real.** Ovenbird Systems does not exist. Neither do
`vireo-gateway`, `marmot-scheduler`, `hoopoe-indexer`, the Ribbon or Bramble queue
backends, or any of the dates, numbers, incidents and decisions recorded here. Every
byte of it was invented for the Eve hallucination eval suite. Do not cite it, copy it
into a real knowledge base, or treat any number in it as advice.

It is written in the future (2029–2031) so that it can never be mistaken for a record
of anything.

## Why a fixture KB at all

You cannot measure hallucination against a knowledge base that changes. The eval
suite needs a corpus where *we* decide, in advance and exactly, which facts exist,
which are stale, which were superseded, and — most importantly — which plausible-sounding
facts are **absent**. That last category is the whole point of the suite and it is
impossible to construct against a real KB, because you can never prove a real KB
doesn't mention something somewhere.

## Structure

```
fixture-kb/
  index.md                 entry point, links the rest
  services/                one file per service, long-lived
  decisions/               dated decision records, append-only
  notes/                   dated working notes, some stale, some superseded
```

The layout mirrors the shape Eve's own `memory/` directory encourages: durable
descriptions in one place, dated records in another, and supersession expressed by
a newer dated file that names the older one — not by editing the older one.

## The four fact shapes it has to support

| Shape | How it looks here |
| --- | --- |
| Stated once, current | A durable service file states a number and nothing contradicts it |
| Stale | The file carries a `review_by` date that the reference date has passed |
| Superseded | An older file still states the old value; a newer dated file names it and overrides it |
| Absent | A topic is discussed qualitatively but the specific quantity was never written down |

The absent facts are deliberately *adjacent* to real ones — same service, same
paragraph, sometimes the same sentence. An agent that pattern-matches on topic
rather than on fact will answer both kinds identically, which is exactly what the
suite is built to catch.

This file deliberately does not list which facts are absent. That would defuse the
trap for any agent that reads the directory before answering. `README.md` at this
root is excluded from the retrievable corpus for the same reason — the question set
in `../questions.json` is the only place the answer key lives.

**Reference date for the whole fixture: `2031-06-01`.** Staleness is judged against
that fixed date, not against today, so the suite's scores do not drift over time.
