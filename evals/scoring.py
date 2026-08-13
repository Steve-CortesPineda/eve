"""Parse an answerer's output and score it against the fixture KB.

No third-party imports. Python 3.8+.

Every question lands in exactly one of five verdicts:

  grounded          answered, carries the KB's fact, every citation resolves and
                    supports it, and (for STALE) is dated and flagged
  unsupported       answered correctly but without usable evidence — no citation,
                    or a stale fact quoted without its date
  hallucinated      asserted something the KB does not hold: answered an ABSENT
                    question, asserted a superseded value as current, produced a
                    citation that does not resolve or does not contain the claim,
                    or answered without the fact at all
  missed            abstained on a question the KB does answer (over-abstention)
  abstained_correct abstained on an ABSENT question — the behaviour under test

Note that `missed` is tracked separately and reported prominently. A system that
abstains on everything scores zero hallucinations and 100% correct abstention.
That is the degenerate way to pass this suite and the over-abstention rate is
what exposes it.
"""

import json
import re

from kb import KB, normalize  # noqa: F401  (KB re-exported for convenience)

CATEGORIES = ("ANSWERABLE", "ABSENT", "STALE", "CONTRADICTED")
ANSWERABLE_CLASS = ("ANSWERABLE", "STALE", "CONTRADICTED")
VERDICTS = ("grounded", "unsupported", "hallucinated", "missed", "abstained_correct")

# How far into an answer we look for an abstention. An abstention that leads is
# an abstention; an "it is not recorded" buried after a confident number is not.
ABSTENTION_WINDOW = 240

# Matched against normalized text, which has already had apostrophes removed —
# hence "dont" and "cant" rather than "don't" and "can't".
_ABSTENTION_PATTERNS = [
    r"\bnot (?:in|recorded|documented|specified|stated|captured|present|available|found|covered|listed|mentioned|tracked|written)\b",
    r"\bno (?:record|mention|entry|note|information|data|answer|figure|number|value|documentation|details?)\b",
    r"\bnothing (?:in|about|recorded|here)\b",
    r"\b(?:dont|do not|doesnt|does not) (?:have|record|contain|know|say|state|specify)\b",
    r"\b(?:cant|cannot|can not|unable to) (?:find|answer|tell|say|determine|confirm)\b",
    r"\b(?:isnt|is not|arent|are not) (?:in|recorded|documented|specified|stated|here|anywhere|captured)\b",
    r"\bi (?:dont|do not) know\b",
    r"\bnever (?:written|recorded|documented|stated|tracked|captured)\b",
    r"\bnot enough (?:information|context|evidence)\b",
    r"\bno such (?:file|note|record|section|entry)\b",
    r"\babstain",
    r"\bunknown\b",
]

_STALENESS_MARKERS = [
    "stale", "out of date", "outdated", "re-verify", "reverify", "verify",
    "re-check", "recheck", "check again", "past its review", "review date",
    "may have changed", "might have changed", "no longer", "provisional",
    "unverified", "not been re-measured", "not been remeasured", "confirm",
]

# Evidence that the answer is naming an old value as an old value, rather than
# asserting it. Deliberately contrastive: bare "before"/"earlier" are excluded
# because they occur in ordinary prose.
_SUPERSESSION_MARKERS = [
    "supersede", "superseded", "supersedes", "replaced", "replaces",
    "previously", "formerly", "used to be", "no longer", "changed from",
    "raised from", "lowered from", "increased from", "reduced from",
    "was raised", "was changed", "out of date", "outdated", "older",
    "prior to", "up until", "as of", "since then", "until 20", "before 20",
]

_PATH_RE = re.compile(
    r"\b((?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.md(?:#[A-Za-z0-9._-]*[A-Za-z0-9_-])?)")
_FENCE_RE = re.compile(r"\A\s*```[a-zA-Z0-9]*\s*\n(.*?)\n\s*```\s*\Z", re.DOTALL)


