#!/usr/bin/env python3
"""A faithful re-implementation of how `eve search` sees text.

This module exists for one reason: the tier a query belongs to has to be a
measurable property of the fixture, not a label somebody typed. "Zero lexical
overlap" is only meaningful if it is computed the way the ranker computes it —
same stopword list, same minimum token length, same substring semantics, same
decision about which parts of a file are searchable.

So the stopword list is READ OUT OF `bin/eve` at run time rather than copied
here. If somebody adds "before" to it — and they should — this module changes
with it, the tier assertions are re-checked against the new tokenisation, and
the suite says so loudly instead of quietly reporting a different number for
the same name.

What is deliberately mirrored from bin/eve:

  tokenise()   lowercase, every non-[a-z0-9] byte becomes a space, drop tokens
               shorter than 3 characters, drop stopwords, de-duplicate keeping
               first appearance, stop at 12.
  containment  substring, not word equality. `index(haystack, token)` is what
               the scorer calls, which is why "ship" finds "shipments" and
               "live" finds "secrets-live-in-the-vault". Modelling this as word
               matching would make the fixture look cleaner than it is.
  searchable   frontmatter is not body. The scorer consumes `title:`, `type:`,
               `status:`, `tags:` and `verified_on:` and skips every other
               frontmatter line, so a word that appears only in `source:` is
               not findable and must not be counted as overlap.
"""
import re
from pathlib import Path

MIN_TOKEN = 3
MAX_TOKENS = 12

_STOPWORD_LINE = re.compile(r'^STOPWORDS="(.*)"\s*$')


def load_stopwords(eve_path):
    """Parse the STOPWORDS assignment out of bin/eve.

    Raises if it cannot be found, because silently falling back to a copy would
    let this module and the ranker disagree — which is the one failure this
    whole file exists to prevent.
    """
    p = Path(eve_path)
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise RuntimeError(f"cannot read {p}: {exc}") from exc
    for line in text.splitlines():
        m = _STOPWORD_LINE.match(line)
        if m:
            # Tokens are compared as whole words; eve tests " word " against the
            # padded list, which is set membership. Non-ASCII entries can never
            # match an ASCII token and are dropped here for the same reason.
            return {w for w in m.group(1).split() if w.isascii()}
    raise RuntimeError(f"no STOPWORDS assignment found in {p}")


def norm(s):
    """bin/eve's norm(): lowercase, non-alphanumerics to spaces, padded."""
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return " " + s.strip() + " "


def tokenise(query, stopwords):
    """bin/eve's tokenise(): the surviving query tokens, in order."""
    lowered = query.lower()
    flat = re.sub(r"[^a-z0-9]+", " ", lowered)
    out = []
    seen = set()
    for tok in flat.split():
        if len(tok) < MIN_TOKEN:
            continue
        if tok in stopwords:
            continue
        if tok in seen:
            continue
        seen.add(tok)
        out.append(tok)
        if len(out) >= MAX_TOKENS:
            break
    return out


class Memory:
    """One fixture file, split the way the scorer splits it."""

    def __init__(self, path):
        self.path = Path(path)
        self.id = self.path.name[: -len(".md")] if self.path.name.endswith(".md") else self.path.name
        self.title = ""
        self.tags = ""
        self.body_lines = []
        self._parse()

    def _parse(self):
        lines = self.path.read_text(encoding="utf-8").splitlines()
        in_fm = False
        fm_done = False
        for i, line in enumerate(lines):
            if i == 0 and re.match(r"^---[ \t]*$", line):
                in_fm = True
                continue
            if in_fm and not fm_done:
                if re.match(r"^---[ \t]*$", line):
                    fm_done = True
                    continue
                if line.startswith("title:"):
                    self.title = _clean(line)
                elif line.startswith("tags:"):
                    self.tags = re.sub(r"[\[\],]", " ", _clean(line))
                # Every other frontmatter key is consumed and not searchable.
                continue
            self.body_lines.append(line)

    def head_hits(self, tokens):
        """Tokens found in title, filename or tags — the high-weight fields."""
        fields = [norm(self.title), norm(self.id), norm(self.tags)]
        return [t for t in tokens if any(t in f for f in fields)]

    def body_hits(self, tokens):
        """Tokens found in the prose. Worth 2 each, which is below the gate."""
        hays = [norm(line) for line in self.body_lines]
        return [t for t in tokens if any(t in h for h in hays)]


def _clean(v):
    v = re.sub(r"^[^:]*:[ \t]*", "", v)
    return v.strip(" \t\"'")


class Store:
    def __init__(self, memdir):
        self.memdir = Path(memdir)
        self.memories = {}
        for p in sorted(self.memdir.glob("*.md")):
            if p.name in ("TEMPLATE.md", "MEMORY.md", "INDEX.md", "README.md"):
                continue
            m = Memory(p)
            self.memories[m.id] = m

    def overlap(self, target_id, tokens):
        """Measured overlap between a query and its target, plus the tier it implies.

        The tier definitions, stated once:

          verbatim   2 or more surviving tokens land in the title, filename or
                     tags. This is the query a person types when they already
                     remember what the memory is called.
          paraphrase at least one token lands somewhere in the file, but fewer
                     than 2 land in the high-weight fields. Real questions live
                     here.
          disjoint   no surviving token appears anywhere in the file. The
                     ranker cannot retrieve this target at any gate setting —
                     it is not a candidate. This tier measures a ceiling, not a
                     bug.
        """
        m = self.memories.get(target_id)
        if m is None:
            raise KeyError(target_id)
        head = m.head_hits(tokens)
        body = m.body_hits(tokens)
        both = set(head) | set(body)
        if len(head) >= 2:
            tier = "verbatim"
        elif both:
            tier = "paraphrase"
        else:
            tier = "disjoint"
        return {
            "tier": tier,
            "head": len(head),
            "body": len(set(body) - set(head)),
            "head_toks": head,
            "body_toks": sorted(set(body) - set(head)),
        }
