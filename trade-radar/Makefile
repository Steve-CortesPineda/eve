# Trade Radar — local dev convenience targets.
# Everything works in free mode (no API keys required).

PY ?= python3
VENV := .venv
BIN := $(VENV)/bin

.PHONY: setup test demo live-smoke dev clean

setup:
	$(PY) -m venv $(VENV)
	$(BIN)/pip install --upgrade pip
	$(BIN)/pip install -r requirements.txt

test:
	$(BIN)/python -m pytest -q

demo:
	$(BIN)/python scripts/demo_offline.py

live-smoke:
	$(BIN)/python scripts/live_smoke.py

dev:
	$(BIN)/uvicorn backend.app:app --reload --host 127.0.0.1 --port 8000

clean:
	rm -rf $(VENV) .pytest_cache **/__pycache__ trade_radar.db
