"""Normalized domain objects + persistence tables.

Providers emit the normalized `NewsItem` / `Quote` / `CalendarEvent` objects onto
the event bus (backend/bus.py). The alert engine consumes them. SQLModel tables
persist every headline (with per-source first_seen) and every alert so latency
can be analyzed later, as required by the spec.

Producers: backend/providers/*  ->  Consumers: backend/alerts/engine.py, API.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field
from sqlmodel import Field as SQLField
from sqlmodel import SQLModel

from .timeutil import now_utc


# --------------------------------------------------------------------------- #
# Normalized in-memory events (what flows on the bus)
# --------------------------------------------------------------------------- #
class NewsItem(BaseModel):
    """A single normalized news headline from any source."""

    source: str
    external_id: str
    headline: str
    url: str = ""
    summary: str = ""
    author: str = ""
    tickers: list[str] = Field(default_factory=list)
    published_at: datetime  # from the feed (authoritative event time, UTC)
    first_seen_at: datetime = Field(default_factory=now_utc)  # when WE saw it

    def dedupe_id(self) -> str:
        """Stable per-source identity used to avoid re-ingesting the same item."""
        return f"{self.source}:{self.external_id}"


class Quote(BaseModel):
    """A price quote. Delayed feeds MUST set is_delayed=True (never show as live)."""

    symbol: str
    last: Optional[float] = None
    change: Optional[float] = None
    change_pct: Optional[float] = None
    is_delayed: bool = True
    source: str = ""
    ts: datetime = Field(default_factory=now_utc)


class CalendarEvent(BaseModel):
    title: str
    country: str = "USD"
    impact: str = "Low"  # High / Medium / Low / Holiday
    when: datetime
    forecast: Optional[str] = None
    previous: Optional[str] = None
    actual: Optional[str] = None
    source: str = ""


# --------------------------------------------------------------------------- #
# Persistence (SQLite via SQLModel)
# --------------------------------------------------------------------------- #
class HeadlineRecord(SQLModel, table=True):
    """One row per (source, external_id). Stores per-source first_seen so we can
    later report which feed was fastest for a given story."""

    __tablename__ = "headlines"

    id: Optional[int] = SQLField(default=None, primary_key=True)
    dedupe_id: str = SQLField(index=True)
    source: str = SQLField(index=True)
    external_id: str
    headline: str
    url: str = ""
    summary: str = ""
    author: str = ""
    tickers: str = ""  # comma-separated
    published_at: datetime
    first_seen_at: datetime = SQLField(default_factory=now_utc, index=True)
    # The story cluster this headline was merged into (dedupe). Null until clustered.
    cluster_key: Optional[str] = SQLField(default=None, index=True)


class AlertRecord(SQLModel, table=True):
    __tablename__ = "alerts"

    id: Optional[int] = SQLField(default=None, primary_key=True)
    kind: str = SQLField(index=True)  # news_fastpath, price, macro, combo, feed_health...
    ticker: str = SQLField(default="", index=True)
    severity: int = 0
    direction: str = ""  # bullish / bearish / neutral / unscored
    title: str = ""
    body: str = ""
    cluster_key: Optional[str] = SQLField(default=None, index=True)
    acknowledged: bool = SQLField(default=False)
    created_at: datetime = SQLField(default_factory=now_utc, index=True)
    delivered: bool = SQLField(default=False)