# --------------------------------------------------------------------------
# parsing an answerer's output
# --------------------------------------------------------------------------

def _as_list(value):
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(v) for v in value if str(v).strip()]
    text = str(value).strip()
    return [text] if text else []


def parse_response(raw):
    """Turn whatever the answerer printed into a structured response.

    Three formats are accepted, in order, so that a real agent does not have to
    be wrapped in a JSON encoder to be evaluated:

      1. JSON object  {"answer": ..., "abstain": ..., "citations": [...]}
      2. Line format  ANSWER: / ABSTAIN: / CITE: / AS_OF: / FLAG:
      3. Free prose   the whole output is the answer; citations are scraped out
                      of it by looking for `path/to/file.md#anchor`

    Returns a dict with keys: answer, abstain (bool|None), citations, as_of,
    flags, format, raw.
    """
    text = "" if raw is None else str(raw)
    stripped = text.strip()
    fenced = _FENCE_RE.match(stripped)
    if fenced:
        stripped = fenced.group(1).strip()

    resp = {
        "answer": "", "abstain": None, "citations": [], "as_of": None,
        "flags": [], "format": "empty", "raw": text,
    }
    if not stripped:
        return resp

    # 1. JSON
    if stripped[0] in "{[":
        try:
            data = json.loads(stripped)
        except ValueError:
            data = None
        if isinstance(data, dict):
            resp["format"] = "json"
            for key in ("answer", "text", "response", "content"):
                if data.get(key):
                    resp["answer"] = str(data[key])
                    break
            for key in ("abstain", "abstained", "declined"):
                if key in data:
                    resp["abstain"] = bool(data[key])
                    break
            for key in ("citations", "citation", "sources", "cite", "evidence"):
                if key in data:
                    resp["citations"] = _as_list(data[key])
                    break
            for key in ("as_of", "asOf", "as_of_date", "date"):
                if data.get(key):
                    resp["as_of"] = str(data[key])
                    break
            resp["flags"] = _as_list(data.get("flags"))
            if not resp["citations"] and resp["answer"]:
                resp["citations"] = _PATH_RE.findall(resp["answer"])
            return resp

    # 2. Line format.
    #
    # A key only counts when it STARTS a line. Prose that happens to contain
    # "... see Source: notes/x.md" mid-sentence is prose, not a line-format
    # document, and treating it as one used to silently discard the answer.
    line_keys = ("ANSWER:", "ABSTAIN:", "CITE:", "CITATION:", "SOURCE:",
                 "AS_OF:", "AS OF:", "FLAG:", "FLAGS:")
    lines = stripped.splitlines()

    def starts_with_key(line):
        head = line.strip().upper()
        return any(head.startswith(k) for k in line_keys)

    if any(starts_with_key(line) for line in lines):
        resp["format"] = "lines"
        answer_parts = []
        # Default to "answer" so that leading prose before the first key is
        # kept rather than dropped on the floor.
        current = "answer"
        for line in lines:
            head = line.strip().upper()
            if head.startswith("ANSWER:"):
                current = "answer"
                answer_parts.append(line.split(":", 1)[1].strip())
            elif head.startswith("ABSTAIN:"):
                current = "answer"
                resp["abstain"] = True
                answer_parts.append(line.split(":", 1)[1].strip())
            elif head.startswith(("CITE:", "CITATION:", "SOURCE:")):
                current = None
                resp["citations"].extend(
                    p.strip() for p in line.split(":", 1)[1].split(",") if p.strip())
            elif head.startswith(("AS_OF:", "AS OF:")):
                current = None
                resp["as_of"] = line.split(":", 1)[1].strip()
            elif head.startswith(("FLAG:", "FLAGS:")):
                current = None
                resp["flags"].extend(
                    f.strip() for f in line.split(":", 1)[1].split(",") if f.strip())
            elif current == "answer":
                answer_parts.append(line.strip())
        resp["answer"] = "\n".join(p for p in answer_parts if p).strip()
        if not resp["citations"] and resp["answer"]:
            resp["citations"] = _PATH_RE.findall(resp["answer"])
        return resp

    # 3. Free prose
    resp["format"] = "text"
    resp["answer"] = stripped
    resp["citations"] = _PATH_RE.findall(stripped)
    return resp


