"""
Re-process items whose enrichment didn't finish.

Catches two cases (see "NULL = work queue" in docs/data-model.md):
- raw_content IS NULL                      -> never processed
  (e.g. the server died while the background task was running)
- summary IS NULL AND raw_content != ''    -> has content, but Gemini failed
  (e.g. a 503 that still failed after retries)

Items with raw_content == '' (genuinely no content, e.g. a private post) are
deliberately NOT retried -- the result would still be empty.

--ids        : re-process specific items FROM SCRATCH, whatever their state.
               For items that "succeeded" but hold the wrong content -- e.g. a
               summary of generic YouTube text because extraction used to be
               blocked -- or raw_content == '' that can be read now after an
               extraction.py fix. Title, summary and category are cleared
               first (including user edits, if any): otherwise, if Gemini
               fails again, the old wrong values would stay.

--reclassify : re-run ONLY the Gemini classification (+ embedding) for every
               item that has content, from the stored raw_content -- no
               re-scraping. For prompt or model changes (e.g. switching the
               summary language). Overwrites title/summary/category,
               including user edits. Uses one classification call per item,
               so mind the daily free-tier quota; items that fail keep their
               old values and can be retried by running this again.

Usage:
    venv/Scripts/python.exe backfill_enrichment.py
    venv/Scripts/python.exe backfill_enrichment.py --ids <uuid> [<uuid> ...]
    venv/Scripts/python.exe backfill_enrichment.py --reclassify
"""

import logging
import sys
import uuid

from sqlalchemy import and_, or_, select

from classifier import classify
from database import SessionLocal
from embeddings import embed_one, embedding_text
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
                print(f"[{i}/{len(ids)}] {item_id} not found, skipped")
                continue
            item.raw_content = item.title = item.summary = item.category = None
            item.embedding = None
            db.commit()
        print(f"[{i}/{len(ids)}] {item_id}")
        enrich_item(item_id)
        with SessionLocal() as db:
            item = db.get(SavedItem, item_id)
            print(f"    -> title={item.title!r} category={item.category!r} has_content={item.has_content}")


def reclassify():
    with SessionLocal() as db:
        items = db.scalars(
            select(SavedItem).where(SavedItem.raw_content != "").order_by(SavedItem.created_at)
        ).all()
        print(f"{len(items)} items to reclassify")
        failed = 0
        for i, item in enumerate(items, 1):
            result = classify(item.url, item.platform or "generic", item.raw_content)
            if result is None:
                # Old values stay (still better than nothing); rerun later.
                failed += 1
                print(f"[{i}/{len(items)}] {item.id} classification failed, kept as is")
                continue
            item.title, item.summary, item.category = result.title, result.summary, result.category
            vector = embed_one(embedding_text(item.title, item.summary))
            if vector is not None:
                item.embedding = vector
            db.commit()  # per item: a later failure doesn't lose earlier progress
            print(f"[{i}/{len(items)}] {item.title!r} ({item.category})")
        print(f"done. {failed} failed (run again later)" if failed else "done.")


def main():
    if "--ids" in sys.argv:
        reprocess([uuid.UUID(a) for a in sys.argv[sys.argv.index("--ids") + 1 :]])
        return
    if "--reclassify" in sys.argv:
        reclassify()
        return

    ids = pending_ids()
    print(f"{len(ids)} items need processing")
    for i, item_id in enumerate(ids, 1):
        print(f"[{i}/{len(ids)}] {item_id}")
        # For the "AI failed" case, reset raw_content so enrich_item processes
        # from scratch (re-extract + re-classify).
        with SessionLocal() as db:
            item = db.get(SavedItem, item_id)
            if item is not None and item.raw_content:
                item.raw_content = None
                db.commit()
        enrich_item(item_id)
    left = len(pending_ids())
    print(f"done. {left} items still failing (run again later)")


if __name__ == "__main__":
    main()
