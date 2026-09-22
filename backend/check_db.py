"""
Throwaway script — not part of the app. Confirms DATABASE_URL connects and
enables the pgvector extension before Phase 1 builds real tables on top of it.

Usage:
    venv/Scripts/python.exe check_db.py
"""

import os

import psycopg
from dotenv import load_dotenv

load_dotenv()

db_url = os.environ.get("DATABASE_URL")
if not db_url:
    raise SystemExit("DATABASE_URL is not set. Copy .env.example to .env and fill it in.")

with psycopg.connect(db_url) as conn:
    with conn.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        conn.commit()

        cur.execute("SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';")
        row = cur.fetchone()

print("Connected OK.")
print(f"pgvector extension: {row}")
