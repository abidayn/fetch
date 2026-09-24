"""
Proses ulang item yang belum selesai diperkaya.

Menangkap dua kasus (lihat "NULL = antrian kerja" di docs/data-model.md):
- raw_content IS NULL                      -> belum pernah diproses
  (item dari sebelum Fase 3, atau server mati saat background task jalan)
- summary IS NULL AND raw_content != ''    -> punya isi, tapi Gemini gagal
  (mis. 503 yang tetap gagal setelah retry)

Item dengan raw_content == '' (memang tidak ada isi, contoh post privat)
sengaja TIDAK diulang -- hasilnya akan tetap kosong.

--ids : proses ulang item tertentu DARI NOL, apa pun statusnya. Untuk item
        yang "berhasil" tapi isinya salah -- mis. ringkasan tentang YouTube
        generik karena ekstraksi dulu diblokir -- atau raw_content == '' yang
        sekarang bisa dibaca setelah extraction.py diperbaiki. Title, summary,
        dan kategori ikut dihapus dulu (termasuk editan user, kalau ada):
        tanpa itu, kalau Gemini gagal lagi, nilai lama yang salah tetap tinggal.

Usage:
    venv/Scripts/python.exe backfill_enrichment.py
    venv/Scripts/python.exe backfill_enrichment.py --ids <uuid> [<uuid> ...]
"""

import logging
import sys
import uuid

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


def reprocess(ids: list[uuid.UUID]):
    for i, item_id in enumerate(ids, 1):
        with SessionLocal() as db:
            item = db.get(SavedItem, item_id)
            if item is None:
                print(f"[{i}/{len(ids)}] {item_id} tidak ditemukan, dilewati")
                continue
            item.raw_content = item.title = item.summary = item.category = None
            item.embedding = None
            db.commit()
        print(f"[{i}/{len(ids)}] {item_id}")
        enrich_item(item_id)
        with SessionLocal() as db:
            item = db.get(SavedItem, item_id)
            print(f"    -> title={item.title!r} category={item.category!r} ada_isi={item.has_content}")


def main():
    if "--ids" in sys.argv:
        reprocess([uuid.UUID(a) for a in sys.argv[sys.argv.index("--ids") + 1 :]])
        return

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
