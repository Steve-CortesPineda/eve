---
id: tessellate-build-pipeline
title: Tessellate build pipeline
type: project
status: current
tags: [tessellate, build, pipeline, architecture]
source: you
created: 2026-04-02
updated: 2026-07-28
verified_on: 2026-07-28
confidence: high
---

# Tessellate build pipeline

Tessellate turns a directory of markdown and templates into a static site. The
pipeline is four stages, and each stage is a pure function of its inputs so any
stage can be skipped when its inputs are unchanged.

## Stages

1. **Collect** walks the content root and produces a manifest of source files
   with their content hashes. It never stats for mtime.
2. **Parse** turns each source file into an AST plus front matter. Failures are
   collected, not thrown, so one bad page does not abort a build.
3. **Resolve** builds the link graph and fails the build on any dangling
   internal link. This is the only stage that can see the whole site at once.
4. **Render** emits HTML into `dist/`, one output file per manifest entry.

## Why the manifest is content-addressed

The manifest is keyed on the SHA-256 of file bytes. A fresh checkout rewrites
every mtime, so an mtime-keyed cache rebuilds the entire site on a machine that
has never changed a byte. Content hashing makes a cold clone a no-op rebuild.

The cost is one full read of every source file per build. At the sizes
Tessellate targets (under ~20k pages) that read is dominated by render time, so
it has never been worth optimising.

## Concurrency

Render is the only parallel stage. It uses a worker pool sized to the CPU count
minus one, leaving a core for the file watcher during `tess serve`. Resolve
must stay single-threaded because the link graph is shared mutable state and
the lock contention measured worse than the serial version.

## Known sharp edges

- The parse stage holds every AST in memory at once. A site above roughly
  50k pages will page out on a 16 GB machine.
- `tess serve` does not invalidate the link graph on delete, only on write, so
  removing a page leaves a stale entry until restart.
