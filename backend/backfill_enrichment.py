"""
Proses ulang item yang belum selesai diperkaya.

Menangkap dua kasus (lihat "NULL = antrian kerja" di docs/data-model.md):
- raw_content IS NULL                      -> belum pernah diproses
  (item dari sebelum Fase 3, atau server mati saat background task jalan)
- summary IS NULL AND raw_content != ''    -> punya isi, tapi Gemini gagal
  (mis. 503 yang tetap gagal setelah retry)

Item dengan raw_content == '' (memang tidak ada isi, contoh Instagram tanpa
login) sengaja TIDAK diulang -- hasilnya akan tetap kosong.

Usage:
    venv/Scripts/python.exe backfill_enrichment.py
"""

import logging

from sqlalchemy import and_, or_, select

from database import SessionLocal
from enrichment import enrich_item
from models import SavedItem

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s - %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)


def pending_ids():
    with SessionLocal() as db:
        return db.scalars(
            select(SavedItem.id).where(
                or_(
                    SavedItem.raw_content.is_(None),
                    and_(SavedItem.summary.is_(None), SavedItem.raw_content != ""),
                )
            )
        ).all()


def main():
    ids = pending_ids()
    print(f"{len(ids)} item perlu diproses")
    for i, item_id in enumerate(ids, 1):
        print(f"[{i}/{len(ids)}] {item_id}")
        # Untuk kasus "AI gagal", reset raw_content supaya enrich_item
        # memproses dari awal (ekstraksi ulang + klasifikasi ulang).
        with SessionLocal() as db:
            item = db.get(SavedItem, item_id)
            if item is not None and item.raw_content:
                item.raw_content = None
                db.commit()
        enrich_item(item_id)
    left = len(pending_ids())
    print(f"selesai. tersisa {left} item yang masih gagal (jalankan ulang nanti)")


if __name__ == "__main__":
    main()
