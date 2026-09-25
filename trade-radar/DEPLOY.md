# Deploying Trade Radar (always-on VPS)

The whole point of the alerts is that they fire while you are asleep in Seoul and
your Mac is closed. Run it on a small always-on box (a $5–6/mo VPS is plenty —
this is I/O-light: a few RSS polls a minute).

## Prerequisites

- A Linux VPS with Docker + the Compose plugin.
- Your `.env` (at minimum `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`; see README).

## Steps

```sh
# on the VPS, in the trade-radar/ directory
cp .env.example .env         # then fill in your Telegram token + chat id
# edit config.yaml to match your holdings/watchlist

docker compose up -d --build
docker compose logs -f       # watch it poll and (dry-run or real) alert
```

Health check:

```sh
curl -s localhost:8000/health | python3 -m json.tool
```

`telegram_enabled: true` confirms real push is active. Send a test by leaving it
running during US premarket; holding-related risk headlines will arrive on your
phone.

## Notes

- **Data persistence:** the SQLite headline/alert log is stored in the
  `trade-radar-data` volume, so latency history survives restarts.
- **Config changes:** `config.yaml` is bind-mounted read-only; edit it and
  `docker compose restart` — no rebuild needed.
- **Updates:** `git pull && docker compose up -d --build`.
- **Read-only guarantee:** the container has no brokerage write scope and the
  code never calls an order endpoint. Keep it that way.
- **Time:** all alerts show ET + KST regardless of the server's timezone (times
  are computed via the IANA tz database, not the host clock).
- **Rate limits / terms:** default poll is 45s jittered (≥30s/feed). Do not lower
  it; the feeds rate-limit and it is against their terms to hammer them.
