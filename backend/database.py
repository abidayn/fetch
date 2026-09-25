"""
Database connection and the declarative Base.

The module deliberately stays importable without DATABASE_URL, so models can
be imported (e.g. by tooling) without a database configured.
"""

import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

load_dotenv()

_raw_url = os.environ.get("DATABASE_URL")

# Providers (Neon, Supabase, etc.) always give a connection string with the
# "postgresql://" scheme. SQLAlchemy maps that bare scheme to the psycopg2
# driver by default. We install psycopg version 3 (the "psycopg" package),
# not psycopg2 -- so the scheme has to be spelled "postgresql+psycopg://" for
# SQLAlchemy to know which driver to use.
DATABASE_URL = (
    _raw_url.replace("postgresql://", "postgresql+psycopg://", 1)
    if _raw_url
    else None
)

engine = create_engine(DATABASE_URL) if DATABASE_URL else None
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """Registry for all models. Alembic finds the tables via Base.metadata."""


def get_db():
    """FastAPI dependency: one session per request, guaranteed to be closed."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
