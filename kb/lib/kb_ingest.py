"""kb ingest -- file existing notes into the knowledge base, with provenance.

Design constraints, in priority order:

  1. Never mangle the original. Sources are copied, not moved, unless the user
     asks for --move. The body is preserved byte for byte; ingestion only adds
     a front-matter block above it.
  2. Idempotent. Running the same ingest twice is a no-op. Identity is the
     SHA-256 of the source body, recorded as `source_sha256`, so a file that
     moved or was renamed upstream is still recognised as already-ingested.
  3. Provenance is not optional. Every ingested document gets `source`,
     `created`, `verified_on` and `confidence`. An unattributed document is
     indistinguishable from something the agent made up, and the whole point of
     the KB is being able to tell those apart.

A source that already has front matter keeps it. Its title and tags win; the
provenance keys are filled in only where missing.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kbcommon as kb  # noqa: E402

_H1_RE = re.compile(r"^\s*#\s+(.+?)\s*$", re.MULTILINE)
_DATE_PREFIX_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})[-_ ]")


def derive_title(fm, body, filename):
    if fm.get("title"):
        return str(fm["title"])
    match = _H1_RE.search(body[:4000])
    if match:
        return match.group(1).strip()

    # Plain-text exports rarely have an H1, but they very often open with a
    # bare title line followed by a blank line. Use it when it looks like a
    # title and not like a sentence.
    lines = body.split("\n")
    if len(lines) > 1 and lines[0].strip() and not lines[1].strip():
        first = lines[0].strip()
        if len(first) <= 90 and not first.endswith((".", ",", ":", ";")):
            return first

    stem = os.path.splitext(os.path.basename(filename))[0]
    stem = _DATE_PREFIX_RE.sub("", stem)
    stem = re.sub(r"[-_]+", " ", stem).strip()
    return stem[:1].upper() + stem[1:] if stem else "Untitled"


def collect_sources(paths):
    found = []
    for raw in paths:
        path = os.path.abspath(os.path.expanduser(raw))
        if os.path.isfile(path):
            found.append(path)
        elif os.path.isdir(path):
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
                for filename in sorted(filenames):
                    if filename.startswith("."):
                        continue
                    if os.path.splitext(filename)[1].lower() in kb.TEXT_EXTS:
                        found.append(os.path.join(dirpath, filename))
        else:
            sys.stderr.write("kb ingest: no such file or directory: %s\n" % raw)
    return found


def existing_index(root):
    """Map body-hash -> rel path and id -> rel path across the whole KB."""
    by_hash, by_id = {}, {}
    for doc in kb.iter_docs(root):
        digest = doc.fm.get("source_sha256")
        if digest:
            by_hash[str(digest)] = doc
        by_id[doc.doc_id] = doc
    return by_hash, by_id


def unique_path(directory, slug, taken):
    candidate = slug
    n = 2
    while candidate in taken or os.path.exists(os.path.join(directory, candidate + ".md")):
        candidate = "%s-%d" % (slug, n)
        n += 1
    taken.add(candidate)
    return candidate


def ingest_one(source_path, root, args, by_hash, by_id, taken):
    raw = kb.read_text(source_path)
    try:
        src_fm, body, _ = kb.parse_front_matter(raw, path=kb.display_path(source_path))
    except kb.KBError as exc:
        return ("error", str(exc), None)

    body = body.strip("\n")
    if not body.strip():
        return ("skipped", "empty body", None)

    digest = kb.sha256_text(body)
    if digest in by_hash:
        return ("unchanged", by_hash[digest].rel, None)

    title = derive_title(src_fm, body, source_path)
    kind = args.type
    slug = kb.slugify(src_fm.get("id") or os.path.splitext(os.path.basename(source_path))[0])
    if not slug or slug == "untitled":
        slug = kb.slugify(title)

    date_match = _DATE_PREFIX_RE.match(os.path.basename(source_path))
    created = str(src_fm.get("created") or "")
    if not kb.parse_date(created):
        created = date_match.group(1) if date_match else args.created
    if kind == "sessions" and not _DATE_PREFIX_RE.match(slug):
        slug = "%s-%s" % (created, slug)

    prior = by_id.get(slug)
    if prior is not None:
        if not args.update:
            return ("conflict", prior.rel, None)
        fm = dict(prior.fm)
        fm["title"] = title
        fm["updated"] = args.created
        fm["verified_on"] = args.verified_on
        fm["source_sha256"] = digest
        if args.tags:
            fm["tags"] = sorted(set(list(fm.get("tags") or []) + args.tags))
        if args.confidence:
            fm["confidence"] = args.confidence
        if not args.dry_run:
            kb.write_text(prior.path, kb.render_doc(fm, body))
        by_hash[digest] = prior
        return ("updated", prior.rel, prior.path)

    directory = os.path.join(root, kind)
    slug = unique_path(directory, slug, taken)
    dest = os.path.join(directory, slug + ".md")

    tags = list(src_fm.get("tags") or [])
    tags += [t for t in args.tags if t not in tags]

    fm = {
        "id": slug,
        "title": title,
        "type": kind.rstrip("s") if kind != "research" else "research",
        "status": str(src_fm.get("status") or "current"),
        "tags": sorted(set(tags)),
        "source": str(src_fm.get("source") or args.source or
                      "file:" + kb.display_path(source_path)),
        "created": created,
        "verified_on": str(src_fm.get("verified_on") or args.verified_on),
        "confidence": str(src_fm.get("confidence") or args.confidence),
        "source_sha256": digest,
    }
    for key, value in src_fm.items():
        if key not in fm and key not in ("id",):
            fm[key] = value

    if not args.dry_run:
        kb.write_text(dest, kb.render_doc(fm, body))
        if args.move:
            os.remove(source_path)

    by_hash[digest] = kb.Doc(dest, os.path.relpath(dest, root), fm, body, 0, kind)
    by_id[slug] = by_hash[digest]
    return ("ingested", os.path.relpath(dest, root), dest)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="kb ingest",
        description="File existing notes into the knowledge base with provenance front matter.",
    )
    parser.add_argument("sources", nargs="+", help="files or directories to ingest")
    parser.add_argument("--root", help="knowledge-base root (default: $EVE_KB_ROOT or kb/)")
    parser.add_argument("--type", default="notes", choices=list(kb.KNOWN_DIRS),
                        help="destination knowledge directory (default: notes)")
    parser.add_argument("--source", help="provenance label, e.g. 'export:wiki' or a URL")
    parser.add_argument("--tags", default="", help="comma-separated tags to add")
    parser.add_argument("--confidence", default="medium",
                        choices=list(kb.CONFIDENCE_LEVELS))
    parser.add_argument("--verified-on", dest="verified_on", default=kb.today(),
                        help="date the content was last checked against reality (YYYY-MM-DD)")
    parser.add_argument("--created", default=kb.today(),
                        help="fallback creation date when the source has none")
    parser.add_argument("--update", action="store_true",
                        help="rewrite the body when a document with the same id exists")
    parser.add_argument("--move", action="store_true",
                        help="delete the source after a successful ingest (default: keep it)")
    parser.add_argument("--dry-run", action="store_true", help="report actions, write nothing")
    args = parser.parse_args(argv)

    args.tags = [t.strip() for t in args.tags.split(",") if t.strip()]
    if not kb.parse_date(args.verified_on):
        kb.die("--verified-on must be YYYY-MM-DD")
    if not kb.parse_date(args.created):
        kb.die("--created must be YYYY-MM-DD")

    root = kb.resolve_root(args.root)
    kb.ensure_dirs(root)

    sources = collect_sources(args.sources)
    if not sources:
        kb.die("nothing to ingest")

    by_hash, by_id = existing_index(root)
    taken = set()
    tally = {}
    rows = []

    for source_path in sources:
        status, detail, _ = ingest_one(source_path, root, args, by_hash, by_id, taken)
        tally[status] = tally.get(status, 0) + 1
        rows.append((status, kb.display_path(source_path), detail))

    width = max(len(r[0]) for r in rows)
    for status, src, detail in rows:
        sys.stdout.write("%-*s  %s\n" % (width, status, detail if status != "error" else detail))
        if status in ("conflict",):
            sys.stdout.write(
                "%-*s  ^ same id, different content -- rerun with --update to replace\n"
                % (width, "")
            )
        if status in ("ingested", "updated", "unchanged") and os.environ.get("KB_VERBOSE"):
            sys.stdout.write("%-*s  <- %s\n" % (width, "", src))

    summary = ", ".join("%d %s" % (count, name) for name, count in sorted(tally.items()))
    prefix = "dry-run: " if args.dry_run else ""
    sys.stdout.write("%s%s (%s)\n" % (prefix, summary, kb.display_path(root)))
    return 1 if tally.get("error") or tally.get("conflict") else 0


if __name__ == "__main__":
    raise SystemExit(main())
