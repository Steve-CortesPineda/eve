#!/usr/bin/env python3
"""Reference answerer — the behaviour the grounding doctrine asks for.

This is a FIXTURE, not a model. It looks its answers up in
`reference_answers.json` and prints them. It exists so that a contributor can
run the suite in two seconds with no API key and see a green baseline, and so
that CI can detect when a change to the scorer breaks the definition of a
correct answer.

It measures the harness. It does not measure anything about an AI system, and
the docs say so in as many words. Do not quote its scores as evidence of
anything except that the plumbing works.

Protocol (identical for a real agent):
  stdin   {"id": "...", "question": "...", "kb_root": "/abs/path/to/kb"}
  stdout  {"answer": "...", "abstain": false, "citations": ["path.md#anchor"],
           "as_of": "YYYY-MM-DD", "flags": ["stale"]}

The payload deliberately does not include the question's category or expected
answer, so this script cannot cheat in a way a real agent could not.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ANSWER_KEY = os.path.join(HERE, "reference_answers.json")


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        payload = {}
    qid = payload.get("id") or os.environ.get("EVE_EVAL_QUESTION_ID", "")

    try:
        with open(ANSWER_KEY, "r", encoding="utf-8") as handle:
            answers = json.load(handle)
    except (OSError, ValueError) as exc:
        sys.stderr.write("reference answerer: cannot read answer key: %s\n" % exc)
        answers = {}

    entry = answers.get(qid)
    if entry is None:
        # Unknown question. The honest response is to decline, not to improvise.
        entry = {
            "abstain": True,
            "answer": "No entry for %s in the reference answer key." % (qid or "?"),
            "citations": [],
        }

    json.dump(entry, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
