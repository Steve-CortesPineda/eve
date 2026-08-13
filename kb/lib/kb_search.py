"""kb search -- ranked, cited retrieval over the knowledge base.

Every result is a passage, and every passage carries the file path and the
line number where it starts. That is not a display detail: the grounding
doctrine (docs/03) says a claim the agent cannot cite is a claim it should not
make, which only works if retrieval hands back an anchor by construction. So
the unit of retrieval here is `(path, line, text)`, never bare text.

Ranking is BM25 over passages with three adjustments that matter for a
knowledge base but not for a general search engine:

  * field weighting -- title, tags and the enclosing heading are indexed into
    the passage bag at higher weight, so "the note about X" beats "a note that
    mentions X once".
  * freshness decay -- a passage from a doc last verified two years ago loses
    score against an equivalent passage verified last month. Floored, never
    zeroed: stale is not the same as wrong.
  * supersession -- documents marked superseded are excluded by default. The
    replacement is what you want; the old one is history.

No index file is written. The KB is scanned per query. That is a deliberate
trade: correctness and zero moving parts up to roughly ten thousand documents,
which is far past the point where a human-curated KB stops being human.
"""

import argparse
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kbcommon as kb  # noqa: E402

MAX_PASSAGE_CHARS = 900
MIN_PASSAGE_CHARS = 60

TITLE_WEIGHT = 3
TAG_WEIGHT = 3
HEADING_WEIGHT = 2
PATH_WEIGHT = 2

K1 = 1.5
B = 0.75

CONFIDENCE_MULT = {"high": 1.0, "medium": 0.88, "low": 0.72}
DEFAULT_CONFIDENCE_MULT = 0.88

STALENESS_HALF_LIFE_DAYS = 365.0
STALENESS_FLOOR = 0.40
SUPERSEDED_MULT = 0.25
PHRASE_BONUS = 1.5

_HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
_FENCE_RE = re.compile(r"^\s*(```|~~~)")


class Passage(object):
    __slots__ = ("doc", "line", "heading", "text", "tokens", "length", "norm")

    def __init__(self, doc, line, heading, text):
        self.doc = doc
        self.line = line
        self.heading = heading
        self.text = text
        self.norm = re.sub(r"\s+", " ", text.lower())
        self.tokens = None
        self.length = 0


def split_passages(doc):
    """Chunk a document body into passages, tracking the true file line number.

    Splits on blank lines and headings, then merges neighbours until a chunk is
    substantial enough to be worth returning on its own. Fenced code blocks are
    never split, so a retrieved snippet is always runnable as shown.
    """
    lines = doc.body.split("\n")
    passages = []
    heading = doc.title
    buf = []
    buf_line = None
    in_fence = False

    def flush():
        nonlocal buf, buf_line
        if not buf:
            return
        text = "\n".join(buf).strip("\n")
        if text.strip():
            passages.append(Passage(doc, buf_line, heading, text))
        buf = []
        buf_line = None

    for offset, raw in enumerate(lines):
        file_line = doc.body_start_line + offset

        if _FENCE_RE.match(raw):
            in_fence = not in_fence
            if buf_line is None:
                buf_line = file_line
            buf.append(raw)
            continue

        if in_fence:
            if buf_line is None:
                buf_line = file_line
            buf.append(raw)
            continue

        match = _HEADING_RE.match(raw)
        if match:
            flush()
            heading = match.group(2).strip()
            buf_line = file_line
            buf.append(raw)
            continue

        if not raw.strip():
            current = "\n".join(buf)
            if len(current) >= MIN_PASSAGE_CHARS:
                flush()
            elif buf:
                buf.append(raw)
            continue

        if buf_line is None:
            buf_line = file_line
        buf.append(raw)

        if len("\n".join(buf)) >= MAX_PASSAGE_CHARS:
            flush()

    flush()
    return [p for p in passages if len(p.text.strip()) >= 12]


