"""A tiny in-process async event bus.

Providers publish normalized events; the alert engine and the websocket layer
subscribe. Each subscriber gets its own bounded queue, so a slow consumer can
never block a fast producer (it drops oldest on overflow and logs it). One
crashing consumer must never take down the producers.

Producers: backend/providers/*   Consumers: backend/alerts/engine.py, API/WS.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, AsyncIterator

log = logging.getLogger("trade_radar.bus")


class EventBus:
    def __init__(self, maxsize: int = 1000) -> None:
        self._subscribers: list[asyncio.Queue] = []
        self._maxsize = maxsize

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=self._maxsize)
        self._subscribers.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        if q in self._subscribers:
            self._subscribers.remove(q)

    async def publish(self, event: Any) -> None:
        for q in list(self._subscribers):
            try:
                q.put_nowait(event)
            except asyncio.QueueFull:
                # Drop the oldest to make room; alerts must keep flowing.
                try:
                    _ = q.get_nowait()
                    q.put_nowait(event)
                    log.warning("bus subscriber queue full; dropped oldest event")
                except Exception:  # pragma: no cover - defensive
                    log.exception("failed to enqueue event after overflow")

    async def stream(self, q: asyncio.Queue) -> AsyncIterator[Any]:
        while True:
            yield await q.get()
