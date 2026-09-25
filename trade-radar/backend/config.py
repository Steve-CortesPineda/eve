"""Configuration: non-secret settings in config.yaml, secrets in .env.

`Settings` (env/.env) holds ONLY secrets and deploy toggles. `AppConfig` (YAML)
holds the watchlist, holdings, aliases, flip levels, keyword lists, thresholds
and quiet hours. Nothing here talks to the network; adapters read these values
and light up only when the matching secret is present.
"""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path
from typing import Optional

import yaml
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = REPO_ROOT / "config.yaml"


class Settings(BaseSettings):
    """Secrets and deploy toggles. Every key is optional so the app runs in free
    mode with none of them set."""

    model_config = SettingsConfigDict(
        env_file=os.environ.get("ENV_FILE", str(REPO_ROOT / ".env")),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Push
    telegram_bot_token: Optional[str] = Field(default=None, alias="TELEGRAM_BOT_TOKEN")
    telegram_chat_id: Optional[str] = Field(default=None, alias="TELEGRAM_CHAT_ID")
    ntfy_topic: Optional[str] = Field(default=None, alias="NTFY_TOPIC")

    # LLM
    openrouter_api_key: Optional[str] = Field(default=None, alias="OPENROUTER_API_KEY")

    # Market data (Tier 0 paid-optional)
    alpaca_api_key_id: Optional[str] = Field(default=None, alias="APCA_API_KEY_ID")
    alpaca_api_secret_key: Optional[str] = Field(default=None, alias="APCA_API_SECRET_KEY")
    finnhub_api_key: Optional[str] = Field(default=None, alias="FINNHUB_API_KEY")

    # Tier 1
    unusual_whales_token: Optional[str] = Field(default=None, alias="UNUSUAL_WHALES_TOKEN")
    massive_api_key: Optional[str] = Field(default=None, alias="MASSIVE_API_KEY")

    # EDGAR requires a descriptive UA with contact email.
    edgar_user_agent: str = Field(
        default="Trade Radar personal use (set EDGAR_USER_AGENT to your email)",
        alias="EDGAR_USER_AGENT",
    )

    db_url: str = Field(default=f"sqlite:///{REPO_ROOT / 'trade_radar.db'}", alias="DB_URL")

    @property
    def telegram_enabled(self) -> bool:
        return bool(self.telegram_bot_token and self.telegram_chat_id)

    @property
    def llm_enabled(self) -> bool:
        return bool(self.openrouter_api_key)


# --------------------------------------------------------------------------- #
# YAML config models
# --------------------------------------------------------------------------- #
class Holding(BaseModel):
    ticker: str
    type: str = "shares"  # shares / call / put
    strike: Optional[float] = None
    expiry: Optional[str] = None
    qty: Optional[float] = None
    entry: Optional[float] = None


class TickerRules(BaseModel):
    aliases: list[str] = Field(default_factory=list)
    flip_levels: list[float] = Field(default_factory=list)


class GoogleQuery(BaseModel):
    query: str
    tickers: list[str] = Field(default_factory=list)


class NewsFeeds(BaseModel):
    google_news_queries: list[GoogleQuery] = Field(default_factory=list)
    investing_rss: list[str] = Field(default_factory=list)
    poll_seconds: int = 45  # jittered around this; never below 30 per the spec


class Thresholds(BaseModel):
    fuzzy_ratio: int = 85           # token-set ratio for dedupe
    dedupe_window_minutes: int = 120
    fastpath_min_severity_push: int = 3
    urgent_severity: int = 4


class QuietHours(BaseModel):
    enabled: bool = False
    start: str = "22:00"  # KST
    end: str = "07:00"    # KST
    # P0 alerts on holdings are never muted unless this is explicitly True.
    mute_holdings: bool = False


class AppConfig(BaseModel):
    watchlist: list[str] = Field(default_factory=list)
    holdings: list[Holding] = Field(default_factory=list)
    tickers: dict[str, TickerRules] = Field(default_factory=dict)
    risk_keywords: list[str] = Field(default_factory=list)
    news: NewsFeeds = Field(default_factory=NewsFeeds)
    thresholds: Thresholds = Field(default_factory=Thresholds)
    quiet_hours: QuietHours = Field(default_factory=QuietHours)

    def holding_tickers(self) -> list[str]:
        return [h.ticker.upper() for h in self.holdings]

    def all_tickers(self) -> list[str]:
        seen: list[str] = []
        for t in self.holding_tickers() + [w.upper() for w in self.watchlist]:
            if t not in seen:
                seen.append(t)
        return seen

    def aliases_for(self, ticker: str) -> list[str]:
        rules = self.tickers.get(ticker.upper()) or self.tickers.get(ticker)
        return rules.aliases if rules else []

    def flip_levels_for(self, ticker: str) -> list[float]:
        rules = self.tickers.get(ticker.upper()) or self.tickers.get(ticker)
        return rules.flip_levels if rules else []


def load_config(path: Optional[str | Path] = None) -> AppConfig:
    cfg_path = Path(path or os.environ.get("CONFIG_PATH") or DEFAULT_CONFIG)
    if not cfg_path.exists():
        return AppConfig()
    with open(cfg_path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    return AppConfig.model_validate(data)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
