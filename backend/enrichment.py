"""
Enriching an item after it's saved: metadata extraction -> AI classification
(via the fallback chain in llm.py) -> embedding (for RAG search).

Runs as a BackgroundTask after POST /items has already replied 201, so saving
a link never waits for (or depends on) scraping or the AI.

Processing state is tracked in raw_content, with no extra column:
- raw_content IS NULL  -> not processed yet
- raw_content == ""    -> processed, but no content could be extracted
- anything else        -> processed, holds the extracted text

classified_by records which model wrote title/summary/category (or "user").
upgrade_fallback_items() re-does items the primary model didn't write -- from
the stored raw_content, no re-scraping. That one mechanism covers two cases:
upgrading a weaker fallback model's summary, and retrying items whose
classification failed entirely (classified_by stays NULL).
"""

import logging
import threading
import time
import uuid

from sqlalchemy import or_, select

import llm
from classifier import PRIMARY, classify
from database import SessionLocal
from embeddings import embed_one, embedding_text
from extraction import extract
from models import SavedItem

log = logging.getLogger(__name__)

# How the upgrade job is paced. It's triggered by opening the app (GET /items),
# not by a timer: the server sleeps when idle, so a timer wouldn't fire. It
# only uses primary-model quota left over after new saves, a few items at a time.
UPGRADE_BATCH = 3
UPGRADE_MIN_INTERVAL_S = 15 * 60


def apply_classification(item: SavedItem, result: "llm.Result") -> None:
    """Store a classifier result on the item (without committing)."""
    item.title = result.value.title
    item.summary = result.value.summary
    item.category = result.value.category
    item.classified_by = result.model


def enrich_item(item_id: uuid.UUID) -> None:
    # Own session: the request's session is closed as soon as the response is
    # sent, so a background task must not use it.
    db = SessionLocal()
    try:
        item = db.get(SavedItem, item_id)
        if item is None:
            return  # deleted by the user before it got processed

        extracted = extract(item.url)
        content = extracted.to_text()
        result = classify(item.url, extracted.platform, content)

        item.platform = extracted.platform
        item.raw_content = content  # "" when empty -> marks it "processed"
        if result is not None:
            apply_classification(item, result)
        else:
            # All models failed / no content: use the extracted title if there
            # is one. classified_by stays NULL, so the upgrade job retries it.
            item.title = item.title or extracted.title

        # The embedding is built from the AI output (or at least the extracted
        # title). No text at all -> no embedding: a vector of empty text means
        # nothing and only shows up as a random "result" in search. Failure ->
        # embedding stays NULL, picked up later by backfill_embeddings.py.
        text = embedding_text(item.title, item.summary)
        item.embedding = embed_one(text) if text else None

        db.commit()
        log.info(
            "item %s enriched: platform=%s sources=%s ai=%s embedding=%s",
            item_id, extracted.platform, extracted.sources,
            result.model if result else None, item.embedding is not None,
        )
    except Exception:
        db.rollback()
        log.exception("enrichment of item %s failed", item_id)
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Upgrading items the primary model didn't write

_upgrade_lock = threading.Lock()   # one run at a time
_last_upgrade_run = 0.0
# Items whose upgrade failed for their own reasons (not quota): skipped for the
# rest of this process, so one problematic item can't burn primary quota on
# every run. Forgotten on restart, which is when a fix would have shipped.
_upgrade_skip: set[uuid.UUID] = set()


def upgrade_due() -> bool:
    """True at most once per UPGRADE_MIN_INTERVAL_S (checked on GET /items)."""
    global _last_upgrade_run
    now = time.monotonic()
    if _last_upgrade_run and now - _last_upgrade_run < UPGRADE_MIN_INTERVAL_S:
        return False
    _last_upgrade_run = now
    return True


def upgrade_fallback_items(limit: int = UPGRADE_BATCH) -> None:
    """Re-classify up to `limit` items with the PRIMARY model only.

    Candidates: items with content whose classified_by is NULL (never
    classified, or from before the column existed) or another model's id.
    "user" is never touched. Stops at the first sign the primary is
    unavailable (e.g. its daily quota), so it never falls back to the very
    models it's meant to replace.
    """
    if not _upgrade_lock.acquire(blocking=False):
        return
    db = SessionLocal()
    try:
        if not llm.is_available(PRIMARY):
            return
        query = (
            select(SavedItem)
            .where(
                SavedItem.raw_content != "",
                or_(SavedItem.classified_by.is_(None),
                    SavedItem.classified_by.not_in([str(PRIMARY), "user"])),
            )
            .order_by(SavedItem.created_at.desc())
        )
        if _upgrade_skip:
            query = query.where(SavedItem.id.not_in(_upgrade_skip))
        for item in db.scalars(query.limit(limit)).all():
            before = item.classified_by
            result = classify(item.url, item.platform or "generic", item.raw_content, chain=[PRIMARY])
            if result is None:
                if not llm.is_available(PRIMARY):
                    log.info("upgrade: primary model unavailable, stopping")
                    break
                _upgrade_skip.add(item.id)
                continue
            apply_classification(item, result)
            vector = embed_one(embedding_text(item.title, item.summary))
            if vector is not None:
                item.embedding = vector
            db.commit()  # per item: a later failure doesn't lose earlier progress
            log.info("upgrade: item %s re-classified (%s -> %s)", item.id, before, result.model)
    except Exception:
        db.rollback()
        log.exception("upgrade run failed")
    finally:
        db.close()
        _upgrade_lock.release()