def index_passage(passage):
    doc = passage.doc
    tokens = kb.tokenize(passage.text)
    tokens += kb.tokenize(doc.title) * TITLE_WEIGHT
    tokens += kb.tokenize(passage.heading) * HEADING_WEIGHT
    for tag in doc.tags:
        tokens += kb.tokenize(tag) * TAG_WEIGHT
    tokens += kb.tokenize(doc.rel.replace(os.sep, " ")) * PATH_WEIGHT
    passage.tokens = tokens
    passage.length = len(tokens)


def staleness_multiplier(doc):
    age = kb.age_days(doc.freshness_date)
    if age is None:
        return STALENESS_FLOOR + (1.0 - STALENESS_FLOOR) * 0.5
    decay = 0.5 ** (age / STALENESS_HALF_LIFE_DAYS)
    return max(STALENESS_FLOOR, decay)


def quality_multiplier(doc):
    confidence = str(doc.fm.get("confidence") or "").strip().lower()
    mult = CONFIDENCE_MULT.get(confidence, DEFAULT_CONFIDENCE_MULT)
    mult *= staleness_multiplier(doc)
    if doc.status == "superseded":
        mult *= SUPERSEDED_MULT
    if doc.status == "draft":
        mult *= 0.8
    return mult


def diversify(results, limit, per_doc):
    """Cap passages per document, then backfill.

    Without this, one well-titled document takes every slot: its title and tags
    boost each of its passages equally, so a doc that matches at all tends to
    match everywhere. The agent then reads five paragraphs of one note and
    never sees the note that actually answers the question. Cap first, backfill
    from the leftovers only if there is room.
    """
    if per_doc <= 0:
        return results[:limit]
    kept, spill, seen = [], [], {}
    for item in results:
        rel = item[1].doc.rel
        if seen.get(rel, 0) < per_doc:
            seen[rel] = seen.get(rel, 0) + 1
            kept.append(item)
        else:
            spill.append(item)
    if len(kept) < limit:
        kept.extend(spill[: limit - len(kept)])
        kept.sort(key=lambda item: (-item[0], item[1].doc.rel, item[1].line))
    return kept[:limit]


VARIANT_PREFIX = 5
VARIANT_WEIGHT = 0.6


def expand_query(query_tokens, vocabulary):
    """Map each query term to the index terms it should match, with weights.

    The stemmer in kbcommon only strips plurals, on purpose -- aggressive
    stemming produces matches nobody can explain. But that leaves real gaps:
    "invalidation" does not match "invalidates", and a reader searching for one
    means the other. So each query term also matches vocabulary terms sharing a
    five-character prefix, at reduced weight. Five is long enough that
    "content" and "context" stay apart (they share four) while "deploy" still
    reaches "deployment".

    Returns (term -> weight, term -> originating query term).
    """
    weights, concept = {}, {}
    for token in query_tokens:
        weights[token] = 1.0
        concept[token] = token
    for token in query_tokens:
        if len(token) < VARIANT_PREFIX:
            continue
        prefix = token[:VARIANT_PREFIX]
        for term in vocabulary:
            if term in weights or len(term) < VARIANT_PREFIX:
                continue
            if term[:VARIANT_PREFIX] != prefix:
                continue
            shared = os.path.commonprefix([term, token])
            if len(shared) >= VARIANT_PREFIX:
                weights[term] = VARIANT_WEIGHT
                concept[term] = token
    return weights, concept


