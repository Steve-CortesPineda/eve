"""Notifier interface + a capturing dry-run notifier used in free mode and tests.

Push is the most important feature, so the pipeline must run end-to-end even
with no Telegram token: in that case DryRunNotifier captures messages (and logs
them) so the same code path is exercised and testable.
"""

from __future__ import annotations

import abc
import logging
from dataclasses import dataclass, field
from datetime import datetime

from ..timeutil import now_utc

log = logging.getLogger("trade_radar.notify")


@dataclass
class SentMessage:
    title: str
    body: str
    urgent: bool
    ts: datetime = field(default_factory=now_utc)
    channel: str = "dryrun"


class Notifier(abc.ABC):
    channel: str = "base"

    @abc.abstractmethod
    async def send(self, title: str, body: str, *, urgent: bool = False) -> bool:
        ...


class DryRunNotifier(Notifier):
    channel = "dryrun"

    def __init__(self) -> None:
        self.sent: list[SentMessage] = []

    async def send(self, title: str, body: str, *, urgent: bool = False) -> bool:
        msg = SentMessage(title=title, body=body, urgent=urgent, channel=self.channel)
        self.sent.append(msg)
        log.info("[DRYRUN notify]%s %s", " URGENT" if urgent else "", title)
        return True
