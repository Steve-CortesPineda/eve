FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install deps first for layer caching.
COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

# App source (secrets are provided at runtime via env / .env, never baked in).
COPY backend ./backend
COPY config.yaml ./config.yaml

EXPOSE 8000

# Read-only news/alert service.
CMD ["uvicorn", "backend.app:app", "--host", "0.0.0.0", "--port", "8000"]
