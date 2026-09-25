"""Google News RSS poller.

One query per holding/alias, e.g. 'Tesla OR TSLA', 'Tesla Optimus'. URL:
  https://news.google.com/rss/search?q=<url-encoded>&hl=en-US&gl=US&ceid=US:en
pubDate is RFC-822 GMT; we keep it as published_at and stamp our own first_seen.
New items (unseen guid) are published to the bus; duplicates across polls are
suppressed by an in-memory seen-set.
"""

from __future__ import annotations

from urllib.parse import quote

from ..bus import EventBus
from ..config import GoogleQuery
from .base import PollingProvider
from .http import Fetcher, http_get_text
from .rss_common import parse_google_news

BASE = "https://news.google.com/rss/search"


def build_url(query: str) -> str:
    return f"{BASE}?q={quote(query)}&hl=en-US&gl=US&ceid=US:en"


class GoogleNewsProvider(PollingProvider):
    name = "google_news"

    def __init__(
        self,
        bus: EventBus,
        queries: list[GoogleQuery],
        *,
        poll_seconds: int = 45,
        fetcher: Fetcher | None = None,
    ) -> None:
        super().__init__(bus, poll_seconds=poll_seconds)
        self.queries = queries
        self._fetch = fetcher or http_get_text
        self._seen: set[str] = set()

    async def run_once(self) -> int:
        emitted = 0
        for gq in self.queries:
            xml = await self._fetch(build_url(gq.query))
            for item in parse_google_news(xml, default_tickers=[t.upper() for t in gq.tickers]):
                did = item.dedupe_id()
                if did in self._seen:
                    continue
                self._seen.add(did)
                await self.bus.publish(item)
                emitted += 1
        return emitted
