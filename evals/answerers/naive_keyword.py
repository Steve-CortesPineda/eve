#!/usr/bin/env python3
"""Naive keyword answerer — a real retriever with no abstention discipline.

This is the pedagogically important stub. It is not broken and it is not lying.
It does honest tf-idf-ish retrieval over the fixture KB, picks the best-matching
section, quotes the best-matching sentence, and cites where it came from. On
questions the KB answers, it does reasonably well.

Then it answers the ABSENT questions too, because it has no way not to. Every
question retrieves *something* — cosine similarity is never undefined — and a
system whose only output mode is "here is the closest passage" cannot say "the
closest passage is not an answer."

That is the entire argument for the grounding layer, expressed as a program. Run
`python3 evals/run.py --answerer naive -v` and read the ABSENT rows.

Protocol: see reference.py.
"""

import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from kb import KB, slugify  # noqa: E402

STOPWORDS = set("""
a an the is are was were be been being am what which who whom whose when where why how
do does did done of for to in on at by with from into over under and or but not no nor
it its it's this that these those there here as if then than so such can could should
would will shall may might must have has had i you he she we they me him her us them my
your our their much many long does much any all some each every other another
""".split())

SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
FRONTMATTER = re.compile(r"\A---\r?\n.*?\r?\n---[ \t]*\r?\n", re.DOTALL)
HEADING = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$")


def terms(text):
    return [t for t in re.findall(r"[a-z0-9][a-z0-9-]*", text.lower())
            if t not in STOPWORDS and len(t) > 1]


def clean(text):
    """Strip frontmatter and blockquote lines (the fixture's fiction banner)."""
    body = FRONTMATTER.sub("", text)
    return "\n".join(l for l in body.splitlines() if not l.lstrip().startswith(">"))


def sections(relpath, text):
    """[(anchor|None, heading|None, body)] — a preamble plus one per heading."""
    lines = clean(text).splitlines()
    out = []
    current_head = None
    current_anchor = None
    buffer = []
    for line in lines:
        match = HEADING.match(line)
        if match:
            if buffer:
                out.append((current_anchor, current_head, "\n".join(buffer)))
            current_head = match.group(2)
            current_anchor = slugify(current_head)
            buffer = [line]
        else:
            buffer.append(line)
    if buffer:
        out.append((current_anchor, current_head, "\n".join(buffer)))
    return out


def score(query_terms, text, idf):
    counts = {}
    for t in terms(text):
        counts[t] = counts.get(t, 0) + 1
    if not counts:
        return 0.0
    length = math.sqrt(sum(counts.values()))
    return sum(counts.get(q, 0) * idf.get(q, 1.0) for q in query_terms) / length


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        payload = {}
    question = payload.get("question", "")
    root = payload.get("kb_root") or os.environ.get("EVE_EVAL_KB", "")

    try:
        knowledge = KB(root)
    except (FileNotFoundError, TypeError) as exc:
        sys.stderr.write("naive answerer: %s\n" % exc)
        json.dump({"abstain": True, "answer": "KB unavailable.", "citations": []}, sys.stdout)
        return 1

    docs = knowledge.docs()
    query = terms(question)

    # idf over the corpus, so "gateway" counts for more than "index".
    n_docs = max(1, len(docs))
    doc_freq = {}
    for _, text in docs:
        for t in set(terms(text)):
            doc_freq[t] = doc_freq.get(t, 0) + 1
    idf = {t: math.log((n_docs + 1.0) / (doc_freq.get(t, 0) + 1.0)) + 1.0 for t in query}

    best = (0.0, None, None, None)  # score, path, anchor, body
    for relpath, text in docs:
        for anchor, _head, body in sections(relpath, text):
            value = score(query, body, idf)
            if value > best[0]:
                best = (value, relpath, anchor, body)

    if best[1] is None:
        # Note that this is the ONLY circumstance in which this answerer
        # declines: when retrieval returns literally nothing. "Nothing matched"
        # is a much weaker condition than "the KB does not contain the answer",
        # and it is the whole gap this eval measures.
        json.dump({"abstain": True, "answer": "No matching passage.", "citations": []}, sys.stdout)
        sys.stdout.write("\n")
        return 0

    _, path, anchor, body = best
    candidates = [s.strip() for s in SENTENCE_SPLIT.split(body) if len(s.strip()) > 20]
    sentence = max(candidates, key=lambda s: score(query, s, idf)) if candidates else body.strip()
    sentence = re.sub(r"\s+", " ", sentence.lstrip("# ")).strip()

    citation = path + ("#" + anchor if anchor else "")
    json.dump({"abstain": False, "answer": sentence, "citations": [citation]}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
