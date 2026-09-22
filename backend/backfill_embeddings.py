"""
Buat embedding untuk item yang belum punya (embedding IS NULL).

Kasusnya: item dari sebelum Fase 4, atau embedding gagal saat enrichment
(Gemini down). Item tanpa title maupun summary dilewati -- tidak ada teks
yang bisa di-embed (lihat enrichment.py).

--all : embed ulang SEMUA item. Wajib dijalankan kalau MODEL/DIMENSIONS di
        embeddings.py diganti: vektor model lama & baru tidak bisa dicampur
        dalam satu pencarian (lihat docs/data-model.md).

Usage:
    venv/Scripts/python.exe backfill_embeddings.py [--all]
"""

import logging
import sys

from sqlalchemy import or_, select

from database import SessionLocal
from embeddings import embed, embedding_text
from models import SavedItem

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s - %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)

# Satu panggilan API untuk banyak teks sekaligus: jauh lebih hemat kuota
# request-per-menit free tier daripada satu panggilan per item.
BATCH_SIZE = 50


def main(reembed_all: bool) -> None:
    with SessionLocal() as db:
        query = select(SavedItem).where(
            or_(SavedItem.title.is_not(None), SavedItem.summary.is_not(None))
        )
        if not reembed_all:
            query = query.where(SavedItem.embedding.is_(None))
        items = [i for i in db.scalars(query).all() if embedding_text(i.title, i.summary)]
        print(f"{len(items)} item perlu di-embed")

        done = 0
        for start in range(0, len(items), BATCH_SIZE):
            batch = items[start : start + BATCH_SIZE]
            vectors = embed([embedding_text(i.title, i.summary) for i in batch])
            if vectors is None:
                print(f"batch {start}-{start + len(batch)} gagal, dilewati (jalankan ulang nanti)")
                continue
            for item, vector in zip(batch, vectors):
                item.embedding = vector
            db.commit()  # commit per batch: kalau batch berikutnya gagal, yang ini tetap tersimpan
            done += len(batch)
            print(f"[{done}/{len(items)}] tersimpan")

        left = db.scalar(
            select(SavedItem.id).where(SavedItem.embedding.is_(None), SavedItem.summary.is_not(None)).limit(1)
        )
        print("selesai." + (" masih ada item ber-summary tanpa embedding." if left else ""))


if __name__ == "__main__":
    main(reembed_all="--all" in sys.argv)
