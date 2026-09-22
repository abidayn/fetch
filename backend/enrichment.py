"""
Pengayaan item setelah disimpan: ekstraksi metadata -> klasifikasi Gemini
-> embedding (untuk pencarian RAG).

Dijalankan sebagai BackgroundTask setelah POST /items sudah membalas 201,
jadi menyimpan link tidak pernah menunggu (atau bergantung pada) scraping
maupun Gemini.

Penanda status memakai raw_content, tanpa kolom tambahan:
- raw_content IS NULL  -> belum diproses
- raw_content == ""    -> sudah diproses, tapi tidak ada isi yang bisa diambil
- selain itu           -> sudah diproses, berisi teks hasil ekstraksi
"""

import logging
import uuid

from classifier import classify
from database import SessionLocal
from embeddings import embed_one, embedding_text
from extraction import extract
from models import SavedItem

log = logging.getLogger(__name__)


def enrich_item(item_id: uuid.UUID) -> None:
    # Session sendiri: session milik request sudah ditutup begitu response
    # terkirim, jadi background task tidak boleh memakainya.
    db = SessionLocal()
    try:
        item = db.get(SavedItem, item_id)
        if item is None:
            return  # sudah dihapus user sebelum sempat diproses

        extracted = extract(item.url)
        content = extracted.to_text()
        result = classify(item.url, extracted.platform, content)

        item.platform = extracted.platform
        item.raw_content = content  # "" kalau kosong -> tanda "sudah diproses"
        if result is not None:
            item.title = result.title
            item.summary = result.summary
            item.category = result.category
        else:
            # Gemini gagal / tidak ada isi: pakai judul hasil ekstraksi kalau ada.
            item.title = item.title or extracted.title

        # Embedding dibuat dari hasil AI (atau minimal judul hasil ekstraksi).
        # Tidak ada teks sama sekali -> tidak di-embed: vektor dari teks kosong
        # tidak bermakna dan cuma jadi "hasil" acak di pencarian. Gagal ->
        # embedding tetap NULL, ditangkap backfill_embeddings.py nanti.
        text = embedding_text(item.title, item.summary)
        item.embedding = embed_one(text) if text else None

        db.commit()
        log.info(
            "item %s diperkaya: platform=%s sources=%s ai=%s embedding=%s",
            item_id, extracted.platform, extracted.sources, result is not None,
            item.embedding is not None,
        )
    except Exception:
        db.rollback()
        log.exception("pengayaan item %s gagal", item_id)
    finally:
        db.close()
