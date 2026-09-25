# Trade Radar

A personal, **read-only** trading news + alert system. It watches your holdings
and watchlist across free news feeds, and pushes a phone alert (Telegram) within
seconds when something market-moving shows up — with a plain-English "what it
means for your position" line.

> **Disclaimer:** This is a personal tool, **not financial advice**. It never
> places, modifies, or cancels orders, and it never will. It only reads public
> data and sends you alerts. Delayed data is always labeled; missing values show
> as `—`; numbers are never invented.

This repository currently implements **Milestone 1 (M1): alerts-first**. It runs
with **zero API keys** ("free mode") — notifications become dry-run (captured +
logged) until you add a Telegram bot token.

---

## What M1 does

- Polls **Google News RSS** (one query per holding/alias) and **Investing.com
  RSS** every ~45s (jittered, never faster than 30s/feed).
- Normalizes every headline, tags tickers by alias, and stores it in SQLite with
  a per-source `first_seen` (so you can later see which feed was fastest).
- **Dedupes across sources** (fuzzy token-set match ≥85 within a 2h window per
  ticker): one alert per story, later sources merged in — never re-sent.
- **Keyword fast-path**: a fresh item mentioning a holding (or alias) *and* a
  risk keyword fires immediately, with no LLM in the path.
- **"Position at risk" combo alert**: when a bearish-signal item hits a holding
  that is up premarket/intraday or near a flip level (price context arrives in
  M3; the engine already supports it and the Sep 25 replay test exercises it).
- Serves a small read-only API: `/health`, `/api/news`, `/api/alerts`.

LLM impact scoring, the Alpaca news stream, live quotes/price rules, the Next.js
dashboard, the economic calendar, and the Tier-1 paid adapters are M2–M7.

---

## Architecture

```
providers/ (Google News, Investing.com)  --NewsItem-->  bus  -->  AlertEngine
                                                                     |
                                        dedupe + keyword fast-path + combo
                                                                     |
                                              Telegram (or dry-run) + SQLite
```

- **Provider adapter pattern**: every source implements `start/stop/health/run_once`
  and is isolated — one crashing/erroring feed can never take down the others
  (`PollingProvider` adds jitter + exponential backoff).
- **Free by default**: paid adapters exist behind their keys and stay disabled
  until the key is present.

---

## Quick start (free mode, no keys)

Requires Python 3.12.

```sh
cd trade-radar
make setup           # create .venv and install deps
make test            # run the full test suite (offline, no keys)
make demo            # offline replay of the Sep 25 2026 TSLA scenario
make dev             # start the API on http://127.0.0.1:8000
```

Then:

```sh
curl -s localhost:8000/health | python3 -m json.tool
curl -s localhost:8000/api/alerts | python3 -m json.tool
```

`make live-smoke` polls the real feeds once (network, still no keys) and prints
what it parsed.

---

## Telegram setup (turns dry-run into real phone alerts)

1. In Telegram, open **@BotFather** → send `/newbot` → choose a name and a
   username ending in `bot`. BotFather replies with a **bot token** like
   `123456789:AA...`. That is your `TELEGRAM_BOT_TOKEN`.
2. Send any message to your new bot (tap Start), so it is allowed to message you.
3. Find your **chat id**: open
   `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates` in a browser and read
   `result[].message.chat.id`. (Alternatively, message **@userinfobot**.) That
   number is your `TELEGRAM_CHAT_ID`.
4. Copy `.env.example` to `.env` and fill both values:
   ```sh
   cp .env.example .env
   # edit TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
   ```
5. Restart `make dev`. `/health` will now show `telegram_enabled: true` and
   alerts will be delivered to your phone.

---

## Accounts / keys checklist

All optional for M1; each unlocks more as later milestones land.

- **Telegram bot** — @BotFather (above). *(enables real push now)*
- **Alpaca** paper account (free, global): https://app.alpaca.markets *(M2 news stream, M3 quotes)*
- **Finnhub** free key: https://finnhub.io *(M3 quotes backup)*
- **OpenRouter** key: https://openrouter.ai/keys *(M2 LLM scoring + daily brief)*
- Optional / paid (M6):
  - Unusual Whales API trial: https://unusualwhales.com/public-api
  - Massive (Benzinga News): https://massive.com/partners/benzinga
  - tastytrade developer (read-only): https://developer.tastytrade.com

Put everything in `.env` (never commit it). See `.env.example`.

---

## Configuration

Non-secret settings live in `config.yaml`: your watchlist, holdings (ticker,
type, strike, expiry, qty, entry), per-ticker aliases and flip levels, the risk
keyword list, feed lists + poll interval, dedupe thresholds, and quiet hours.
Edit it to match your book.

---

## Testing

```sh
make test          # pytest: dedupe, keyword fast-path, ET↔KST (incl. DST),
                   # RSS parsing/providers, the API, and the Sep 25 replay.
```

The **Sep 25 2026 replay** (`tests/test_replay_sep25.py`) is the acceptance test
for the failure this app exists to prevent: it asserts a "position at risk" alert
fires off the 09:05 ET Optimus headline (by 09:06 ET), that the 09:15 Investing.com
duplicate is merged (not re-sent), and that the distinct 09:21 EU/FSD story gets
its own alert.

---

## Deployment

See [DEPLOY.md](DEPLOY.md) for the always-on VPS setup (`docker compose up -d`)
so alerts keep firing while your Mac sleeps.
