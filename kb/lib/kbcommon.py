"""Shared helpers for the Eve knowledge-base tools.

Stdlib only. Targets Python 3.8+ so it runs on the python3 that ships with
macOS without anyone installing anything.

Three things live here:

  1. A deliberately small front-matter parser/serializer. It reads a strict
     subset of YAML (see parse_front_matter) rather than depending on PyYAML.
     The subset is documented and enforced -- unsupported constructs are
     reported as errors instead of being silently misread.
  2. Document discovery and reading, with line numbers preserved so every
     passage the search tool returns can carry a `path:line` anchor.
  3. Tokenization/normalization shared by search and consolidation, so the two
     agree on what counts as "the same claim".
"""

import datetime
import hashlib
import os
import re
import sys
import unicodedata

# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------

# The five knowledge directories. Kept deliberately short: every extra bucket
# is a decision the writer has to make at capture time, and buckets that make
# people hesitate do not get used.
KNOWN_DIRS = ("notes", "projects", "sessions", "decisions", "research")

# Not knowledge. An outbox for consolidation proposals awaiting human review.
PROPOSAL_DIR = "proposals"

# Front-matter keys, in the order they are written back out.
FM_ORDER = (
    "id",
    "title",
    "type",
    "status",
    "tags",
    "source",
    "created",
    "updated",
    "verified_on",
    "confidence",
    "supersedes",
    "superseded_by",
    "source_sha256",
)

REQUIRED_FM = ("id", "title", "type", "source", "created", "verified_on", "confidence")

LIST_KEYS = ("tags", "supersedes")
CONFIDENCE_LEVELS = ("high", "medium", "low")
STATUSES = ("current", "draft", "superseded")

TEXT_EXTS = (".md", ".markdown", ".txt")


class KBError(Exception):
    """A problem the user can fix, reported without a traceback."""


def die(msg):
    sys.stderr.write("kb: error: %s\n" % msg)
    raise SystemExit(2)


# --------------------------------------------------------------------------
# Root resolution
# --------------------------------------------------------------------------


def default_root():
    """kb/ is the directory two levels up from this file (kb/lib/kbcommon.py)."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def resolve_root(explicit=None):
    root = explicit or os.environ.get("EVE_KB_ROOT") or default_root()
    root = os.path.abspath(os.path.expanduser(root))
    if not os.path.isdir(root):
        die("knowledge-base root does not exist: %s" % root)
    return root


def ensure_dirs(root):
    for name in KNOWN_DIRS + (PROPOSAL_DIR,):
        path = os.path.join(root, name)
        if not os.path.isdir(path):
            os.makedirs(path)


def display_path(path):
    """Path a human can paste into an editor. Relative to cwd when sensible."""
    abspath = os.path.abspath(path)
    try:
        rel = os.path.relpath(abspath, os.getcwd())
    except ValueError:  # different drive on some platforms
        return abspath
    if rel.startswith(".." + os.sep + ".." + os.sep + ".."):
        return abspath
    return rel


# --------------------------------------------------------------------------
# Dates
# --------------------------------------------------------------------------

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def today():
    return datetime.date.today().isoformat()


def parse_date(value):
    if not value or not DATE_RE.match(str(value).strip()):
        return None
    try:
        return datetime.date.fromisoformat(str(value).strip())
    except ValueError:
        return None


def age_days(value, ref=None):
    """Whole days between `value` (YYYY-MM-DD) and today. None if unparseable.

    Clamped at zero so a future date never inflates a score.
    """
    date = parse_date(value)
    if date is None:
        return None
    ref = ref or datetime.date.today()
    return max(0, (ref - date).days)


# --------------------------------------------------------------------------
# Front matter
# --------------------------------------------------------------------------

_FENCE = "---"


def parse_front_matter(text, path="<string>"):
    """Split `text` into (front_matter_dict, body, body_start_line).

    `body_start_line` is 1-based and points at the first line of the body in
    the original file, so callers can turn body offsets into file line numbers.

    Supported YAML subset -- anything else raises KBError rather than guessing:

        key: scalar value
        key: "quoted value"
        key: [a, b, c]
        key:
          - a
          - b
        # whole-line comment

    Values are kept as strings (or lists of strings). No type coercion, no
    nested maps, no multi-line scalars. That is enough for provenance metadata
    and it means the parser is 60 lines instead of a dependency.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != _FENCE:
        return {}, text, 1

    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == _FENCE:
            end = i
            break
    if end is None:
        raise KBError("%s: front matter opened with '---' but never closed" % path)

    data = {}
    pending_key = None
    for offset in range(1, end):
        raw = lines[offset]
        lineno = offset + 1
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue

        if raw.lstrip().startswith("- "):
            if pending_key is None:
                raise KBError(
                    "%s:%d: list item with no key above it" % (path, lineno)
                )
            data[pending_key].append(_scalar(raw.lstrip()[2:].strip()))
            continue

        if raw[:1] in (" ", "\t"):
            raise KBError(
                "%s:%d: indented value -- nested maps are not supported" % (path, lineno)
            )

        if ":" not in raw:
            raise KBError("%s:%d: expected 'key: value'" % (path, lineno))

        key, _, value = raw.partition(":")
        key = key.strip()
        value = value.strip()
        if not key:
            raise KBError("%s:%d: empty key" % (path, lineno))

        if value == "":
            data[key] = []
            pending_key = key
        elif value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            data[key] = [_scalar(p.strip()) for p in inner.split(",") if p.strip()]
            pending_key = None
        elif value in ("|", ">"):
            raise KBError(
                "%s:%d: block scalars are not supported -- keep front matter flat"
                % (path, lineno)
            )
        else:
            data[key] = _scalar(value)
            pending_key = None

    body = "\n".join(lines[end + 1 :])
    # Drop one leading blank line so bodies round-trip cleanly.
    body_start_line = end + 2
    if body.startswith("\n"):
        body = body[1:]
        body_start_line += 1
    return data, body, body_start_line


