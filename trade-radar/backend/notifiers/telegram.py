"""Telegram Bot API notifier (sendMessage, HTML parse mode).

Verified against https://core.telegram.org/bots/api#sendmessage :
  POST https://api.telegram.org/bot<token>/sendMessage
  body: {chat_id, text, parse_mode: "HTML", disable_web_page_preview}

If no token/chat_id is configured this falls back to a captured dry-run so the
alert pipeline still runs (push must never be the thing that blocks free mode).
See README for the @BotFather + chat-id walkthrough.
"""

from __future__ import annotations

import logging
from typing import Optional

import httpx

from .base import DryRunNotifier, Notifier, SentMessage

log = logging.getLogger("trade_radar.notify.telegram")

API = "https://api.telegram.org"


class TelegramNotifier(Notifier):
    channel = "telegram"

    def __init__(
        self,
        token: Optional[str],
        chat_id: Optional[str],
        *,
        client: Optional[httpx.AsyncClient] = None,
        timeout: float = 8.0,
    ) -> None:
        self.token = token
        self.chat_id = chat_id
        self._client = client
        self._timeout = timeout
        self._fallback = DryRunNotifier()
        self.sent: list[SentMessage] = self._fallback.sent

    @property
    def enabled(self) -> bool:
        return bool(self.token and self.chat_id)

    async def send(self, title: str, body: str, *, urgent: bool = False) -> bool:
        text = f"<b>{title}</b>\n{body}" if body else f"<b>{title}</b>"
        if not self.enabled:
            # Free mode: capture and log, still return True (pipeline continues).
            return await self._fallback.send(title, body, urgent=urgent)

        url = f"{API}/bot{self.token}/sendMessage"
        payload = {
            "chat_id": self.chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        try:
            if self._client is not None:
                resp = await self._client.post(url, json=payload, timeout=self._timeout)
            else:
                async with httpx.AsyncClient() as client:
                    resp = await client.post(url, json=payload, timeout=self._timeout)
            resp.raise_for_status()
            data = resp.json()
            if not data.get("ok", False):
                log.warning("telegram sendMessage not ok: %s", data)
                return False
            return True
        except Exception as exc:  # noqa: BLE001 - never let notify crash the loop
            log.warning("telegram send failed: %s", exc)
            return False