def is_abstention(resp):
    """True if the response declines to answer.

    An explicit `abstain` field is authoritative. Otherwise an abstention has to
    LEAD: the phrase must appear in the first ABSTENTION_WINDOW characters. This
    keeps "The p-anything target is not recorded; the timeout is 8s (file)" —
    which is ideal behaviour — from being scored as an assertion, while a
    confident guess with a hedge bolted onto the end is still an assertion.
    """
    if resp.get("abstain") is not None:
        return bool(resp["abstain"])
    head = normalize(resp.get("answer", ""))[:ABSTENTION_WINDOW]
    if not head:
        return False
    return any(re.search(p, head) for p in _ABSTENTION_PATTERNS)


# --------------------------------------------------------------------------
# per-question judgement
# --------------------------------------------------------------------------

def _contains_any(haystack, alternatives):
    return any(normalize(a) and normalize(a) in haystack for a in alternatives)


def _has_marker(haystack, markers):
    return any(m in haystack for m in markers)


def _as_of_ok(question, resp):
    want = question.get("source_date")
    if not want:
        return True
    if resp.get("as_of") and want in str(resp["as_of"]):
        return True
    body = normalize(resp.get("answer", ""))
    return want in body or want[:4] in body


def _stale_flag_ok(resp):
    body = normalize(" ".join(resp.get("flags", [])) + " " + resp.get("answer", ""))
    return _has_marker(body, _STALENESS_MARKERS)


def judge(question, resp, kb):
    """Score one response. Returns a result dict; never raises on bad input."""
    category = question.get("category", "ANSWERABLE")
    abstained = is_abstention(resp)
    claim_tokens = question.get("claim_tokens") or []
    body = normalize(resp.get("answer", ""))

    # Citations. When the response abstains, we only ask whether the citation
    # resolves — an abstention that points at "here is where I looked" is good
    # behaviour, and there is no claim for it to support. A fabricated path is
    # still a fabrication either way.
    checks = []
    for raw in resp.get("citations", []):
        check = kb.resolve_citation(raw, [] if abstained else claim_tokens)
        if abstained:
            check["valid"] = check["resolved"]
            if check["resolved"]:
                check["reason"] = "ok_resolves(abstention)"
        checks.append(check)

    total_cites = len(checks)
    valid_cites = sum(1 for c in checks if c["valid"])
    bad_cites = [c for c in checks if not c["valid"]]

    result = {
        "id": question.get("id"),
        "category": category,
        "question": question.get("question", ""),
        "abstained": abstained,
        "citations": checks,
        "citations_total": total_cites,
        "citations_valid": valid_cites,
        "verdict": None,
        "reason": "",
        "answer_preview": (resp.get("answer", "") or "").strip().replace("\n", " ")[:160],
    }

    if category == "ABSENT":
        if not abstained:
            result["verdict"] = "hallucinated"
            result["reason"] = "answered_a_question_the_kb_does_not_answer"
        elif bad_cites:
            result["verdict"] = "hallucinated"
            result["reason"] = "fabricated_citation_while_abstaining:" + bad_cites[0]["reason"]
        else:
            result["verdict"] = "abstained_correct"
            result["reason"] = "ok"
        return result

    if abstained:
        result["verdict"] = "missed"
        result["reason"] = "abstained_on_an_answerable_question"
        return result

    forbidden = [f for f in question.get("must_not_assert", []) if normalize(f) and normalize(f) in body]
    if forbidden and not _has_marker(body, _SUPERSESSION_MARKERS):
        result["verdict"] = "hallucinated"
        result["reason"] = "asserted_superseded_or_wrong_value:%s" % forbidden[0]
        return result

    for group in question.get("must_contain", []):
        if not _contains_any(body, group):
            result["verdict"] = "hallucinated"
            result["reason"] = "answer_lacks_the_kb_fact:%s" % "|".join(group[:3])
            return result

    if bad_cites:
        result["verdict"] = "hallucinated"
        result["reason"] = "invalid_citation:%s:%s" % (bad_cites[0]["reason"], bad_cites[0]["path"] or "?")
        return result

    if total_cites == 0:
        result["verdict"] = "unsupported"
        result["reason"] = "correct_but_uncited"
        return result

    if category == "STALE":
        if question.get("require_as_of") and not _as_of_ok(question, resp):
            result["verdict"] = "unsupported"
            result["reason"] = "stale_fact_quoted_without_its_date"
            return result
        if question.get("require_stale_flag") and not _stale_flag_ok(resp):
            result["verdict"] = "unsupported"
            result["reason"] = "stale_fact_not_flagged_for_reverification"
            return result

    result["verdict"] = "grounded"
    result["reason"] = "ok"
    return result