def _scalar(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def _needs_quotes(value):
    text = str(value)
    if text == "":
        return True
    if text[0] in ("'", '"', "[", "]", "{", "}", "#", "-", "*", "&", "!", "|", ">", "%", "@", "`"):
        return True
    if ": " in text or text.endswith(":") or " #" in text:
        return True
    return False


def _emit_scalar(value):
    text = str(value)
    if _needs_quotes(text):
        return '"%s"' % text.replace('\\', '\\\\').replace('"', '\\"')
    return text


def serialize_front_matter(data):
    """Deterministic front matter. Schema keys first, extras alphabetically."""
    keys = [k for k in FM_ORDER if k in data]
    keys += sorted(k for k in data if k not in FM_ORDER)
    out = [_FENCE]
    for key in keys:
        value = data[key]
        if isinstance(value, (list, tuple)):
            if not value:
                continue
            out.append("%s: [%s]" % (key, ", ".join(_emit_scalar(v) for v in value)))
        else:
            if value is None or str(value).strip() == "":
                continue
            out.append("%s: %s" % (key, _emit_scalar(value)))
    out.append(_FENCE)
    return "\n".join(out) + "\n"


def render_doc(front_matter, body):
    body = body.rstrip("\n")
    return serialize_front_matter(front_matter) + "\n" + body + "\n"


# --------------------------------------------------------------------------
# Documents
# --------------------------------------------------------------------------


class Doc(object):
    __slots__ = ("path", "rel", "fm", "body", "body_start_line", "kind")

    def __init__(self, path, rel, fm, body, body_start_line, kind):
        self.path = path
        self.rel = rel
        self.fm = fm
        self.body = body
        self.body_start_line = body_start_line
        self.kind = kind

    @property
    def title(self):
        return self.fm.get("title") or os.path.basename(self.path)

    @property
    def doc_id(self):
        return self.fm.get("id") or slugify(os.path.splitext(os.path.basename(self.path))[0])

    @property
    def status(self):
        return (self.fm.get("status") or "current").strip()

    @property
    def tags(self):
        value = self.fm.get("tags") or []
        if isinstance(value, str):
            return [value]
        return list(value)

    @property
    def freshness_date(self):
        for key in ("verified_on", "updated", "created"):
            if self.fm.get(key):
                return self.fm[key]
        return None


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def write_text(path, text):
    directory = os.path.dirname(path)
    if directory and not os.path.isdir(directory):
        os.makedirs(directory)
    tmp = path + ".kbtmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(tmp, path)


def load_doc(path, root):
    text = read_text(path)
    fm, body, start = parse_front_matter(text, path=display_path(path))
    rel = os.path.relpath(path, root)
    kind = rel.split(os.sep)[0] if os.sep in rel else "notes"
    return Doc(path, rel, fm, body, start, kind)


def iter_docs(root, dirs=None, include_proposals=False, errors=None):
    """Yield Doc objects from the knowledge directories, sorted by path.

    Only the known directories are walked. A stray markdown file at the KB root
    is not silently indexed -- `kb doctor` reports it instead, because silent
    indexing is how a KB starts accumulating things nobody meant to keep.
    """
    names = list(dirs or KNOWN_DIRS)
    if include_proposals:
        names.append(PROPOSAL_DIR)
    for name in names:
        base = os.path.join(root, name)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(
                d for d in dirnames if not d.startswith(".") and not d.startswith("_")
            )
            for filename in sorted(filenames):
                if not filename.endswith(".md") or filename.startswith("."):
                    continue
                path = os.path.join(dirpath, filename)
                try:
                    yield load_doc(path, root)
                except KBError as exc:
                    # A document that will not parse is invisible to search --
                    # the worst failure mode there is, because nothing says so.
                    # Callers that can report it properly (kb doctor) pass a
                    # collector; everyone else at least gets it on stderr.
                    if errors is None:
                        sys.stderr.write("kb: skipping %s\n" % exc)
                    else:
                        errors.append((path, str(exc)))


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def slugify(value):
    value = unicodedata.normalize("NFKD", str(value))
    value = value.encode("ascii", "ignore").decode("ascii").lower()
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    value = re.sub(r"-{2,}", "-", value)
    return value[:80] or "untitled"


# --------------------------------------------------------------------------
# Text normalization (shared by search + consolidate)
# --------------------------------------------------------------------------

STOPWORDS = frozenset(
    """
a an the and or but if then than that this these those of in on at to for from by
with without into over under is are was were be been being it its as we you your
i my our their there here what which who whom how when where why do does did done
not no so such can will would could should may might must about after before also
""".split()
)

_TOKEN_RE = re.compile(r"[a-z0-9]+(?:[._][a-z0-9]+)*")


def tokenize(text, keep_stopwords=False):
    tokens = []
    for raw in _TOKEN_RE.findall(str(text).lower()):
        for part in re.split(r"[._]", raw):
            if len(part) < 2:
                continue
            if not keep_stopwords and part in STOPWORDS:
                continue
            tokens.append(stem(part))
    return tokens


def stem(word):
    """Conservative plural stripping. Nothing clever -- predictability wins."""
    if len(word) > 3 and word.endswith("ies"):
        return word[:-3] + "y"
    if len(word) > 3 and word.endswith("ses"):
        return word[:-2]
    if len(word) > 3 and word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


def normalize_claim(text):
    """Signature used to tell whether two sentences say the same thing."""
    text = re.sub(r"`[^`]*`", " ", str(text))
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    tokens = tokenize(text)
    return " ".join(sorted(set(tokens)))


def jaccard(a, b):
    sa, sb = set(a), set(b)
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / float(len(sa | sb))


def overlap(a, b):
    """Containment: how much of the *smaller* claim appears in the larger.

    Jaccard alone splits "cache keys must be content hashes, never mtime" from
    the same rule written with an extra clause, because the longer version
    dilutes the union. Overlap catches the case where one claim is a restatement
    of the other with more detail attached.
    """
    sa, sb = set(a), set(b)
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / float(min(len(sa), len(sb)))


def squeeze(text, limit=220):
    text = re.sub(r"\s+", " ", str(text)).strip()
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"
