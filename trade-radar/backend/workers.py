"""Runtime wiring: providers -> bus -> alert engine.

Builds the notifier (Telegram or dry-run), the alert engine, and the Tier-0 news
providers, then runs a consumer that feeds bus events into the engine. Each
provider is isolated; a crash in one is contained by PollingProvider's loop.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from .alerts.engine import AlertEngine
from .bus import EventBus
from .config import AppConfig, Settings, get_settings, load_config
from .db import init_db
from .models import NewsItem
from .notifiers.base import Notifier
from .notifiers.telegram import TelegramNotifier
from .providers.base import Provider
from .providers.google_news import GoogleNewsProvider
from .providers.investing import InvestingProvider

log = logging.getLogger("trade_radar.runtime")


def build_notifier(settings: Settings) -> Notifier:
    return TelegramNotifier(settings.telegram_bot_token, settings.telegram_chat_id)


class Runtime:
    def __init__(self, config: Optional[AppConfig] = None, settings: Optional[Settings] = None) -> None:
        self.config = config or load_config()
        self.settings = settings or get_settings()
        self.bus = EventBus()
        self.notifier = build_notifier(self.settings)
        init_db(self.settings.db_url)
        self.engine = AlertEngine(self.config, self.notifier, db_url=self.settings.db_url)
        self.providers: list[Provider] = self._build_providers()
        self._consumer_task: Optional[asyncio.Task] = None
        self._queue = None

    def _build_providers(self) -> list[Provider]:
        news = self.config.news
        providers: list[Provider] = [
            GoogleNewsProvider(self.bus, news.google_news_queries, poll_seconds=news.poll_seconds),
            InvestingProvider(self.bus, news.investing_rss or None, poll_seconds=news.poll_seconds),
        ]
        return providers

    async def _consume(self) -> None:
        assert self._queue is not None
        async for event in self.bus.stream(self._queue):
            try:
                if isinstance(event, NewsItem):
                    await self.engine.ingest(event)
            except Exception:  # noqa: BLE001 - one bad event must not kill the loop
                log.exception("error handling event")

    async def start(self) -> None:
        self._queue = self.bus.subscribe()
        self._consumer_task = asyncio.create_task(self._consume(), name="engine-consumer")
        for p in self.providers:
            await p.start()
        log.info("runtime started: %d providers, telegram=%s", len(self.providers), self.notifier.channel)

    async def stop(self) -> None:
        for p in self.providers:
            await p.stop()
        if self._consumer_task:
            self._consumer_task.cancel()
            try:
                await self._consumer_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    def health(self) -> list[dict]:
        return [p.health.as_dict() for p in self.providers]
