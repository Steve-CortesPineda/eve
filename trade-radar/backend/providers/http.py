"""Shared HTTP fetch with an honest browser User-Agent.

Investing.com needs a normal browser UA; Google News is fine with one too. The
fetcher is injectable so providers can be unit-tested without the network.
"""

from __future__ import annotations

from typing import Awaitable, Callable

import httpx

BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

Fetcher = Callable[[str], Awaitable[str]]


async def http_get_text(url: str, *, timeout: float = 20.0) -> str:
    headers = {"User-Agent": BROWSER_UA, "Accept": "application/rss+xml, application/xml, text/xml, */*"}
    async with httpx.AsyncClient(follow_redirects=True, headers=headers) as client:
        resp = await client.get(url, timeout=timeout)
        resp.raise_for_status()
        return resp.text