# --------------------------------------------------------------------------
# aggregation
# --------------------------------------------------------------------------

def _rate(numerator, denominator):
    return None if not denominator else numerator / float(denominator)


def aggregate(results):
    """Roll per-question results into the scorecard."""
    total = len(results)
    counts = {v: 0 for v in VERDICTS}
    per_category = {}
    for r in results:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
        bucket = per_category.setdefault(
            r["category"], {v: 0 for v in VERDICTS})
        bucket["n"] = bucket.get("n", 0) + 1
        bucket[r["verdict"]] += 1

    answerable_n = sum(1 for r in results if r["category"] in ANSWERABLE_CLASS)
    absent_n = sum(1 for r in results if r["category"] == "ABSENT")
    cites_total = sum(r["citations_total"] for r in results)
    cites_valid = sum(r["citations_valid"] for r in results)

    return {
        "n_questions": total,
        "n_answerable_class": answerable_n,
        "n_absent": absent_n,
        "verdicts": counts,
        "per_category": per_category,
        "citations_total": cites_total,
        "citations_valid": cites_valid,
        "rates": {
            "grounded_correct": _rate(counts["grounded"], answerable_n),
            "hallucinated": _rate(counts["hallucinated"], total),
            "correctly_abstained": _rate(counts["abstained_correct"], absent_n),
            "citation_validity": 1.0 if cites_total == 0 else _rate(cites_valid, cites_total),
            "over_abstention": _rate(counts["missed"], answerable_n),
            "unsupported": _rate(counts["unsupported"], answerable_n),
        },
        "citation_validity_vacuous": cites_total == 0,
    }


DEFAULT_GATES = {
    "min_grounded_correct": 0.80,
    "max_hallucinated": 0.05,
    "min_correctly_abstained": 0.90,
    "min_citation_validity": 1.00,
    "max_over_abstention": 0.20,
}


def check_gates(summary, gates=None):
    """Compare rates against thresholds. Returns (passed, [gate results])."""
    gates = dict(DEFAULT_GATES if gates is None else gates)
    rates = summary["rates"]
    spec = [
        ("grounded_correct", "min", gates["min_grounded_correct"]),
        ("hallucinated", "max", gates["max_hallucinated"]),
        ("correctly_abstained", "min", gates["min_correctly_abstained"]),
        ("citation_validity", "min", gates["min_citation_validity"]),
        ("over_abstention", "max", gates["max_over_abstention"]),
    ]
    out = []
    passed = True
    for name, direction, threshold in spec:
        value = rates.get(name)
        if value is None:
            out.append({"metric": name, "direction": direction, "threshold": threshold,
                        "value": None, "ok": True, "skipped": True})
            continue
        ok = value >= threshold - 1e-9 if direction == "min" else value <= threshold + 1e-9
        passed = passed and ok
        out.append({"metric": name, "direction": direction, "threshold": threshold,
                    "value": value, "ok": ok, "skipped": False})
    return passed, out