def search(root, query, limit=8, kinds=None, tags=None,
           include_superseded=False, min_score=0.0, per_doc=2):
    query_tokens = kb.tokenize(query)
    if not query_tokens:
        raise kb.KBError("query has no searchable terms (stopwords only?)")
    phrase = re.sub(r"\s+", " ", query.lower()).strip()

    passages = []
    for doc in kb.iter_docs(root, dirs=kinds):
        if doc.status == "superseded" and not include_superseded:
            continue
        if tags:
            have = set(t.lower() for t in doc.tags)
            if not have.intersection(t.lower() for t in tags):
                continue
        for passage in split_passages(doc):
            index_passage(passage)
            passages.append(passage)

    if not passages:
        return [], set()

    doc_freq = {}
    for passage in passages:
        for token in set(passage.tokens):
            doc_freq[token] = doc_freq.get(token, 0) + 1

    total = len(passages)
    avg_len = sum(p.length for p in passages) / float(total)

    term_weight, concept = expand_query(query_tokens, doc_freq)

    idf = {}
    for token in term_weight:
        n = doc_freq.get(token, 0)
        idf[token] = math.log(1.0 + (total - n + 0.5) / (n + 0.5))

    results = []
    for passage in passages:
        counts = {}
        for token in passage.tokens:
            if token in idf:
                counts[token] = counts.get(token, 0) + 1
        if not counts:
            continue

        score = 0.0
        for token, freq in counts.items():
            denom = freq + K1 * (1 - B + B * passage.length / avg_len)
            score += term_weight[token] * idf[token] * (freq * (K1 + 1)) / denom

        # Count distinct query *concepts* hit, not distinct index terms, so a
        # passage does not look broader just because it inflects a word twice.
        matched = len(set(concept[t] for t in counts))
        score *= 1.0 + 0.15 * (matched - 1)

        if len(query_tokens) > 1 and phrase in passage.norm:
            score *= PHRASE_BONUS

        score *= quality_multiplier(passage.doc)

        if score > min_score:
            results.append((score, passage, matched))

    results.sort(key=lambda item: (-item[0], item[1].doc.rel, item[1].line))
    return diversify(results, limit, per_doc), set(term_weight)


def best_excerpt(passage, query_tokens, max_chars=300):
    """Pick the most on-topic window inside a passage, and its line offset."""
    lines = passage.text.split("\n")
    wanted = set(query_tokens)
    best_i, best_hits = 0, -1
    for i in range(len(lines)):
        window = " ".join(lines[i : i + 3])
        hits = sum(1 for token in kb.tokenize(window) if token in wanted)
        if hits > best_hits:
            best_hits, best_i = hits, i
    # Advance past leading blanks and headings: they get stripped from the
    # excerpt, and an anchor must point at the line the quoted words are
    # actually on. A citation that is two lines off is a citation the reader
    # has to double-check, which defeats the point of having one.
    window = lines[best_i : best_i + 3]
    while len(window) > 1 and (not window[0].strip() or _HEADING_RE.match(window[0])):
        best_i += 1
        window = lines[best_i : best_i + 3]

    text = " ".join(window).strip()
    if not text:
        text = passage.text.strip()
        best_i = 0
    text = re.sub(r"^#{1,6}\s*", "", text)
    # A passage whose only content is its heading still needs the heading gone
    # from the excerpt, since the heading is displayed separately.
    heading = passage.heading.strip()
    if heading and text.startswith(heading) and len(text) > len(heading) + 4:
        text = text[len(heading) :].lstrip(" -–—:")
    return kb.squeeze(text, max_chars), best_i


def result_record(score, passage, matched, query_tokens):
    doc = passage.doc
    excerpt, offset = best_excerpt(passage, query_tokens)
    return {
        "score": round(score, 3),
        "path": kb.display_path(doc.path),
        "abs_path": doc.path,
        "line": passage.line + offset,
        "passage_line": passage.line,
        "citation": "%s:%d" % (kb.display_path(doc.path), passage.line + offset),
        "id": doc.doc_id,
        "title": doc.title,
        "heading": passage.heading,
        "type": doc.kind,
        "status": doc.status,
        "tags": doc.tags,
        "source": doc.fm.get("source", ""),
        "verified_on": doc.fm.get("verified_on", ""),
        "confidence": doc.fm.get("confidence", ""),
        "terms_matched": matched,
        "excerpt": excerpt,
    }


