"""Pure RSS parsing helpers (no network, fully unit-testable).

Two feed shapes are supported, both verified against the live feeds:

Google News RSS (https://news.google.com/rss/search?q=...):
  <item><title>Headline - Source</title><link/><guid/>
        <pubDate>Thu, 24 Sep 2026 16:30:00 GMT</pubDate>
        <description>..html..</description><source url="...">Source</source></item>
  pubDate is RFC-822 in GMT.

Investing.com RSS (https://www.investing.com/rss/news_25.rss):
  <item><title/><pubDate>2026-09-25 15:50:00</pubDate><author/><link/></item>
  pubDate is 'YYYY-MM-DD HH:MM:SS' in GMT (naive -> treat as UTC).
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Optional
from xml.etree import ElementTree as ET

from dateutil import parser as dtparser

from ..models import NewsItem
from ..timeutil import UTC

_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


def _text(el: Optional[ET.Element]) -> str:
    if el is None or el.text is None:
        return ""
    return el.text.strip()


def strip_html(s: str) -> str:
    return _WS_RE.sub(" ", _TAG_RE.sub(" ", s or "")).strip()


def parse_rfc822_gmt(raw: str) -> Optional[datetime]:
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        dt = dtparser.parse(raw)
    except (ValueError, OverflowError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def parse_investing_ts(raw: str) -> Optional[datetime]:
    """'YYYY-MM-DD HH:MM:SS' in GMT -> aware UTC datetime."""
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        dt = datetime.strptime(raw, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        # Fall back to a lenient parse; still treat naive as UTC.
        parsed = parse_rfc822_gmt(raw)
        return parsed
    return dt.replace(tzinfo=UTC)


def split_google_title(title: str) -> tuple[str, str]:
    """Google titles are 'Headline - Source'. Split on the LAST ' - '."""
    if " - " in title:
        head, _, source = title.rpartition(" - ")
        return head.strip(), source.strip()
    return title.strip(), ""


def _iter_items(xml_bytes: bytes | str) -> list[ET.Element]:
    if isinstance(xml_bytes, str):
        xml_bytes = xml_bytes.encode("utf-8")
    root = ET.fromstring(xml_bytes)
    # Works for both <rss><channel><item> and namespaced variants.
    return root.findall(".//item")


def parse_google_news(xml_bytes: bytes | str, default_tickers: list[str] | None = None) -> list[NewsItem]:
    items: list[NewsItem] = []
    for it in _iter_items(xml_bytes):
        raw_title = _text(it.find("title"))
        if not raw_title:
            continue
        headline, src_name = split_google_title(raw_title)
        guid = _text(it.find("guid")) or _text(it.find("link")) or raw_title
        link = _text(it.find("link"))
        pub = parse_rfc822_gmt(_text(it.find("pubDate")))
        source_el = it.find("source")
        source_name = _text(source_el) or src_name or "Google News"
        summary = strip_html(_text(it.find("description")))
        items.append(
            NewsItem(
                source="google_news",
                external_id=guid,
                headline=headline,
                url=link,
                summary=summary,
                author=source_name,
                tickers=list(default_tickers or []),
                published_at=pub or datetime.now(tz=UTC),
            )
        )
    return items


def parse_investing(xml_bytes: bytes | str, default_tickers: list[str] | None = None) -> list[NewsItem]:
    items: list[NewsItem] = []
    for it in _iter_items(xml_bytes):
        headline = _text(it.find("title"))
        if not headline:
            continue
        link = _text(it.find("link"))
        guid = _text(it.find("guid")) or link or headline
        pub = parse_investing_ts(_text(it.find("pubDate")))
        author = _text(it.find("author")) or "Investing.com"
        items.append(
            NewsItem(
                source="investing",
                external_id=guid,
                headline=headline,
                url=link,
                summary="",
                author=author,
                tickers=list(default_tickers or []),
                published_at=pub or datetime.now(tz=UTC),
            )
        )
    return items
