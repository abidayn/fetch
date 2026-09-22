"""
Koneksi database dan Base declarative.

DATABASE_URL belum tersedia sampai Fase 0 (provisioning Postgres) selesai.
Modul ini sengaja tetap bisa di-import tanpa itu, supaya model bisa ditulis
dan diperiksa lebih dulu.
"""

import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

load_dotenv()

_raw_url = os.environ.get("DATABASE_URL")

# Provider (Neon, Supabase, dll) selalu kasih connection string berskema
# "postgresql://". SQLAlchemy menerjemahkan skema polos itu ke driver
# psycopg2 secara default. Kita install psycopg versi 3 (paket "psycopg"),
# bukan psycopg2 -- jadi skemanya perlu ditulis eksplisit "postgresql+psycopg://"
# supaya SQLAlchemy tahu driver mana yang harus dipakai.
DATABASE_URL = (
    _raw_url.replace("postgresql://", "postgresql+psycopg://", 1)
    if _raw_url
    else None
)

engine = create_engine(DATABASE_URL) if DATABASE_URL else None
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """Registry untuk semua model. Alembic menemukan tabel lewat Base.metadata."""


def get_db():
    """Dependency FastAPI: satu session per request, dijamin ditutup."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
