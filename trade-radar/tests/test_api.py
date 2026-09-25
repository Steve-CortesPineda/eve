"""API-layer tests: read-only contract + DB serialization (no network)."""

from __future__ import annotations

from datetime import datetime, timezone

import backend.app as appmod
from backend.config import get_settings
from backend.db import init_db, session_scope
from backend.models import AlertRecord, HeadlineRecord


def _seed(db_url: str) -> None:
    init_db(db_url)
    with session_scope(db_url) as s:
        s.add(HeadlineRecord(
            dedupe_id="google_news:x1", source="google_news", external_id="x1",
            headline="Tesla's Optimus Hits Snags", url="http://x", tickers="TSLA",
            published_at=datetime(2026, 9, 25, 13, 5, tzinfo=timezone.utc),
            cluster_key="TSLA:optimus",
        ))
        s.add(AlertRecord(
            kind="combo", ticker="TSLA", severity=0, direction="unscored",
            title="TSLA — position at risk (unscored)", body="...", cluster_key="TSLA:optimus",
            delivered=True,
        ))


def test_root_declares_read_only():
    body = appmod.root()
    assert body["read_only"] is True
    assert "not financial advice" in body["disclaimer"].lower()


def test_news_and_alerts_endpoints_serialize(tmp_path, monkeypatch):
    db_url = f"sqlite:///{tmp_path / 'api.db'}"
    monkeypatch.setenv("DB_URL", db_url)
    get_settings.cache_clear()
    _seed(db_url)

    news = appmod.recent_news(limit=10)
    alerts = appmod.recent_alerts(limit=10)

    assert len(news) == 1
    assert news[0]["source"] == "google_news"
    assert news[0]["tickers"] == "TSLA"

    assert len(alerts) == 1
    assert alerts[0]["kind"] == "combo"
    assert alerts[0]["delivered"] is True

    get_settings.cache_clear()
