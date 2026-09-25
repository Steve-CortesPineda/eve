"""SQLite persistence via SQLModel.

Every headline and alert is stored so latency (per-source first_seen) can be
analyzed later. The engine is created lazily so tests can point DB_URL at an
in-memory or temp database without side effects on import.
"""

from __future__ import annotations

from contextlib import contextmanager
from typing import Iterator, Optional

from sqlmodel import Session, SQLModel, create_engine

from .config import get_settings

_engine = None


def get_engine(db_url: Optional[str] = None):
    global _engine
    if db_url is not None:
        return create_engine(db_url, connect_args={"check_same_thread": False})
    if _engine is None:
        url = get_settings().db_url
        _engine = create_engine(url, connect_args={"check_same_thread": False})
    return _engine


def init_db(db_url: Optional[str] = None) -> None:
    # Import models so their tables register on SQLModel.metadata.
    from . import models  # noqa: F401

    SQLModel.metadata.create_all(get_engine(db_url))


@contextmanager
def session_scope(db_url: Optional[str] = None) -> Iterator[Session]:
    engine = get_engine(db_url)
    with Session(engine) as session:
        yield session
        session.commit()
