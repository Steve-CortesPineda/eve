"""Cross-source dedupe tests."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from backend.alerts.dedupe import Deduper, normalize_title
from backend.models import NewsItem

T0 = datetime(2026, 9, 25, 13, 5, tzinfo=timezone.utc)


def _item(source, headline, tickers, minutes=0, ext=None):
    return NewsItem(
        source=source,
        external_id=ext or f"{source}-{headline[:10]}",
        headline=headline,
        tickers=tickers,
        published_at=T0 + timedelta(minutes=minutes),
        first_seen_at=T0 + timedelta(minutes=minutes),
    )


def test_normalize_strips_punct_and_stopwords():
    assert normalize_title("Tesla's Optimus Hits Snags!") == "teslas optimus hits snags"


def test_near_duplicate_same_ticker_within_window_merges():
    d = Deduper(ratio_threshold=85, window_minutes=120)
    a = _item("google_news", "Tesla's Optimus Hits Snags in Hands, Suppliers as Scale-Up Begins", ["TSLA"])
    b = _item("investing", "Tesla Optimus hits snags in hands and suppliers as scale-up begins", ["TSLA"], minutes=10)

    c1, new1 = d.add(a)
    c2, new2 = d.add(b)

    assert new1 is True
    assert new2 is False  # merged, not a new alert
    assert c1.key == c2.key
    assert set(c1.sources) == {"google_news", "investing"}


def test_different_tickers_do_not_merge():
    d = Deduper()
    a = _item("google_news", "Company reports a delay in shipments", ["TSLA"])
    b = _item("investing", "Company reports a delay in shipments", ["GOOGL"], minutes=5)
    _, new1 = d.add(a)
    _, new2 = d.add(b)
    assert new1 and new2  # both new -> two alerts


def test_outside_window_does_not_merge():
    d = Deduper(window_minutes=120)
    a = _item("google_news", "Tesla Optimus hits snags in hands and suppliers", ["TSLA"])
    b = _item("investing", "Tesla Optimus hits snags in hands and suppliers", ["TSLA"], minutes=200)
    _, new1 = d.add(a)
    _, new2 = d.add(b)
    assert new1 and new2


def test_unrelated_headlines_same_ticker_do_not_merge():
    d = Deduper(ratio_threshold=85)
    a = _item("google_news", "Tesla Optimus hits snags in hands and suppliers", ["TSLA"])
    b = _item("investing", "Tesla opens new gigafactory in India with record output", ["TSLA"], minutes=5)
    _, new1 = d.add(a)
    _, new2 = d.add(b)
    assert new1 and new2


def test_fastest_source_is_tracked():
    d = Deduper()
    a = _item("google_news", "Tesla Optimus hits snags in hands and suppliers", ["TSLA"], minutes=0)
    b = _item("investing", "Tesla Optimus hits snags in hands and suppliers", ["TSLA"], minutes=10)
    c, _ = d.add(a)
    d.add(b)
    fastest = c.fastest_source()
    assert fastest is not None and fastest[0] == "google_news"
