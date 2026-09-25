"""Timezone conversion tests, including the US DST switch in early November.

KST has no DST, so KST - ET is +13h while the US is on EDT and +14h once the US
falls back to EST (first Sunday of November)."""

from __future__ import annotations

from datetime import datetime, timezone

from backend.timeutil import (
    et_kst_offset_hours,
    format_et_kst,
    to_et,
    to_kst,
)


def test_offset_is_13_during_us_daylight_time():
    # Sep 25 2026 13:05 UTC -> 09:05 EDT, 22:05 KST
    dt = datetime(2026, 9, 25, 13, 5, tzinfo=timezone.utc)
    assert et_kst_offset_hours(dt) == 13
    assert to_et(dt).hour == 9 and to_et(dt).minute == 5
    assert to_kst(dt).hour == 22 and to_kst(dt).minute == 5


def test_offset_is_14_after_us_falls_back_to_standard_time():
    # US DST ends Sun Nov 1 2026 02:00 local. Nov 10 is firmly EST.
    dt = datetime(2026, 11, 10, 14, 30, tzinfo=timezone.utc)
    assert et_kst_offset_hours(dt) == 14
    # 14:30 UTC -> 09:30 EST -> 23:30 KST
    assert to_et(dt).hour == 9 and to_et(dt).minute == 30
    assert to_kst(dt).hour == 23 and to_kst(dt).minute == 30


def test_dst_boundary_switches_offset():
    before = datetime(2026, 10, 31, 13, 0, tzinfo=timezone.utc)  # EDT
    after = datetime(2026, 11, 5, 13, 0, tzinfo=timezone.utc)    # EST
    assert et_kst_offset_hours(before) == 13
    assert et_kst_offset_hours(after) == 14


def test_naive_datetime_is_treated_as_utc():
    naive = datetime(2026, 9, 25, 13, 5)
    aware = datetime(2026, 9, 25, 13, 5, tzinfo=timezone.utc)
    assert to_et(naive) == to_et(aware)


def test_format_matches_spec_style():
    dt = datetime(2026, 9, 25, 13, 5, tzinfo=timezone.utc)
    s = format_et_kst(dt)
    # Spec example: "10:05pm KST / 9:05am ET" (order differs; both present)
    assert "9:05am ET" in s
    assert "10:05pm KST" in s
