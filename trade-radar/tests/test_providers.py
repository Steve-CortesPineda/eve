"""RSS parsing + provider polling tests (no network; injected fetcher)."""

from __future__ import annotations

from datetime import timezone

import pytest

from backend.bus import EventBus
from backend.config import GoogleQuery
from backend.models import NewsItem
from backend.providers.google_news import GoogleNewsProvider, build_url
from backend.providers.investing import InvestingProvider
from backend.providers.rss_common import (
    parse_google_news,
    parse_investing,
    parse_investing_ts,
    parse_rfc822_gmt,
    split_google_title,
)

from .conftest import load_fixture


def test_split_google_title():
    assert split_google_title("Headline here - The Source") == ("Headline here", "The Source")
    assert split_google_title("No source") == ("No source", "")


def test_parse_rfc822_is_utc():
    dt = parse_rfc822_gmt("Fri, 25 Sep 2026 13:05:00 GMT")
    assert dt is not None
    assert dt.tzinfo is not None
    assert dt.astimezone(timezone.utc).hour == 13


def test_parse_investing_ts_treats_naive_as_utc():
    dt = parse_investing_ts("2026-09-25 13:15:00")
    assert dt is not None and dt.tzinfo == timezone.utc
    assert dt.hour == 13 and dt.minute == 15


def test_parse_google_news_fixture():
    items = parse_google_news(load_fixture("google_news_optimus.xml"), default_tickers=["TSLA"])
    assert len(items) == 1
    it = items[0]
    assert it.source == "google_news"
    assert it.headline == "Tesla's Optimus Hits Snags in Hands, Suppliers as Scale-Up Begins"
    assert it.author == "The Information"
    assert it.tickers == ["TSLA"]
    assert it.published_at.astimezone(timezone.utc).hour == 13


def test_parse_investing_fixture():
    items = parse_investing(load_fixture("investing_optimus_relay.xml"))
    assert len(items) == 1
    it = items[0]
    assert it.source == "investing"
    assert "Optimus" in it.headline
    assert it.published_at.minute == 15


async def test_google_provider_publishes_new_and_dedupes_across_polls():
    bus = EventBus()
    q = bus.subscribe()
    xml = load_fixture("google_news_optimus.xml")

    async def fake_fetch(url: str) -> str:
        assert "news.google.com" in url
        return xml

    p = GoogleNewsProvider(bus, [GoogleQuery(query="Tesla OR TSLA", tickers=["TSLA"])], fetcher=fake_fetch)

    n1 = await p.run_once()
    assert n1 == 1
    evt = q.get_nowait()
    assert isinstance(evt, NewsItem) and evt.tickers == ["TSLA"]

    # Second poll returns the same feed -> nothing new emitted.
    n2 = await p.run_once()
    assert n2 == 0
    assert q.empty()


async def test_investing_provider_uses_injected_fetcher():
    bus = EventBus()
    q = bus.subscribe()
    xml = load_fixture("investing_fsd_delay.xml")

    async def fake_fetch(url: str) -> str:
        return xml

    p = InvestingProvider(bus, ["https://example/rss"], fetcher=fake_fetch)
    n = await p.run_once()
    assert n == 1
    evt = q.get_nowait()
    assert "Full Self-Driving" in evt.headline


def test_build_url_encodes_query():
    url = build_url("Tesla OR TSLA")
    assert "q=Tesla%20OR%20TSLA" in url
    assert "ceid=US:en" in url