def render_text(records, query, root):
    if not records:
        return 'kb search: no passages matched "%s" in %s\n' % (query, kb.display_path(root))
    out = []
    docs = len(set(r["path"] for r in records))
    out.append(
        'kb search "%s" -- %d passage%s from %d document%s in %s'
        % (query, len(records), "" if len(records) == 1 else "s",
           docs, "" if docs == 1 else "s", kb.display_path(root))
    )
    out.append("")
    for i, r in enumerate(records, 1):
        meta = [r["type"]]
        if r["verified_on"]:
            meta.append("verified " + r["verified_on"])
        if r["confidence"]:
            meta.append("confidence " + r["confidence"])
        if r["status"] != "current":
            meta.append("STATUS " + r["status"].upper())
        if r["tags"]:
            meta.append("tags " + ", ".join(r["tags"]))
        out.append("%d. %s   score %.2f" % (i, r["citation"], r["score"]))
        where = r["title"]
        if r["heading"] and r["heading"].strip() != r["title"].strip():
            where += "  >  " + r["heading"]
        out.append("   %s" % where)
        out.append("   [%s]" % (" | ".join(meta)))
        out.append("   %s" % r["excerpt"])
        out.append("")
    return "\n".join(out) + "\n"


def render_cite(records):
    lines = []
    for r in records:
        lines.append('%s — "%s"' % (r["citation"], kb.squeeze(r["excerpt"], 160)))
    return "\n".join(lines) + ("\n" if lines else "")


def render_ground(records):
    """The citation shape the grounding doctrine (docs/08) asks answers to use.

    A citation proves provenance, not truth, so the age of the claim travels
    with it. An agent quoting this can say "verified 217 days ago" without
    doing any arithmetic of its own -- and arithmetic it does not do is
    arithmetic it cannot get wrong.
    """
    lines = []
    for r in records:
        bits = [r["citation"]]
        if r["verified_on"]:
            age = kb.age_days(r["verified_on"])
            bits.append("verified_on %s%s"
                        % (r["verified_on"],
                           " — %d days old" % age if age is not None else ""))
        if r["confidence"]:
            bits.append("confidence %s" % r["confidence"])
        if r["status"] != "current":
            bits.append("status %s" % r["status"])
        lines.append("[%s]" % ", ".join(bits))
        lines.append("> %s" % r["excerpt"])
        lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="kb search",
        description="Ranked, cited search over the Eve knowledge base.",
    )
    parser.add_argument("query", nargs="+", help="search terms")
    parser.add_argument("--root", help="knowledge-base root (default: $EVE_KB_ROOT or kb/)")
    parser.add_argument("-n", "--limit", type=int, default=8, help="max passages (default 8)")
    parser.add_argument("--type", dest="kinds", action="append",
                        choices=list(kb.KNOWN_DIRS),
                        help="restrict to a knowledge directory (repeatable)")
    parser.add_argument("--tag", dest="tags", action="append", help="require a tag (repeatable)")
    parser.add_argument("--per-doc", type=int, default=2,
                        help="max passages from any one document (0 = no cap, default 2)")
    parser.add_argument("--include-superseded", action="store_true",
                        help="also search documents marked superseded")
    parser.add_argument("--format", choices=("text", "json", "cite", "ground"),
                        default="text",
                        help="text (default), json, cite (one line each), "
                             "ground (docs/08 citation shape with claim age)")
    args = parser.parse_args(argv)

    root = kb.resolve_root(args.root)
    query = " ".join(args.query)

    try:
        hits, terms = search(root, query, limit=args.limit, kinds=args.kinds,
                             tags=args.tags, per_doc=args.per_doc,
                             include_superseded=args.include_superseded)
    except kb.KBError as exc:
        kb.die(str(exc))

    records = [result_record(s, p, m, terms) for s, p, m in hits]

    if args.format == "json":
        sys.stdout.write(json.dumps(
            {"query": query, "root": root, "results": records}, indent=2) + "\n")
    elif args.format == "cite":
        sys.stdout.write(render_cite(records))
    elif args.format == "ground":
        sys.stdout.write(render_ground(records))
    else:
        sys.stdout.write(render_text(records, query, root))

    return 0 if records else 1


if __name__ == "__main__":
    raise SystemExit(main())
