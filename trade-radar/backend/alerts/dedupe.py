"""Cross-source dedupe.

Normalize titles and fuzzy-match (token-set ratio >= threshold) within a time
window for the same ticker. The first item creates a cluster and triggers one
alert; later matching items are merged into that cluster (their sources appended)
instead of firing a new alert. Every source's first_seen is retained so the UI
can show which feed was fastest.

Consumer: backend/alerts/engine.py
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from rapidfuzz import fuzz

from ..models import NewsItem

_PUNCT_RE = re.compile(r"[^a-z0-9 ]+")
_WS_RE = re.compile(r"\s+")
# Low-value tokens that inflate similarity between unrelated market headlines.
_STOP = {
    "the", "a", "an", "to", "of", "in", "on", "for", "and", "or", "as", "is",
    "are", "at", "by", "says", "say", "report", "reports", "update", "stock",
    "shares", "inc", "corp", "co", "amp",
}


def normalize_title(title: str) -> str:
    title = (title or "").lower()
    # Drop apostrophes so "tesla's" -> "teslas" (not "tesla s").
    title = title.replace("'", "").replace("\u2019", "")
    title = _PUNCT_RE.sub(" ", title)
    tokens = [t for t in _WS_RE.sub(" ", title).split() if t and t not in _STOP]
    return " ".join(tokens)


@dataclass
class Cluster:
    key: str
    ticker: str
    canonical_title: str
    norm_title: str
    first_item: NewsItem
    items: list[NewsItem] = field(default_factory=list)
    sources: dict[str, datetime] = field(default_factory=dict)  # source -> first_seen
    created_at: datetime = field(default_factory=lambda: datetime.min)

    def add(self, item: NewsItem) -> None:
        self.items.append(item)
        # Keep the EARLIEST first_seen per source.
        prev = self.sources.get(item.source)
        if prev is None or item.first_seen_at < prev:
            self.sources[item.source] = item.first_seen_at

    def fastest_source(self) -> tuple[str, datetime] | None:
        if not self.sources:
            return None
        return min(self.sources.items(), key=lambda kv: kv[1])


class Deduper:
    def __init__(self, ratio_threshold: int = 85, window_minutes: int = 120) -> None:
        self.ratio_threshold = ratio_threshold
        self.window = timedelta(minutes=window_minutes)
        self._clusters: list[Cluster] = []

    def _prune(self, now: datetime) -> None:
        self._clusters = [
            c for c in self._clusters if now - c.first_item.published_at <= self.window
        ]

    def add(self, item: NewsItem) -> tuple[Cluster, bool]:
        """Return (cluster, is_new_cluster).

        is_new_cluster=True means this should fire a NEW alert; False means it was
        merged into an existing story and should only append a source.
        """
        now = item.published_at
        self._prune(now)
        norm = normalize_title(item.headline)
        item_tickers = set(item.tickers) or {"*"}

        for c in self._clusters:
            if abs((item.published_at - c.first_item.published_at).total_seconds()) > self.window.total_seconds():
                continue
            # Same-ticker requirement (or wildcard when untagged).
            if c.ticker != "*" and item_tickers != {"*"} and c.ticker not in item_tickers:
                continue
            score = fuzz.token_set_ratio(norm, c.norm_title)
            if score >= self.ratio_threshold:
                c.add(item)
                return c, False

        ticker = sorted(item_tickers)[0]
        cluster = Cluster(
            key=f"{ticker}:{normalize_title(item.headline)[:60]}:{item.published_at.timestamp():.0f}",
            ticker=ticker,
            canonical_title=item.headline,
            norm_title=norm,
            first_item=item,
            created_at=item.first_seen_at,
        )
        cluster.add(item)
        self._clusters.append(cluster)
        return cluster, True
