"""Investing.com RSS poller.

Default feed: https://www.investing.com/rss/news_25.rss (stock market news).
The feed list is configurable so more categories can be added. Needs a normal
browser UA (handled by the shared fetcher). pubDate is 'YYYY-MM-DD HH:MM:SS' GMT.
Items are a general market feed, so ticker tagging is left to the alert engine's
alias matcher.
"""

from __future__ import annotations

from ..bus import EventBus
from .base import PollingProvider
from .http import Fetcher, http_get_text
from .rss_common import parse_investing

DEFAULT_FEEDS = ["https://www.investing.com/rss/news_25.rss"]


class InvestingProvider(PollingProvider):
    name = "investing"

    def __init__(
        self,
        bus: EventBus,
        feeds: list[str] | None = None,
        *,
        poll_seconds: int = 45,
        fetcher: Fetcher | None = None,
    ) -> None:
        super().__init__(bus, poll_seconds=poll_seconds)
        self.feeds = feeds or list(DEFAULT_FEEDS)
        self._fetch = fetcher or http_get_text
        self._seen: set[str] = set()

    async def run_once(self) -> int:
        emitted = 0
        for url in self.feeds:
            xml = await self._fetch(url)
            for item in parse_investing(xml):
                did = item.dedupe_id()
                if did in self._seen:
                    continue
                self._seen.add(did)
                await self.bus.publish(item)
                emitted += 1
        return emitted
