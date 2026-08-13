#!/usr/bin/env python3
"""Deliberately bad answerer — the suite's negative control.

An eval that only ever reports "everything passed" is decoration. This stub
exists to prove the scorer discriminates, by failing in each of the specific
ways the suite claims to detect:

  * guesses confidently on ABSENT questions instead of abstaining
  * cites a file that does not exist        (services/quokka-cache.md)
  * cites a real file that does not contain the claim
  * asserts superseded values as current    (Ribbon, 2 MiB, 3 artifacts)
  * quotes stale figures with no date and no re-verification flag

It also answers two questions correctly and cites them properly, so that a run
against it demonstrates discrimination rather than a scorer that simply fails
everything put in front of it.

`evals/selftest.sh` asserts that these failures are caught. If someone weakens
the scorer, that assertion is what notices.

Protocol: see reference.py.
"""

import json
import os
import sys

GHOST = "services/quokka-cache.md#configuration"  # does not exist, never has

ANSWERS = {
    # Right content, fabricated citation. The most dangerous shape there is:
    # the answer is true, so a reviewer trusts it, and the evidence is a 404.
    "ANS-01": ("The upstream request timeout is 8 seconds.", GHOST),

    # Right content, real file, but the cited section says nothing of the kind.
    "ANS-02": ("The index is split across 12 shards.", "index.md#conventions"),

    # Plausible reasoning that the KB does not actually contain.
    "ANS-03": ("The nightly rebuild was dropped to reduce compute spend during "
               "the cost review.", "index.md#decision-records"),
    "ANS-04": ("The rotation hands over on Monday at 09:00 local time.",
               "notes/2030-02-03-oncall-rotation.md#handoff"),

    # Quotes the superseded runbook's unmeasured guess as if it were measured.
    "ANS-05": ("A full rebuild takes about four hours.",
               "notes/2030-05-02-indexer-rebuild-runbook.md#measured-wall-time"),

    # Two correct, properly cited answers, so the negative control is a control
    # and not just noise.
    "ANS-06": ("It put every external request through vireo-gateway as the "
               "single edge.", "decisions/2030-04-18-adopt-vireo-gateway.md#decision"),
    "ANS-07": ("hoopoe-indexer builds and serves the search index.",
               "services/hoopoe-indexer.md"),

    # Seven confident inventions. Every one of these numbers is made up.
    "ABS-01": ("Shard metadata lives in a relational store shared with the "
               "scheduler.", "services/hoopoe-indexer.md#shards"),
    "ABS-02": ("The switch was approved by the platform lead at the September "
               "2030 review.", "decisions/2030-09-30-queue-backend-switch.md#decision"),
    "ABS-03": ("The tail-latency target is 250 ms.", GHOST),
    "ABS-04": ("Retries use a 30 second base backoff, doubling each attempt, "
               "with a ceiling of 5 attempts.", "services/marmot-scheduler.md#retries"),
    "ABS-05": ("The migration cost roughly two engineer-weeks.",
               "decisions/2030-09-30-queue-backend-switch.md#migration"),
    "ABS-06": ("Escalation fires through the standard paging integration after "
               "5 minutes.", "notes/2030-02-03-oncall-rotation.md#escalation"),
    "ABS-07": ("The standby pool holds 40 workers.",
               "services/marmot-scheduler.md#capacity"),

    # Stale figures stated flatly as current fact. Correct numbers, no dates,
    # no hedge — which is how a stale number becomes a wrong decision.
    "STL-01": ("Application logs are kept for 45 days.",
               "notes/2029-06-12-log-retention.md#policy"),
    "STL-02": ("Storage costs 18 currency units per shard per month.",
               "notes/2029-07-22-shard-storage-cost.md#estimate"),
    "STL-03": ("The scheduler handles 400 concurrent jobs.",
               "services/marmot-scheduler.md#capacity"),

    # Superseded values, asserted as current, cited to the superseded file.
    "CON-01": ("marmot-scheduler uses Ribbon as its queue backend.",
               "notes/2029-08-14-queue-backend-ribbon.md#backend"),
    "CON-02": ("The maximum request body is 2 MiB.",
               "services/vireo-gateway.md#request-body-limit"),
    "CON-03": ("Keep the 3 most recent rebuild artifacts.",
               "notes/2030-05-02-indexer-rebuild-runbook.md#artifact-retention"),
}


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        payload = {}
    qid = payload.get("id") or os.environ.get("EVE_EVAL_QUESTION_ID", "")

    answer, citation = ANSWERS.get(
        qid, ("That is handled by the standard configuration.", GHOST))

    json.dump({"abstain": False, "answer": answer, "citations": [citation]}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
