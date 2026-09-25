#!/usr/bin/env python
"""Live smoke test of the Tier-0 news pollers (network, but NO API keys).

Polls Google News + Investing.com once through the real providers and runs the
results through the alert engine in dry-run mode. Proves the fetch+parse+pipeline
path works against the live feeds. Respects the feeds' terms (single polite poll,
honest browser UA).

    python scripts/live_smoke.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend.alerts.engine import AlertEngine
from backend.bus import EventBus
from backend.config import load_config
from backend.models import NewsItem
from backend.notifiers.base import DryRunNotifier
from backend.providers.google_news import GoogleNewsProvider
from backend.providers.investing import InvestingProvider


async def main() -> None:
    config = load_config()
    bus = EventBus()
    q = bus.subscribe()
    notifier = DryRunNotifier()
    engine = AlertEngine(config, notifier)  # no db_url -> no persistence for smoke

    google = GoogleNewsProvider(bus, config.news.google_news_queries[:2])
    investing = InvestingProvider(bus, config.news.investing_rss or None)

    print("Polling Google News (first 2 queries) + Investing.com once ...")
    g = await google.run_once()
    i = await investing.run_once()
    print(f"  google_news emitted: {g} items")
    print(f"  investing   emitted: {i} items")
    assert g + i > 0, "expected at least some items from the live feeds"

    # Drain the bus through the engine.
    alerts = 0
    sample = []
    while not q.empty():
        evt = q.get_nowait()
        if isinstance(evt, NewsItem):
            if len(sample) < 5:
                sample.append(evt)
            res = await engine.ingest(evt)
            if res:
                alerts += 1

    print(f"\nSample of live headlines parsed ({len(sample)} shown):")
    for it in sample:
        print(f"  [{it.source}] {it.published_at.isoformat()}  {it.headline[:90]}")
        if it.tickers:
            print(f"      tagged tickers: {it.tickers}")

    print(f"\nFast-path alerts fired from live data this poll: {alerts}")
    print("(zero is normal — it only fires on a holding + risk keyword.)")
    print("Feed health:")
    for h in (google.health.as_dict(), investing.health.as_dict()):
        print(f"  {h['name']}: healthy={h['healthy']} emitted={h['events_emitted']} errors={h['error_count']}")


if __name__ == "__main__":
    asyncio.run(main())
