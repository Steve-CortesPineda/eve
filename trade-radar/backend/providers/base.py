"""Provider adapter pattern.

Every data source implements this interface and is isolated: one crashing or
erroring feed must never take down the others. `PollingProvider` adds a jittered
poll loop with exponential backoff and a health record the dashboard can read.

Providers emit normalized events (backend/models.py) onto the EventBus.
"""

from __future__ import annotations

import abc
import asyncio
import logging
import random
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from ..bus import EventBus
from ..timeutil import now_utc

log = logging.getLogger("trade_radar.providers")


@dataclass
class Health:
    name: str
    enabled: bool = True
    last_ok: Optional[datetime] = None
    last_error: Optional[str] = None
    error_count: int = 0
    events_emitted: int = 0

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "enabled": self.enabled,
            "last_ok": self.last_ok.isoformat() if self.last_ok else None,
            "last_error": self.last_error,
            "error_count": self.error_count,
            "events_emitted": self.events_emitted,
            "healthy": self.enabled and self.error_count < 5,
        }


class Provider(abc.ABC):
    name: str = "provider"

    def __init__(self, bus: EventBus) -> None:
        self.bus = bus
        self.health = Health(name=self.name)
        self._task: Optional[asyncio.Task] = None
        self._stopped = asyncio.Event()

    @abc.abstractmethod
    async def run_once(self) -> int:
        """Do one unit of work (e.g. one poll). Return number of events emitted."""

    async def start(self) -> None:
        self._stopped.clear()
        self._task = asyncio.create_task(self._loop(), name=f"provider:{self.name}")

    async def stop(self) -> None:
        self._stopped.set()
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    async def _loop(self) -> None:  # pragma: no cover - exercised via integration
        raise NotImplementedError


class PollingProvider(Provider):
    """A provider that polls on an interval with jitter + exponential backoff.

    The spec requires RSS polling no faster than every 30s per feed, so the
    effective interval is clamped to >= 30s.
    """

    def __init__(self, bus: EventBus, poll_seconds: int = 45) -> None:
        super().__init__(bus)
        self.poll_seconds = max(30, int(poll_seconds))
        self._backoff = 0

    async def _loop(self) -> None:  # pragma: no cover - timing loop
        while not self._stopped.is_set():
            try:
                emitted = await self.run_once()
                self.health.last_ok = now_utc()
                self.health.error_count = 0
                self.health.events_emitted += emitted
                self._backoff = 0
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - isolate every feed
                self.health.last_error = f"{type(exc).__name__}: {exc}"
                self.health.error_count += 1
                self._backoff = min(self._backoff + 1, 6)
                log.warning("provider %s error: %s", self.name, exc)

            delay = self._next_delay()
            try:
                await asyncio.wait_for(self._stopped.wait(), timeout=delay)
            except asyncio.TimeoutError:
                pass

    def _next_delay(self) -> float:
        base = self.poll_seconds
        if self._backoff:
            base = min(self.poll_seconds * (2 ** self._backoff), 900)
        jitter = random.uniform(0, min(15, base * 0.25))
        return base + jitter
