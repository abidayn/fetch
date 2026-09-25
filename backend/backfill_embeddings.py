"""
Create embeddings for items that don't have one yet (embedding IS NULL).

Cases: embedding failed during enrichment (Gemini down), or items saved
before embeddings existed. Items with neither title nor summary are skipped
-- there's no text to embed (see enrichment.py).

--all : re-embed ALL items. Required whenever MODEL/DIMENSIONS in
        embeddings.py change: vectors from the old and new model can't be
        mixed in one search (see docs/data-model.md).

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

# One API call for many texts at once: far easier on the free tier's
# requests-per-minute quota than one call per item.
BATCH_SIZE = 50


def main(reembed_all: bool) -> None:
    with SessionLocal() as db:
        query = select(SavedItem).where(
            or_(SavedItem.title.is_not(None), SavedItem.summary.is_not(None))
        )
        if not reembed_all:
            query = query.where(SavedItem.embedding.is_(None))
        items = [i for i in db.scalars(query).all() if embedding_text(i.title, i.summary)]
        print(f"{len(items)} items need embedding")

        done = 0
        for start in range(0, len(items), BATCH_SIZE):
            batch = items[start : start + BATCH_SIZE]
            vectors = embed([embedding_text(i.title, i.summary) for i in batch])
            if vectors is None:
                print(f"batch {start}-{start + len(batch)} failed, skipped (run again later)")
                continue
            for item, vector in zip(batch, vectors):
                item.embedding = vector
            db.commit()  # commit per batch: if the next batch fails, this one is still saved
            done += len(batch)
            print(f"[{done}/{len(items)}] saved")

        left = db.scalar(
            select(SavedItem.id).where(SavedItem.embedding.is_(None), SavedItem.summary.is_not(None)).limit(1)
        )
        print("done." + (" some items with a summary still have no embedding." if left else ""))


if __name__ == "__main__":
    main(reembed_all="--all" in sys.argv)
