#!/usr/bin/env python
"""Offline end-to-end demo of the Sep 25 scenario — no API keys, no network.

Runs the real pipeline (parse -> tag -> dedupe -> keyword fast-path -> combo
alert -> dry-run Telegram) over the bundled fixtures and prints the alerts that
WOULD be pushed to your phone. This is exactly what M1 does live; only the feed
source and the notifier's delivery differ once keys are added.

    python scripts/demo_offline.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend.alerts.engine import AlertEngine, PositionState
from backend.config import (
    AppConfig,
    GoogleQuery,
    Holding,
    NewsFeeds,
    Thresholds,
    TickerRules,
)
from backend.notifiers.base import DryRunNotifier
from backend.providers.rss_common import parse_google_news, parse_investing

FIX = Path(__file__).resolve().parent.parent / "tests" / "fixtures"


class DemoPositions:
    def get(self, ticker: str):
        if ticker == "TSLA":
            return PositionState(price=384.0, premarket_change_pct=1.6, near_flip=True, flip_level=375.70)
        return None


def demo_config() -> AppConfig:
    return AppConfig(
        watchlist=["NQ", "ES"],
        holdings=[Holding(ticker="TSLA", type="shares", qty=100, entry=372.0),
                  Holding(ticker="GOOGL", type="shares", qty=50, entry=168.0)],
        tickers={
            "TSLA": TickerRules(
                aliases=["Tesla", "Musk", "Optimus", "FSD", "Full Self-Driving", "Robotaxi"],
                flip_levels=[375.70],
            ),
            "GOOGL": TickerRules(aliases=["Alphabet", "Google", "Waymo"], flip_levels=[168.0]),
        },
        risk_keywords=["The Information", "snag", "delay", "EU", "SEC", "probe", "recall", "downgrade"],
        news=NewsFeeds(google_news_queries=[GoogleQuery(query="Tesla OR TSLA", tickers=["TSLA"])]),
        thresholds=Thresholds(fuzzy_ratio=85, dedupe_window_minutes=120),
    )


async def main() -> None:
    notifier = DryRunNotifier()
    engine = AlertEngine(demo_config(), notifier, position_ctx=DemoPositions())

    steps = [
        ("09:05 ET  Google News / The Information", parse_google_news((FIX / "google_news_optimus.xml").read_text(), ["TSLA"])),
        ("09:15 ET  Investing.com (relay, duplicate)", parse_investing((FIX / "investing_optimus_relay.xml").read_text())),
        ("09:21 ET  Investing.com (EU/FSD delay)", parse_investing((FIX / "investing_fsd_delay.xml").read_text())),
        ("08:30 ET  Google News (benign opinion)", parse_google_news((FIX / "google_news_benign.xml").read_text(), ["TSLA"])),
    ]

    print("=" * 72)
    print(" Trade Radar — offline replay of the Fri Sep 25 2026 TSLA scenario")
    print(" (free mode: notifications are DRY-RUN; no keys, no network)")
    print("=" * 72)
    for label, items in steps:
        for it in items:
            it.first_seen_at = it.published_at
            res = await engine.ingest(it)
            verdict = "ALERT SENT" if res else "no alert (merged/benign)"
            print(f"\n> {label}\n  headline: {it.headline}\n  -> {verdict}")
            if res:
                print(f"     [{'URGENT ' if res.kind == 'combo' else ''}{res.kind}] {res.title}")
                print(f"     {res.body}")

    print("\n" + "-" * 72)
    print(f"Total pushes that would hit your phone: {len(notifier.sent)}")
    print("Expected: 2 (the Optimus combo alert + the EU/FSD alert).")
    print("The 09:15 duplicate was merged (not re-sent); the benign item did not alert.")


if __name__ == "__main__":
    asyncio.run(main())
