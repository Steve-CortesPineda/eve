"""kb consolidate -- propose which KB facts deserve promotion to atomic memory.

Consolidation is the ritual that decides what stays in the deep store and what
graduates into the handful of always-present memories. Without it a knowledge
base becomes a landfill: everything is written, nothing is ranked, and the
agent's behaviour never changes no matter how much it "knows".

It proposes. It never promotes. Writing to memory/ is a human action, because
an atomic memory is a standing instruction that will shape every future session
-- that is exactly the kind of change that should require a person to say yes.
The output is a reviewable markdown file with citations; approving means moving
a line into memory/ yourself.

Three signals, deliberately dumb and deterministic (no model call required):

  marked      an explicit `RULE:` / `FACT:` / `GOTCHA:` / `CONSTRAINT:` /
              `PREF:` / `DECISION:` marker, or a line under a "Durable" /
              "Learnings" / "Takeaways" heading. The writer already said this
              was durable.
  recurrence  the same claim, normalized, showing up in several documents.
              Repetition across sessions is the strongest available proxy for
              "this keeps mattering".
  gating      short sentences in behaviour-gating language -- always, never,
              must, prefer, avoid, don't. Atomic memory exists to gate
              behaviour, so that is the shape worth promoting.

An agent running this ritual can do better than the heuristics by reading the
proposals and the surrounding context. That is the intended workflow; the
script is the floor that works with zero model calls and no network.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kbcommon as kb  # noqa: E402

MARKER_RE = re.compile(
    r"^\s*(?:[-*+]\s+|\d+\.\s+)?(?:\*\*)?"
    r"(RULE|FACT|PREF|PREFERENCE|GOTCHA|CONSTRAINT|DECISION|LESSON)(?:\*\*)?\s*:\s*(.+?)\s*$",
    re.IGNORECASE,
)
DURABLE_HEADING_RE = re.compile(
    r"^#{1,6}\s+.*\b(durable|promote|promotion|learning|learnings|takeaway|takeaways|"
    r"rules?|lessons?)\b", re.IGNORECASE,
)
HEADING_RE = re.compile(r"^#{1,6}\s+")
GATING_RE = re.compile(
    r"\b(always|never|must not|must|don't|do not|doesn't|never use|prefer|prefers|"
    r"avoid|only use|require[sd]?|not allowed|instead of)\b", re.IGNORECASE,
)
SKIP_LINE_RE = re.compile(r"^\s*(?:```|~~~|\||>|\[.*\]:|#{1,6}\s*$)")

WEIGHT_MARKED = 3.0
WEIGHT_DURABLE_SECTION = 2.0
WEIGHT_GATING = 1.0
KIND_BONUS = {"decisions": 1.5, "sessions": 1.0, "notes": 1.0,
              "projects": 1.0, "research": 0.6}

MERGE_THRESHOLD = 0.60          # cluster two claims as "the same thing"
CONTAINMENT_THRESHOLD = 0.85    # ...or one is a restatement of the other
CONTAINMENT_MIN_TOKENS = 5
MEMORY_THRESHOLD = 0.62  # already covered by an existing atomic memory
MAX_CLAIM_CHARS = 240
MIN_CLAIM_TOKENS = 4


class Claim(object):
    __slots__ = ("text", "weight", "doc", "line", "signature", "tokens", "kind")

    def __init__(self, text, weight, doc, line, kind):
        self.text = text
        self.weight = weight
        self.doc = doc
        self.line = line
        self.kind = kind
        self.signature = kb.normalize_claim(text)
        self.tokens = self.signature.split()


def clean(text):
    text = re.sub(r"^\s*(?:[-*+]\s+|\d+\.\s+)", "", text)
    text = re.sub(r"\*\*|__|`", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return text.strip().rstrip(".").strip()


LIST_START_RE = re.compile(r"^\s*(?:[-*+]\s+|\d+\.\s+)")


def logical_lines(doc):
    """Yield (kind, text, line) with hard-wrapped lines rejoined.

    Markdown is wrapped for humans, so a rule written on one logical line lands
    in the file as two or three. Extracting per physical line produces proposed
    memories that stop mid-sentence, which are worse than useless -- a reviewer
    cannot approve a fragment. So paragraphs are rejoined first, and the line
    number reported is where the paragraph *starts*, which is what a citation
    should point at anyway.

    A new block starts at a blank line, a heading, a list item, or a marker.
    """
    buf, buf_line = [], None
    in_fence = False

    def flush():
        nonlocal buf, buf_line
        if buf:
            text = " ".join(part.strip() for part in buf).strip()
            if text:
                out.append(("text", text, buf_line))
        buf, buf_line = [], None

    out = []
    for offset, raw in enumerate(doc.body.split("\n")):
        line = doc.body_start_line + offset
        stripped = raw.strip()

        if stripped.startswith("```") or stripped.startswith("~~~"):
            flush()
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if not stripped:
            flush()
            continue
        if HEADING_RE.match(stripped):
            flush()
            out.append(("heading", stripped, line))
            continue
        if SKIP_LINE_RE.match(raw):
            flush()
            continue
        if LIST_START_RE.match(raw) or MARKER_RE.match(raw):
            flush()
            buf_line = line
            buf.append(raw)
            continue
        if buf_line is None:
            buf_line = line
        buf.append(raw)
    flush()
    return out


def first_sentences(text, limit):
    """Trim to a sentence boundary rather than mid-word, when one is in range."""
    if len(text) <= limit:
        return text
    cut = text[:limit]
    for stop in (". ", "; ", " -- ", " — "):
        idx = cut.rfind(stop)
        if idx > limit * 0.4:
            return cut[:idx].rstrip(" .;—-")
    return kb.squeeze(text, limit)


def extract_claims(doc):
    claims = []
    in_durable = False

    for kind, text, line in logical_lines(doc):
        if kind == "heading":
            in_durable = bool(DURABLE_HEADING_RE.match(text))
            continue

        marker = MARKER_RE.match(text)
        if marker:
            body = first_sentences(clean(marker.group(2)), MAX_CLAIM_CHARS)
            if len(kb.tokenize(body)) >= MIN_CLAIM_TOKENS:
                claims.append(Claim(body, WEIGHT_MARKED, doc, line, doc.kind))
            continue

        body = clean(text)
        if len(kb.tokenize(body)) < MIN_CLAIM_TOKENS:
            continue

        if in_durable and len(body) <= MAX_CLAIM_CHARS:
            claims.append(Claim(body, WEIGHT_DURABLE_SECTION, doc, line, doc.kind))
        elif GATING_RE.search(body) and len(body) <= 200:
            claims.append(Claim(body, WEIGHT_GATING, doc, line, doc.kind))
    return claims


class Cluster(object):
    def __init__(self, claim):
        self.claims = [claim]
        self.tokens = set(claim.tokens)

    def matches(self, claim):
        if kb.jaccard(self.tokens, claim.tokens) >= MERGE_THRESHOLD:
            return True
        # One claim restating the other with extra detail. Guarded by a minimum
        # size so a four-word phrase does not swallow every paragraph
        # containing those four words.
        if min(len(self.tokens), len(claim.tokens)) >= CONTAINMENT_MIN_TOKENS:
            return kb.overlap(self.tokens, claim.tokens) >= CONTAINMENT_THRESHOLD
        return False

    def add(self, claim):
        self.claims.append(claim)
        self.tokens |= set(claim.tokens)

    @property
    def files(self):
        return sorted(set(c.doc.rel for c in self.claims))

    @property
    def best(self):
        return sorted(self.claims, key=lambda c: (-c.weight, len(c.text)))[0]

    @property
    def score(self):
        base = sum(c.weight * KIND_BONUS.get(c.kind, 1.0) for c in self.claims)
        return round(base * (1.0 + 0.5 * (len(self.files) - 1)), 2)

    @property
    def reasons(self):
        out = []
        marked = sum(1 for c in self.claims if c.weight == WEIGHT_MARKED)
        if marked:
            out.append("%d explicit marker%s" % (marked, "" if marked == 1 else "s"))
        if len(self.files) > 1:
            out.append("recurs in %d documents" % len(self.files))
        if any(c.kind == "decisions" for c in self.claims):
            out.append("recorded as a decision")
        if any(GATING_RE.search(c.text) for c in self.claims):
            out.append("behaviour-gating language")
        return out or ["single mention"]


def cluster_claims(claims):
    clusters = []
    for claim in sorted(claims, key=lambda c: (-c.weight, c.doc.rel, c.line)):
        for cluster in clusters:
            if cluster.matches(claim):
                cluster.add(claim)
                break
        else:
            clusters.append(Cluster(claim))
    return clusters


def load_memory_signatures(memory_dir):
    """Read existing atomic memories so we do not propose what is already there.

    Read-only, and entirely optional -- an absent memory/ just means nothing
    gets filtered.
    """
    signatures = []
    if not memory_dir or not os.path.isdir(memory_dir):
        return signatures
    for dirpath, dirnames, filenames in os.walk(memory_dir):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for filename in sorted(filenames):
            if not filename.endswith((".md", ".txt")):
                continue
            path = os.path.join(dirpath, filename)
            try:
                text = kb.read_text(path)
            except OSError:
                continue
            try:
                _, body, _ = kb.parse_front_matter(text, path=path)
            except kb.KBError:
                body = text
            for raw in body.split("\n"):
                stripped = clean(raw.strip())
                if len(kb.tokenize(stripped)) >= MIN_CLAIM_TOKENS:
                    signatures.append((os.path.relpath(path, memory_dir),
                                       set(kb.normalize_claim(stripped).split())))
    return signatures


def covered_by_memory(cluster, signatures):
    for rel, tokens in signatures:
        if kb.jaccard(cluster.tokens, tokens) >= MEMORY_THRESHOLD:
            return rel
    return None


def recent_docs(root, since_days):
    import time

    cutoff = time.time() - since_days * 86400
    for doc in kb.iter_docs(root):
        if doc.status == "superseded":
            continue
        age = kb.age_days(doc.fm.get("updated") or doc.fm.get("created"))
        if age is not None:
            if age <= since_days:
                yield doc
            continue
        try:
            if os.path.getmtime(doc.path) >= cutoff:
                yield doc
        except OSError:
            continue


def build_proposals(root, since_days, limit, min_score, memory_dir):
    docs = list(recent_docs(root, since_days))
    claims = []
    for doc in docs:
        claims.extend(extract_claims(doc))

    clusters = cluster_claims(claims)
    signatures = load_memory_signatures(memory_dir)

    proposals, skipped = [], []
    for cluster in clusters:
        marked = any(c.weight == WEIGHT_MARKED for c in cluster.claims)
        if cluster.score < min_score or not (marked or len(cluster.files) >= 2):
            continue
        covered = covered_by_memory(cluster, signatures)
        if covered:
            skipped.append((cluster, covered))
        else:
            proposals.append(cluster)

    proposals.sort(key=lambda c: (-c.score, c.best.text))
    skipped.sort(key=lambda item: -item[0].score)
    return docs, proposals[:limit], skipped[:limit]


def render(root, docs, proposals, skipped, since_days, memory_dir):
    date = kb.today()
    fm = {
        "id": "%s-promotions" % date,
        "title": "Promotion proposals -- %s" % date,
        "type": "proposal",
        "status": "proposed",
        "source": "kb consolidate --since %d" % since_days,
        "created": date,
        "verified_on": date,
        "confidence": "low",
    }

    out = []
    out.append("Generated by `kb consolidate`. Nothing here has been promoted.")
    out.append("")
    out.append("Scanned %d document%s updated in the last %d days under `%s`."
               % (len(docs), "" if len(docs) == 1 else "s", since_days,
                  kb.display_path(root)))
    if memory_dir and os.path.isdir(memory_dir):
        out.append("Cross-checked against existing atomic memories in `%s`."
                   % kb.display_path(memory_dir))
    out.append("")
    out.append("**To approve:** copy the proposed memory line into an atomic memory file")
    out.append("under `memory/`, then delete the block here. **To reject:** delete the")
    out.append("block. Leaving a block untouched means undecided -- it will be proposed")
    out.append("again on the next run.")
    out.append("")

    if not proposals:
        out.append("## No proposals")
        out.append("")
        out.append("No claim cleared the bar (score >= threshold, and either explicitly")
        out.append("marked or recurring across two or more documents). That is a normal")
        out.append("result for a quiet week -- it is not a failure.")
    else:
        out.append("## Proposals (%d)" % len(proposals))
        out.append("")

    for i, cluster in enumerate(proposals, 1):
        best = cluster.best
        out.append("### P%d. %s" % (i, kb.squeeze(best.text, 90)))
        out.append("")
        out.append("- **proposed memory:** `%s`" % best.text)
        out.append("- **score:** %.2f (%s)" % (cluster.score, "; ".join(cluster.reasons)))
        out.append("- **evidence:**")
        for claim in sorted(cluster.claims, key=lambda c: (-c.weight, c.doc.rel, c.line))[:6]:
            out.append("  - `%s:%d` — %s"
                       % (kb.display_path(claim.doc.path), claim.line,
                          kb.squeeze(claim.text, 150)))
        out.append("")

    if skipped:
        out.append("## Already covered by atomic memory (%d)" % len(skipped))
        out.append("")
        out.append("Left in the KB on purpose. Promoting these again would duplicate a")
        out.append("standing instruction, and duplicate memories drift apart.")
        out.append("")
        for cluster, where in skipped:
            out.append("- %s — matches `memory/%s`"
                       % (kb.squeeze(cluster.best.text, 110), where))
        out.append("")

    return kb.render_doc(fm, "\n".join(out))


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="kb consolidate",
        description="Propose durable facts for promotion to atomic memory. Never promotes.",
    )
    parser.add_argument("--root", help="knowledge-base root (default: $EVE_KB_ROOT or kb/)")
    parser.add_argument("--since", type=int, default=14,
                        help="only consider documents updated in the last N days (default 14)")
    parser.add_argument("--limit", type=int, default=20, help="max proposals (default 20)")
    parser.add_argument("--min-score", type=float, default=3.0,
                        help="minimum cluster score to propose (default 3.0)")
    parser.add_argument("--memory-dir",
                        help="atomic memory directory to de-duplicate against "
                             "(default: <repo>/memory if present). Read only.")
    parser.add_argument("--stdout", action="store_true",
                        help="print the proposal file instead of writing it")
    parser.add_argument("--out", help="explicit output path")
    args = parser.parse_args(argv)

    root = kb.resolve_root(args.root)
    kb.ensure_dirs(root)

    memory_dir = args.memory_dir
    if memory_dir is None:
        guess = os.path.join(os.path.dirname(root), "memory")
        memory_dir = guess if os.path.isdir(guess) else None

    docs, proposals, skipped = build_proposals(
        root, args.since, args.limit, args.min_score, memory_dir)
    text = render(root, docs, proposals, skipped, args.since, memory_dir)

    if args.stdout:
        sys.stdout.write(text)
        return 0

    out_path = args.out or os.path.join(
        root, kb.PROPOSAL_DIR, "%s-promotions.md" % kb.today())
    kb.write_text(out_path, text)
    sys.stdout.write(
        "%d proposal%s, %d already covered -> %s\n"
        % (len(proposals), "" if len(proposals) == 1 else "s",
           len(skipped), kb.display_path(out_path))
    )
    if proposals:
        sys.stdout.write("review it, then move approved lines into memory/ yourself\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
