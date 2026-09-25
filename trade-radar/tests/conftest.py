from __future__ import annotations

from pathlib import Path

import pytest

from backend.config import (
    AppConfig,
    GoogleQuery,
    Holding,
    NewsFeeds,
    TickerRules,
    Thresholds,
)

FIXTURES = Path(__file__).parent / "fixtures"


def load_fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


@pytest.fixture
def sample_config() -> AppConfig:
    """A realistic config mirroring the spec's holdings (TSLA/GOOGL)."""
    return AppConfig(
        watchlist=["NQ", "ES", "VIX"],
        holdings=[
            Holding(ticker="TSLA", type="shares", qty=100, entry=372.0),
            Holding(ticker="GOOGL", type="shares", qty=50, entry=168.0),
        ],
        tickers={
            "TSLA": TickerRules(
                aliases=["Tesla", "Musk", "Optimus", "FSD", "Full Self-Driving", "Robotaxi"],
                flip_levels=[375.70],
            ),
            "GOOGL": TickerRules(
                aliases=["Alphabet", "Google", "Gemini", "Waymo"],
                flip_levels=[168.0],
            ),
            "NQ": TickerRules(aliases=["Nasdaq"]),
        },
        risk_keywords=[
            "report says", "The Information", "delay", "snag", "probe",
            "investigation", "recall", "NHTSA", "SEC", "EU", "downgrade",
            "lawsuit", "misses", "warns",
        ],
        news=NewsFeeds(
            google_news_queries=[GoogleQuery(query="Tesla OR TSLA", tickers=["TSLA"])],
            investing_rss=["https://www.investing.com/rss/news_25.rss"],
            poll_seconds=45,
        ),
        thresholds=Thresholds(fuzzy_ratio=85, dedupe_window_minutes=120),
    )


@pytest.fixture
def temp_db(tmp_path) -> str:
    return f"sqlite:///{tmp_path / 'test.db'}"
