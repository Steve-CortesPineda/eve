#!/usr/bin/env python3
"""What tier does this query belong to? — a maintainer tool, not part of scoring.

Adding a query to `questions.json` means declaring its tier, and run.py will
reject the declaration if it disagrees with the measured overlap. Use this to
find out what the answer is before you commit the guess:

    python3 evals/recall/classify.py --query "can we ship this evening" \\
                                     --target deploys-blocked-after-1800-utc

    python3 evals/recall/classify.py evals/recall/questions.json

It also prints WHICH tokens matched and where, which is usually the interesting
part. A query can land in `verbatim` by accident — "app" is a substring of
"capped", and the scorer matches substrings — and a tier that was earned by an
accident like that measures nothing.
"""
import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from lexicon import Store, load_stopwords, tokenise  # noqa: E402

ROOT = HERE.parent.parent


def show(store, stopwords, query, target):
    toks = tokenise(query, stopwords)
    if target is None:
        print(f"  out-of-scope         tokens={toks}   {query!r}")
        return
    m = store.overlap(target, toks)
    print(f"  {m['tier']:<20} {query!r} -> {target}")
    print(f"      tokens      {toks}")
    print(f"      in title/id/tags  {m['head_toks'] or '(none)'}")
    print(f"      in body only      {m['body_toks'] or '(none)'}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("path", nargs="?", help="a questions.json-shaped file to classify in bulk")
    ap.add_argument("--query")
    ap.add_argument("--target")
    ap.add_argument("--fixture", default=str(HERE / "fixture-store"))
    args = ap.parse_args(argv)

    try:
        store = Store(Path(args.fixture) / "memory")
        stopwords = load_stopwords(ROOT / "bin" / "eve")
    except (OSError, RuntimeError) as exc:
        sys.stderr.write(f"classify: {exc}\n")
        return 2

    if args.query:
        try:
            show(store, stopwords, args.query, args.target)
        except KeyError:
            sys.stderr.write(f"classify: no memory {args.target!r} in {args.fixture}\n")
            return 2
        return 0

    if not args.path:
        ap.print_help()
        return 2

    try:
        data = json.loads(Path(args.path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"classify: {exc}\n")
        return 2
    items = data["queries"] if isinstance(data, dict) else data
    for q in items:
        try:
            show(store, stopwords, q["query"], q.get("target"))
        except KeyError as exc:
            sys.stderr.write(f"classify: {q.get('id', '?')}: {exc}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
