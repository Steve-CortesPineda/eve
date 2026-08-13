"""kb doctor -- report (and optionally repair) rot in the knowledge base.

A knowledge base rots in predictable ways, and all of them are detectable
without a model:

  * documents with no `verified_on`, so nobody can tell whether they are still
    true;
  * documents nobody has re-checked in a long time, still ranking as if fresh;
  * a replacement that declares `supersedes: [old]` while `old` still reads as
    current, so search returns both and the agent picks one at random;
  * duplicate ids, which break every citation that resolves by id;
  * files sitting outside the five knowledge directories, invisible to search.

--fix repairs only the mechanical half: closing supersession links, which is
purely additive (it sets `superseded_by` and flips `status`). Deciding whether
a two-year-old note is still true is a reconcile job, not a lint job -- see
loops/reality-reconcile, which re-checks claims against the world and stamps
`verified_on`. `kb doctor` tells you what to point it at.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kbcommon as kb  # noqa: E402

DEFAULT_STALE_DAYS = 180


def check(root, stale_days, fix=False):
    parse_errors = []
    docs = list(kb.iter_docs(root, errors=parse_errors))
    by_id = {}
    findings = []

    def add(level, path, line, message):
        findings.append((level, kb.display_path(path), line, message))

    for path, message in parse_errors:
        # The message already carries "path:line: detail" from the parser.
        detail = message.split(": ", 1)[-1] if ": " in message else message
        add("error", path, 1, "unreadable front matter -- %s" % detail)

    for doc in docs:
        for key in kb.REQUIRED_FM:
            if not doc.fm.get(key):
                add("error", doc.path, 1, "missing front-matter key: %s" % key)

        confidence = str(doc.fm.get("confidence") or "").lower()
        if confidence and confidence not in kb.CONFIDENCE_LEVELS:
            add("error", doc.path, 1,
                "confidence must be one of %s (got %r)"
                % ("/".join(kb.CONFIDENCE_LEVELS), confidence))

        if doc.status not in kb.STATUSES:
            add("error", doc.path, 1,
                "status must be one of %s (got %r)" % ("/".join(kb.STATUSES), doc.status))

        for key in ("created", "updated", "verified_on"):
            value = doc.fm.get(key)
            if value and not kb.parse_date(value):
                add("error", doc.path, 1, "%s is not a YYYY-MM-DD date: %r" % (key, value))

        if doc.doc_id in by_id:
            add("error", doc.path, 1,
                "duplicate id %r (also %s)" % (doc.doc_id, by_id[doc.doc_id].rel))
        else:
            by_id[doc.doc_id] = doc

        age = kb.age_days(doc.freshness_date)
        if age is not None and age > stale_days and doc.status == "current":
            add("warn", doc.path, 1,
                "not verified in %d days -- reconcile or lower confidence" % age)

    # Supersession links, in both directions.
    repaired = 0
    for doc in docs:
        for old_id in (doc.fm.get("supersedes") or []):
            old = by_id.get(str(old_id))
            if old is None:
                add("error", doc.path, 1, "supersedes unknown id: %r" % old_id)
                continue
            if str(old.fm.get("superseded_by") or "") == doc.doc_id and old.status == "superseded":
                continue
            if fix:
                old.fm["superseded_by"] = doc.doc_id
                old.fm["status"] = "superseded"
                kb.write_text(old.path, kb.render_doc(old.fm, old.body))
                repaired += 1
                add("fixed", old.path, 1, "marked superseded by %s" % doc.doc_id)
            else:
                add("warn", old.path, 1,
                    "still reads as %s but %s supersedes it -- run `kb doctor --fix`"
                    % (old.status, doc.doc_id))

    for doc in docs:
        pointer = str(doc.fm.get("superseded_by") or "")
        if pointer and pointer not in by_id:
            add("error", doc.path, 1, "superseded_by unknown id: %r" % pointer)
        if pointer == doc.doc_id:
            add("error", doc.path, 1, "document supersedes itself")

    # Files search will never see.
    known = set(kb.KNOWN_DIRS) | {kb.PROPOSAL_DIR}
    # Files that legitimately sit at the KB root and are not knowledge
    # documents: the tooling, and the gap ledger the gap-detection loop owns.
    exempt = {"bin", "lib", "examples", "README.md", "gaps.md"}
    for entry in sorted(os.listdir(root)):
        path = os.path.join(root, entry)
        if entry.startswith(".") or entry in exempt:
            continue
        if os.path.isfile(path) and entry.endswith(".md"):
            add("warn", path, 1, "markdown at the KB root is not indexed -- move it into a "
                                 "knowledge directory (%s)" % ", ".join(kb.KNOWN_DIRS))
        if os.path.isdir(path) and entry not in known:
            add("warn", path, 1, "unknown directory -- not searched")

    return docs, findings, repaired


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="kb doctor",
        description="Report front-matter and freshness problems in the knowledge base.",
    )
    parser.add_argument("--root", help="knowledge-base root (default: $EVE_KB_ROOT or kb/)")
    parser.add_argument("--stale-days", type=int, default=DEFAULT_STALE_DAYS,
                        help="warn when verified_on is older than N days (default 180)")
    parser.add_argument("--fix", action="store_true",
                        help="close supersession links (additive; never deletes)")
    parser.add_argument("--strict", action="store_true", help="exit non-zero on warnings too")
    args = parser.parse_args(argv)

    root = kb.resolve_root(args.root)
    docs, findings, repaired = check(root, args.stale_days, fix=args.fix)

    for level, path, line, message in findings:
        sys.stdout.write("%-5s %s:%d  %s\n" % (level, path, line, message))

    errors = sum(1 for f in findings if f[0] == "error")
    warns = sum(1 for f in findings if f[0] == "warn")
    sys.stdout.write(
        "%d document%s, %d error%s, %d warning%s%s\n"
        % (len(docs), "" if len(docs) == 1 else "s",
           errors, "" if errors == 1 else "s",
           warns, "" if warns == 1 else "s",
           ", %d repaired" % repaired if repaired else "")
    )
    if errors:
        return 1
    if warns and args.strict:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
