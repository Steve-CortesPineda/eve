"""Replay of the Fri Sep 25 2026 TSLA scenario (the failure this app must prevent).

Timeline (ET = EDT = UTC-4 in September):
  09:05 ET (13:05 GMT)  The Information: "Optimus Hits Snags..."   (via Google News)
  09:15 ET (13:15 GMT)  Investing.com relays the SAME story         (duplicate)
  09:21 ET (13:21 GMT)  Investing.com: "EU vote on FSD delayed..."  (distinct story)
TSLA is +1.6% premarket (~$384), flip level $375.70.

Asserts:
  * a "position at risk" (combo) alert fires off the 09:05 item, by 09:06 ET;
  * the 09:15 Investing.com duplicate is MERGED, not re-sent;
  * the distinct 09:21 story produces its own alert.
"""

from __future__ import annotations

from datetime import time, timezone

import pytest
from sqlmodel import select

from backend.alerts.engine import AlertEngine, PositionState
from backend.db import session_scope
from backend.models import AlertRecord, HeadlineRecord, NewsItem
from backend.notifiers.base import DryRunNotifier
from backend.providers.rss_common import parse_google_news, parse_investing
from backend.timeutil import to_et

from .conftest import load_fixture


class FakePositions:
    """TSLA is up premarket and near its flip level (the Sep 25 setup)."""

    def get(self, ticker: str):
        if ticker == "TSLA":
            return PositionState(price=384.0, premarket_change_pct=1.6, near_flip=True, flip_level=375.70)
        return None


def _one(items: list[NewsItem]) -> NewsItem:
    assert len(items) == 1
    it = items[0]
    it.first_seen_at = it.published_at  # deterministic for the replay
    return it


@pytest.fixture
def engine(sample_config, temp_db):
    return AlertEngine(
        sample_config,
        DryRunNotifier(),
        db_url=temp_db,
        position_ctx=FakePositions(),
    )


async def test_position_at_risk_fires_by_0906_and_duplicate_is_merged(engine):
    notifier: DryRunNotifier = engine.notifier  # type: ignore[assignment]

    # 09:05 ET — The Information via Google News
    optimus = _one(parse_google_news(load_fixture("google_news_optimus.xml"), default_tickers=["TSLA"]))
    res = await engine.ingest(optimus)

    assert res is not None, "an alert must fire off the 09:05 item"
    assert res.kind == "combo", "should escalate to the position-at-risk combo alert"
    assert res.ticker == "TSLA"
    assert res.delivered is True
    assert "position at risk" in res.title.lower()
    assert "premarket" in res.body.lower()
    assert "375.7" in res.body  # flip level surfaced
    # ...and it is anchored to 09:05 ET, i.e. by 09:06 ET.
    assert to_et(optimus.published_at).timetz().replace(tzinfo=None) <= time(9, 6)
    assert len(notifier.sent) == 1

    # 09:15 ET — Investing.com relays the SAME story: must merge, not re-send.
    relay = _one(parse_investing(load_fixture("investing_optimus_relay.xml")))
    res2 = await engine.ingest(relay)
    assert res2 is None, "the duplicate must be merged, not re-alerted"
    assert len(notifier.sent) == 1, "no second push for the duplicate"

    # The merged cluster now carries BOTH sources (fastest-source latency stats).
    cluster = engine.deduper._clusters[0]
    assert set(cluster.sources) == {"google_news", "investing"}
    assert cluster.fastest_source()[0] == "google_news"

    # 09:21 ET — distinct EU/FSD story: its own alert.
    fsd = _one(parse_investing(load_fixture("investing_fsd_delay.xml")))
    res3 = await engine.ingest(fsd)
    assert res3 is not None, "a distinct story must fire its own alert"
    assert len(notifier.sent) == 2


async def test_replay_persists_headlines_and_alerts(engine, temp_db):
    for loader, parser, kw in [
        ("google_news_optimus.xml", parse_google_news, {"default_tickers": ["TSLA"]}),
        ("investing_optimus_relay.xml", parse_investing, {}),
        ("investing_fsd_delay.xml", parse_investing, {}),
    ]:
        item = _one(parser(load_fixture(loader), **kw))
        await engine.ingest(item)

    with session_scope(temp_db) as s:
        headlines = s.exec(select(HeadlineRecord)).all()
        alerts = s.exec(select(AlertRecord)).all()
        n_headlines = len(headlines)
        n_alerts = len(alerts)
        kinds = {a.kind for a in alerts}
        sources = {h.source for h in headlines}

    assert n_headlines == 3, "every headline is stored with per-source first_seen"
    assert sources == {"google_news", "investing"}
    # Two distinct stories (Optimus cluster + EU/FSD cluster) -> two alerts.
    assert n_alerts == 2
    assert "combo" in kinds


async def test_benign_headline_does_not_alert(engine):
    notifier: DryRunNotifier = engine.notifier  # type: ignore[assignment]
    benign = _one(parse_google_news(load_fixture("google_news_benign.xml"), default_tickers=["TSLA"]))
    res = await engine.ingest(benign)
    assert res is None, "a benign TSLA headline with no risk keyword must not alert"
    assert len(notifier.sent) == 0
