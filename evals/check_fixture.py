#!/usr/bin/env python3
"""Integrity check for the fixture KB and the question set.

The eval suite's scores are only meaningful if the fixture is internally
consistent. This script checks the things that silently rot when someone edits
a markdown file:

  * every expected citation resolves (path exists, anchor exists)
  * every expected citation actually contains its claim tokens
  * every non-ABSENT claim token appears somewhere in the KB at all
  * every ABSENT question has no claim tokens and no expected citations —
    if a trap question acquires an answer, it has stopped being a trap
  * every superseded value named in must_not_assert really is in the KB
    (otherwise the contradiction being tested does not exist)
  * the reference answer key covers every question, and no more
  * question ids are unique and categories are valid

Run it before trusting a scorecard. `selftest.sh` runs it first.

    python3 evals/check_fixture.py

Exit 0 if the fixture is sound, 1 if not.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from kb import KB, normalize  # noqa: E402
from scoring import CATEGORIES  # noqa: E402


def main():
    questions_path = os.path.join(HERE, "questions.json")
    with open(questions_path, "r", encoding="utf-8") as handle:
        data = json.load(handle)

    knowledge = KB(os.path.join(HERE, data.get("kb_root", "fixture-kb")))
    corpus = normalize("\n".join(text for _, text in knowledge.docs()))

    key_path = os.path.join(HERE, "answerers", "reference_answers.json")
    with open(key_path, "r", encoding="utf-8") as handle:
        answer_key = json.load(handle)

    problems = []
    seen = set()

    for q in data["questions"]:
        qid = q.get("id", "<missing id>")
        where = "question %s" % qid

        if qid in seen:
            problems.append("%s: duplicate id" % where)
        seen.add(qid)

        if q.get("category") not in CATEGORIES:
            problems.append("%s: unknown category %r" % (where, q.get("category")))

        claims = q.get("claim_tokens") or []
        cites = q.get("expected_citations") or []

        if q.get("category") == "ABSENT":
            if claims:
                problems.append("%s: ABSENT question has claim_tokens, so it is "
                                "answerable and no longer a trap" % where)
            if cites:
                problems.append("%s: ABSENT question has expected_citations" % where)
            if q.get("must_contain"):
                problems.append("%s: ABSENT question has must_contain" % where)
            continue

        if not claims:
            problems.append("%s: no claim_tokens, so citations cannot be checked" % where)
        for token in claims:
            if normalize(token) not in corpus:
                problems.append("%s: claim token %r appears nowhere in the KB"
                                % (where, token))

        if not cites:
            problems.append("%s: no expected_citations" % where)
        for cite in cites:
            check = knowledge.resolve_citation(cite, claims)
            if not check["resolved"]:
                problems.append("%s: expected citation %r does not resolve (%s)"
                                % (where, cite, check["reason"]))
            elif not check["supports"]:
                problems.append("%s: expected citation %r resolves but does not "
                                "contain any claim token (%s)"
                                % (where, cite, check["reason"]))

        forbidden = q.get("must_not_assert", [])
        if q["category"] == "CONTRADICTED":
            # must_not_assert holds spelling variants of one superseded value,
            # so only one of them has to literally appear. What must be true is
            # that the old value is still somewhere in the KB — otherwise there
            # is nothing for the agent to be misled by and the question is not
            # testing supersession at all.
            if not forbidden:
                problems.append("%s: CONTRADICTED question names no superseded "
                                "value in must_not_assert" % where)
            elif not any(normalize(f) in corpus for f in forbidden):
                problems.append("%s: none of must_not_assert %r appear in the KB, "
                                "so there is no contradiction to test"
                                % (where, forbidden))

        if q.get("category") == "STALE":
            if not q.get("source_date"):
                problems.append("%s: STALE question has no source_date" % where)
            if not q.get("require_as_of") or not q.get("require_stale_flag"):
                problems.append("%s: STALE question does not require a date and a "
                                "staleness flag" % where)

    key_ids = {k for k in answer_key if not k.startswith("_")}
    missing = sorted(seen - key_ids)
    extra = sorted(key_ids - seen)
    for qid in missing:
        problems.append("reference answer key has no entry for %s" % qid)
    for qid in extra:
        problems.append("reference answer key has an entry for unknown question %s" % qid)

    print("fixture: %s" % os.path.relpath(knowledge.root, os.getcwd()))
    print("documents: %d   questions: %d" % (len(knowledge.docs()), len(data["questions"])))
    if problems:
        print("\n%d problem(s):" % len(problems))
        for problem in problems:
            print("  - %s" % problem)
        return 1
    print("OK: every expected citation resolves and supports its claim; every trap "
          "question is still a trap.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
