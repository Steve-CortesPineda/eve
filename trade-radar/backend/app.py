"""FastAPI application (M1).

Exposes health, recent news, and recent alerts, and starts the runtime (news
pollers + alert engine) on startup. Read-only: there are no order endpoints and
never will be. The dashboard (M4) will consume /ws for live updates.
"""

from __future__ import annotations

import contextlib
import logging
from datetime import datetime

from fastapi import FastAPI
from sqlmodel import select

from .config import get_settings, load_config
from .db import session_scope
from .models import AlertRecord, HeadlineRecord
from .timeutil import format_et_kst, now_utc
from .workers import Runtime

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("trade_radar.app")


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    runtime = Runtime()
    app.state.runtime = runtime
    await runtime.start()
    try:
        yield
    finally:
        await runtime.stop()


app = FastAPI(title="Trade Radar", version="0.1.0", lifespan=lifespan)


@app.get("/")
def root() -> dict:
    settings = get_settings()
    return {
        "app": "Trade Radar",
        "mode": "live-keys" if settings.telegram_enabled else "free (dry-run notifications)",
        "read_only": True,
        "disclaimer": "Personal tool. Not financial advice.",
    }


@app.get("/health")
def health() -> dict:
    runtime: Runtime = app.state.runtime
    now = now_utc()
    return {
        "now": {"utc": now.isoformat(), "et_kst": format_et_kst(now, with_date=True)},
        "telegram_enabled": get_settings().telegram_enabled,
        "feeds": runtime.health(),
    }


@app.get("/api/news")
def recent_news(limit: int = 50) -> list[dict]:
    settings = get_settings()
    out: list[dict] = []
    with session_scope(settings.db_url) as s:
        rows = s.exec(
            select(HeadlineRecord).order_by(HeadlineRecord.first_seen_at.desc()).limit(limit)
        ).all()
        for r in rows:
            out.append(
                {
                    "source": r.source,
                    "headline": r.headline,
                    "url": r.url,
                    "tickers": r.tickers,
                    "published_at": r.published_at.isoformat() if isinstance(r.published_at, datetime) else r.published_at,
                    "first_seen_at": r.first_seen_at.isoformat() if isinstance(r.first_seen_at, datetime) else r.first_seen_at,
                    "cluster_key": r.cluster_key,
                }
            )
    return out


@app.get("/api/alerts")
def recent_alerts(limit: int = 50) -> list[dict]:
    settings = get_settings()
    out: list[dict] = []
    with session_scope(settings.db_url) as s:
        rows = s.exec(
            select(AlertRecord).order_by(AlertRecord.created_at.desc()).limit(limit)
        ).all()
        for r in rows:
            out.append(
                {
                    "id": r.id,
                    "kind": r.kind,
                    "ticker": r.ticker,
                    "severity": r.severity,
                    "direction": r.direction,
                    "title": r.title,
                    "body": r.body,
                    "acknowledged": r.acknowledged,
                    "delivered": r.delivered,
                    "created_at": r.created_at.isoformat() if isinstance(r.created_at, datetime) else r.created_at,
                }
            )
    return out
