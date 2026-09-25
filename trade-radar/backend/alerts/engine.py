"""The alert engine (M1 scope).

Pipeline for each NewsItem:
  1. Tag tickers (union of provider hint + alias matcher over all configured tickers).
  2. Persist the headline (per-source first_seen).
  3. Dedupe across sources (fuzzy, per ticker, within a time window).
  4. New cluster -> run the keyword fast-path against HOLDINGS. If it fires, send
     ONE alert. If a position context says the holding is up premarket/intraday or
     near a flip level, escalate to the "position at risk" combo alert.
  5. Merged cluster -> append the source to the existing alert (do NOT re-send).

LLM impact scoring and price/macro rules arrive in M2/M3; alerts here are marked
"unscored" and always send on the fast-path so nothing is missed.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Optional, Protocol

from ..config import AppConfig
from ..db import init_db, session_scope
from ..models import AlertRecord, HeadlineRecord, NewsItem
from ..notifiers.base import Notifier
from ..timeutil import format_et_kst, now_utc
from .dedupe import Cluster, Deduper
from .keywords import KeywordFastPath, TickerMatcher

log = logging.getLogger("trade_radar.engine")


class PositionContext(Protocol):
    """Supplies live position/price context (filled in by M3 price feeds).

    Returns None when no data is available (free mode / market closed)."""

    def get(self, ticker: str) -> Optional["PositionState"]: ...


@dataclass
class PositionState:
    price: Optional[float] = None
    premarket_change_pct: Optional[float] = None
    intraday_change_pct: Optional[float] = None
    near_flip: bool = False
    flip_level: Optional[float] = None

    @property
    def is_up(self) -> bool:
        for v in (self.premarket_change_pct, self.intraday_change_pct):
            if v is not None and v >= 1.0:
                return True
        return False


@dataclass
class AlertResult:
    kind: str
    ticker: str
    title: str
    body: str
    cluster_key: str
    severity: int = 0
    direction: str = "unscored"
    delivered: bool = False


class AlertEngine:
    def __init__(
        self,
        config: AppConfig,
        notifier: Notifier,
        *,
        db_url: Optional[str] = None,
        position_ctx: Optional[PositionContext] = None,
        clock: Callable[[], datetime] = now_utc,
    ) -> None:
        self.config = config
        self.notifier = notifier
        self.db_url = db_url
        self.position_ctx = position_ctx
        self.clock = clock

        # Matcher over ALL tickers (for tagging); fast-path over HOLDINGS only.
        all_terms = {t: config.aliases_for(t) for t in config.all_tickers()}
        holding_terms = {t: config.aliases_for(t) for t in config.holding_tickers()}
        self.matcher = TickerMatcher(all_terms)
        self.fastpath = KeywordFastPath(holding_terms, config.risk_keywords)

        th = config.thresholds
        self.deduper = Deduper(ratio_threshold=th.fuzzy_ratio, window_minutes=th.dedupe_window_minutes)
        self._alerts_by_cluster: dict[str, AlertResult] = {}
        self.alerts: list[AlertResult] = []

        if db_url is not None:
            init_db(db_url)

    # ------------------------------------------------------------------ #
    def _persist_headline(self, item: NewsItem, cluster: Cluster) -> None:
        if self.db_url is None:
            return
        try:
            with session_scope(self.db_url) as s:
                s.add(
                    HeadlineRecord(
                        dedupe_id=item.dedupe_id(),
                        source=item.source,
                        external_id=item.external_id,
                        headline=item.headline,
                        url=item.url,
                        summary=item.summary,
                        author=item.author,
                        tickers=",".join(item.tickers),
                        published_at=item.published_at,
                        first_seen_at=item.first_seen_at,
                        cluster_key=cluster.key,
                    )
                )
        except Exception:  # noqa: BLE001 - persistence must never crash ingest
            log.exception("failed to persist headline")

    def _persist_alert(self, res: AlertResult) -> None:
        if self.db_url is None:
            return
        try:
            with session_scope(self.db_url) as s:
                s.add(
                    AlertRecord(
                        kind=res.kind,
                        ticker=res.ticker,
                        severity=res.severity,
                        direction=res.direction,
                        title=res.title,
                        body=res.body,
                        cluster_key=res.cluster_key,
                        delivered=res.delivered,
                    )
                )
        except Exception:  # noqa: BLE001
            log.exception("failed to persist alert")

    # ------------------------------------------------------------------ #
    def _build_alert(self, item: NewsItem, cluster: Cluster, hit_keywords: list[str]) -> AlertResult:
        ticker = cluster.ticker
        state = self.position_ctx.get(ticker) if self.position_ctx else None
        flips = self.config.flip_levels_for(ticker)
        when = format_et_kst(item.published_at)

        is_combo = bool(state and (state.is_up or state.near_flip))
        prefix_bits = []
        if state and state.premarket_change_pct is not None:
            price_s = f" (${state.price:g})" if state.price is not None else ""
            prefix_bits.append(f"{ticker} {state.premarket_change_pct:+.1f}% premarket{price_s}.")
        elif state and state.intraday_change_pct is not None:
            price_s = f" (${state.price:g})" if state.price is not None else ""
            prefix_bits.append(f"{ticker} {state.intraday_change_pct:+.1f}% intraday{price_s}.")

        kw = ", ".join(hit_keywords) if hit_keywords else ""
        headline_line = f"{item.author or item.source}: {item.headline}"
        flip_line = ""
        flip_level = None
        if state and state.flip_level is not None:
            flip_level = state.flip_level
        elif flips:
            flip_level = flips[0]
        if flip_level is not None:
            flip_line = f" Flip level ${flip_level:g}."

        if is_combo:
            kind = "combo"
            title = f"{ticker} — position at risk (unscored)"
            body = (
                (prefix_bits[0] + " " if prefix_bits else "")
                + f"Bearish signal (unscored): {headline_line}."
                + " Consider protecting gains."
                + flip_line
                + f" {when}"
            )
            urgent = True
        else:
            kind = "news_fastpath"
            title = f"{ticker} — news alert (unscored)"
            body = f"{headline_line}." + (f" [{kw}]" if kw else "") + flip_line + f" {when}"
            urgent = False

        res = AlertResult(
            kind=kind, ticker=ticker, title=title, body=body,
            cluster_key=cluster.key, severity=0, direction="unscored",
        )
        res._urgent = urgent  # type: ignore[attr-defined]
        return res

    # ------------------------------------------------------------------ #
    async def ingest(self, item: NewsItem) -> Optional[AlertResult]:
        # 1. tag tickers (union provider hint + matcher)
        matched = self.matcher.match(f"{item.headline} {item.summary}")
        tickers = sorted(set(item.tickers) | set(matched))
        item.tickers = tickers

        # 3. dedupe (also persists headline with its cluster)
        cluster, is_new = self.deduper.add(item)
        self._persist_headline(item, cluster)

        if not is_new:
            # Merged: append source to the existing alert; never re-send.
            existing = self._alerts_by_cluster.get(cluster.key)
            if existing and item.source not in existing.body:
                existing.body += f"  (+{item.source})"
            log.info("merged duplicate into cluster %s from %s", cluster.key, item.source)
            return None

        # 4. fast-path over holdings
        hit = self.fastpath.evaluate(item.headline, item.summary)
        if not hit.fired:
            return None

        res = self._build_alert(item, cluster, hit.keywords)
        urgent = getattr(res, "_urgent", False)
        res.delivered = await self.notifier.send(res.title, res.body, urgent=urgent)
        self._alerts_by_cluster[cluster.key] = res
        self.alerts.append(res)
        self._persist_alert(res)
        log.info("ALERT %s %s delivered=%s", res.kind, res.ticker, res.delivered)
        return res
