"""Ticker/alias matching and the keyword fast-path.

The fast-path sends within seconds with NO LLM: it fires when a fresh item
mentions a holding ticker (or any alias) AND matches a risk keyword. Matching is
case-insensitive and word-boundary aware so 'EU' does not match 'euro' and 'ES'
does not match 'shares'.

Consumers: backend/alerts/engine.py, backend/providers/* (ticker tagging).
"""

from __future__ import annotations

import re
from dataclasses import dataclass


def _boundary_regex(terms: list[str]) -> re.Pattern | None:
    cleaned = [re.escape(t.strip()) for t in terms if t and t.strip()]
    if not cleaned:
        return None
    # Sort longest-first so multi-word aliases win over their prefixes.
    cleaned.sort(key=len, reverse=True)
    return re.compile(r"(?<!\w)(?:" + "|".join(cleaned) + r")(?!\w)", re.IGNORECASE)


class TickerMatcher:
    """Maps free text to the configured tickers it mentions."""

    def __init__(self, ticker_terms: dict[str, list[str]]) -> None:
        self._patterns: dict[str, re.Pattern] = {}
        for ticker, terms in ticker_terms.items():
            all_terms = [ticker] + list(terms)
            pat = _boundary_regex(all_terms)
            if pat is not None:
                self._patterns[ticker.upper()] = pat

    def match(self, text: str) -> list[str]:
        text = text or ""
        hits = [tk for tk, pat in self._patterns.items() if pat.search(text)]
        return sorted(hits)


@dataclass
class FastPathHit:
    tickers: list[str]
    keywords: list[str]

    @property
    def fired(self) -> bool:
        return bool(self.tickers and self.keywords)


class KeywordFastPath:
    def __init__(self, holding_terms: dict[str, list[str]], risk_keywords: list[str]) -> None:
        self.matcher = TickerMatcher(holding_terms)
        self._kw_pattern = _boundary_regex(risk_keywords)

    def evaluate(self, headline: str, summary: str = "") -> FastPathHit:
        text = f"{headline} {summary}".strip()
        tickers = self.matcher.match(text)
        keywords: list[str] = []
        if self._kw_pattern is not None:
            keywords = sorted({m.group(0).lower() for m in self._kw_pattern.finditer(text)})
        return FastPathHit(tickers=tickers, keywords=keywords)
