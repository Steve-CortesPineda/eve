"""Timezone helpers.

The owner trades US markets from Seoul, so every user-facing time must be shown
in BOTH US Eastern (ET) and Korea Standard Time (KST). KST has no DST; ET does.
That means the ET->KST offset is +13h during US daylight saving (EDT) and +14h
outside it (EST). We never hardcode that offset -- we convert through the IANA
tz database (zoneinfo) so the DST switch is handled correctly and automatically.

Consumers: alert formatting (backend/alerts/engine.py) and the API layer.
"""

from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")
KST = ZoneInfo("Asia/Seoul")
UTC = timezone.utc


def ensure_aware(dt: datetime) -> datetime:
    """Treat a naive datetime as UTC; leave aware datetimes untouched."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt


def to_utc(dt: datetime) -> datetime:
    return ensure_aware(dt).astimezone(UTC)


def to_et(dt: datetime) -> datetime:
    return ensure_aware(dt).astimezone(ET)


def to_kst(dt: datetime) -> datetime:
    return ensure_aware(dt).astimezone(KST)


def et_kst_offset_hours(dt: datetime) -> int:
    """Whole-hour difference KST - ET at the given instant (13 in EDT, 14 in EST)."""
    dt = ensure_aware(dt)
    et_off = to_et(dt).utcoffset()
    kst_off = to_kst(dt).utcoffset()
    assert et_off is not None and kst_off is not None
    return int((kst_off - et_off).total_seconds() // 3600)


def format_et_kst(dt: datetime, *, with_date: bool = False) -> str:
    """Render an instant as e.g. '9:05am ET / 10:05pm KST'.

    This is the exact style used in alert messages in the spec.
    """
    et = to_et(dt)
    kst = to_kst(dt)
    if with_date:
        et_s = et.strftime("%a %b %-d %-I:%M%p ET").replace("AM", "am").replace("PM", "pm")
        kst_s = kst.strftime("%a %b %-d %-I:%M%p KST").replace("AM", "am").replace("PM", "pm")
    else:
        et_s = et.strftime("%-I:%M%p ET").replace("AM", "am").replace("PM", "pm")
        kst_s = kst.strftime("%-I:%M%p KST").replace("AM", "am").replace("PM", "pm")
    return f"{et_s} / {kst_s}"


def now_utc() -> datetime:
    return datetime.now(tz=UTC)
