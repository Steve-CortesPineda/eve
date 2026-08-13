"""Read-only access to a fixture knowledge base, and mechanical citation checking.

No third-party imports. Python 3.8+.

The only interesting thing in here is `resolve_citation`, which answers two
questions that a scorer has to answer mechanically or not at all:

  1. Does the cited location EXIST?  (fabricated path / fabricated section)
  2. Does the cited location CONTAIN the claim?  (real file, wrong content)

A citation that fails (1) is the most dangerous output an agent can produce,
because it looks like evidence and costs a human a trip to a 404 to disprove.
A citation that fails (2) is worse in a different way: the link resolves, the
reader glances at the file, and nobody ever checks that the sentence is in it.
"""

import os
import re
import unicodedata

# Files at the KB root that describe the fixture rather than being part of it.
# Excluded from the retrievable corpus so that an agent cannot read the eval's
# own commentary and infer which questions are traps.
CORPUS_EXCLUDE_ROOT = {"README.md"}

_HEADING_RE = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$")
_FRONTMATTER_RE = re.compile(r"\A---\r?\n.*?\r?\n---[ \t]*\r?\n", re.DOTALL)

# Characters that carry no meaning for a substring match but that markdown
# sprinkles through numbers: "**5** most recent" must match "5 most recent".
_STRIP_CHARS = set("*_`~[]()<>\"'")


def normalize(text):
    """Fold text to a form where substring matching is meaningful.

    Lowercases, drops markdown emphasis and punctuation that splits phrases,
    normalizes unicode dashes and spaces, and collapses whitespace. Applied
    identically to KB text and to agent answers, so the comparison stays fair.
    """
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text)
    text = text.replace("—", "-").replace("–", "-").replace("−", "-")
    text = text.replace("‘", "'").replace("’", "'")
    text = text.replace("“", '"').replace("”", '"')
    text = text.replace(" ", " ")
    out = []
    for ch in text:
        if ch in _STRIP_CHARS:
            continue
        out.append(ch)
    return re.sub(r"\s+", " ", "".join(out)).strip().lower()


def slugify(heading):
    """GitHub-flavoured-ish anchor slug for a heading."""
    text = unicodedata.normalize("NFKC", heading)
    for ch in "*_`~":
        text = text.replace(ch, "")
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # [label](url) -> label
    text = text.strip().lower()
    text = re.sub(r"[^a-z0-9\s-]", "", text)
    text = re.sub(r"\s+", "-", text)
    return re.sub(r"-{2,}", "-", text).strip("-")


def parse_citation(raw):
    """Split a citation string into (path, anchor|None). Tolerant of prefixes.

    Accepts 'services/x.md#shards', './services/x.md', 'fixture-kb/services/x.md',
    and strips surrounding punctuation an agent's prose may leave behind.
    """
    if raw is None:
        return "", None
    cite = str(raw).strip().strip("`\"'").rstrip(".,;:)").lstrip("(")
    cite = cite.replace("\\", "/")
    for prefix in ("./", "/"):
        while cite.startswith(prefix):
            cite = cite[len(prefix):]
    for prefix in ("fixture-kb/", "evals/fixture-kb/", "kb/"):
        if cite.startswith(prefix):
            cite = cite[len(prefix):]
    if "#" in cite:
        path, anchor = cite.split("#", 1)
        anchor = anchor.strip()
        return path.strip(), (anchor or None)
    return cite, None


class KB:
    """A fixture knowledge base rooted at a directory."""

    def __init__(self, root):
        self.root = os.path.abspath(root)
        if not os.path.isdir(self.root):
            raise FileNotFoundError("KB root does not exist: %s" % self.root)
        self._cache = {}

    # -- corpus -----------------------------------------------------------

    def docs(self):
        """[(relpath, text)] for every retrievable document, sorted."""
        found = []
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            for name in sorted(filenames):
                if not name.endswith(".md"):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, self.root).replace(os.sep, "/")
                if rel in CORPUS_EXCLUDE_ROOT:
                    continue
                found.append((rel, self.read(rel)))
        return found

    def read(self, relpath):
        if relpath in self._cache:
            return self._cache[relpath]
        full = self._safe_join(relpath)
        if full is None or not os.path.isfile(full):
            self._cache[relpath] = None
            return None
        with open(full, "r", encoding="utf-8") as handle:
            text = handle.read()
        self._cache[relpath] = text
        return text

    def exists(self, relpath):
        return self.read(relpath) is not None

    def _safe_join(self, relpath):
        """Join under root, refusing anything that escapes it."""
        if not relpath or relpath.startswith("/"):
            return None
        candidate = os.path.abspath(os.path.join(self.root, relpath))
        if candidate != self.root and not candidate.startswith(self.root + os.sep):
            return None
        return candidate

    # -- sections ---------------------------------------------------------

    def headings(self, relpath):
        text = self.read(relpath)
        if text is None:
            return []
        body = _FRONTMATTER_RE.sub("", text)
        out = []
        for line in body.splitlines():
            match = _HEADING_RE.match(line)
            if match:
                out.append((len(match.group(1)), match.group(2), slugify(match.group(2))))
        return out

    def section(self, relpath, anchor):
        """Text of the section whose heading slugifies to `anchor`.

        Runs from the heading line to the next heading of the same or higher
        level. Returns None if there is no such heading.
        """
        text = self.read(relpath)
        if text is None:
            return None
        body = _FRONTMATTER_RE.sub("", text)
        want = slugify(anchor)
        lines = body.splitlines()
        start = None
        level = 0
        for i, line in enumerate(lines):
            match = _HEADING_RE.match(line)
            if match and slugify(match.group(2)) == want:
                start = i
                level = len(match.group(1))
                break
        if start is None:
            return None
        end = len(lines)
        for j in range(start + 1, len(lines)):
            match = _HEADING_RE.match(lines[j])
            if match and len(match.group(1)) <= level:
                end = j
                break
        return "\n".join(lines[start:end])

    # -- the load-bearing check -------------------------------------------

    def resolve_citation(self, raw, claim_tokens):
        """Check one citation. Returns a dict, never raises.

        resolved  the path (and anchor, if given) exists
        supports  the cited text contains at least one claim token
        valid     resolved and supports
        reason    machine-readable failure code

        `claim_tokens` empty means nothing in the KB can support this claim
        (that is how ABSENT questions are encoded), so `supports` is False by
        construction: you cannot cite evidence for a fact the KB does not hold.
        """
        path, anchor = parse_citation(raw)
        result = {
            "raw": str(raw),
            "path": path,
            "anchor": anchor,
            "resolved": False,
            "supports": False,
            "valid": False,
            "reason": "",
        }

        if not path:
            result["reason"] = "empty_citation"
            return result
        if not self.exists(path):
            result["reason"] = "path_not_found"
            return result

        if anchor is not None:
            scope = self.section(path, anchor)
            if scope is None:
                result["reason"] = "anchor_not_found"
                return result
        else:
            scope = self.read(path)

        result["resolved"] = True

        if not claim_tokens:
            result["reason"] = "no_supporting_content_exists"
            return result

        haystack = normalize(scope)
        for token in claim_tokens:
            if normalize(token) and normalize(token) in haystack:
                result["supports"] = True
                result["valid"] = True
                result["reason"] = "ok"
                return result

        result["reason"] = "claim_not_in_cited_text"
        return result
