"""Ticker matching + keyword fast-path tests."""

from __future__ import annotations

from backend.alerts.keywords import KeywordFastPath, TickerMatcher

HOLDINGS = {
    "TSLA": ["Tesla", "Musk", "Optimus", "FSD", "Full Self-Driving"],
    "GOOGL": ["Alphabet", "Google", "Waymo"],
}
RISK = ["report says", "The Information", "delay", "snag", "probe", "EU", "SEC", "recall"]


def test_matcher_finds_ticker_by_alias():
    m = TickerMatcher(HOLDINGS)
    assert m.match("Tesla's Optimus hits snags") == ["TSLA"]
    assert m.match("Waymo expands in Austin") == ["GOOGL"]
    assert m.match("Nothing relevant here") == []


def test_matcher_is_word_boundary_aware():
    m = TickerMatcher({"ES": ["ES"], "TSLA": ["Tesla"]})
    # 'ES' must not match inside 'shares' or 'business'
    assert m.match("the business shares fell") == []
    assert m.match("ES futures slipped") == ["ES"]


def test_multiword_alias_matches():
    m = TickerMatcher(HOLDINGS)
    assert m.match("EU approves Full Self-Driving rollout") == ["TSLA"]


def test_fastpath_fires_on_holding_plus_keyword():
    fp = KeywordFastPath(HOLDINGS, RISK)
    hit = fp.evaluate("Tesla's Optimus Hits Snags as Scale-Up Begins", "The Information report")
    assert hit.fired
    assert "TSLA" in hit.tickers
    assert "snag" in hit.keywords or "the information" in hit.keywords


def test_fastpath_does_not_fire_without_keyword():
    fp = KeywordFastPath(HOLDINGS, RISK)
    hit = fp.evaluate("Tesla stock rises on strong delivery numbers")
    assert not hit.fired
    assert hit.tickers == ["TSLA"]
    assert hit.keywords == []


def test_fastpath_does_not_fire_without_holding():
    fp = KeywordFastPath(HOLDINGS, RISK)
    hit = fp.evaluate("SEC opens probe into an unrelated small-cap company")
    assert not hit.fired


def test_eu_keyword_boundary_not_matching_substring():
    fp = KeywordFastPath(HOLDINGS, RISK)
    # 'EU' must not match inside 'euro'; this headline has a holding but the only
    # near-keyword is 'euro', so the fast-path must NOT fire.
    hit = fp.evaluate("Tesla euro-zone deliveries climb in the quarter")
    assert not hit.fired
