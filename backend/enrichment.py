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

Folders: the same classification call also proposes a folder
(folder_suggestion). It's applied only if the user asked the AI to pick
(folder_by = "ai"), whenever a classification lands -- here, in the upgrade
job, or in suggest_folder(). See folders.py.
"""

import logging
import threading
import time
import uuid

from sqlalchemy import and_, or_, select
from sqlalchemy.exc import InvalidRequestError
from sqlalchemy.orm import Session

import folders
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


def apply_classification(
    db: Session, item: SavedItem, result: "llm.Result", keep_text: bool = False
) -> None:
    """Store a classifier result on the item (without committing), and file
    the item if the user asked the AI to pick its folder.

    keep_text=True takes only the folder suggestion and leaves
    title/summary/category alone -- for items the user edited, whose text
    must never be overwritten, but which can still ask the AI for a folder.
    """
    if not keep_text:
        item.title = result.value.title
        item.summary = result.value.summary
        item.category = result.value.category
        item.classified_by = result.model
    item.folder_suggestion = folders.suggestion_from_model(result.value.folder)
    folders.apply_ai_folder(db, item)


def lock_item(db: Session, item: SavedItem) -> bool:
    """Re-read the item's row and lock it until the next commit. False if the
    user deleted it meanwhile.

    Enrichment works on an item for seconds (scraping, AI). Meanwhile the user
    can pick a folder or tap "Let AI pick" (PUT /items/{id}/folder), which
    locks the same row. Re-reading under the lock means the folder decision
    below sees the user's latest choice, and a tap landing at the same moment
    waits for this commit instead of being lost (see folders.py).
    """
    try:
        db.refresh(item, with_for_update=True)
    except InvalidRequestError:  # the row no longer exists
        return False
    return True


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
        result = classify(
            item.url, extracted.platform, content, folders.user_folder_names(db, item.user_id)
        )

        # The embedding is built from the AI output (or at least the extracted
        # title). No text at all -> no embedding: a vector of empty text means
        # nothing and only shows up as a random "result" in search. Failure ->
        # embedding stays NULL, picked up later by backfill_embeddings.py.
        # Computed BEFORE locking the row: it's a network call, and the lock
        # below should be held only for the quick writes.
        title = result.value.title if result else (item.title or extracted.title)
        summary = result.value.summary if result else item.summary
        text = embedding_text(title, summary)
        vector = embed_one(text) if text else None

        if not lock_item(db, item):
            return  # deleted by the user while it was being processed
        item.platform = extracted.platform
        item.raw_content = content  # "" when empty -> marks it "processed"
        if result is not None:
            apply_classification(db, item, result)
        else:
            # All models failed / no content: use the extracted title if there
            # is one. classified_by stays NULL, so the upgrade job retries it
            # (and files the item then, if the user asked the AI to).
            item.title = item.title or extracted.title
        item.embedding = vector

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


def suggest_folder(item_id: uuid.UUID) -> None:
    """The user tapped "Let AI pick" on an item that has no folder suggestion:
    saved before folders existed, or its classification failed. One
    classification with the normal chain (the user is waiting for it), run
    as a BackgroundTask from PUT /items/{id}/folder.

    Only an item that was never classified gets its title/summary written
    too; an existing one keeps its text (a fallback model's answer here
    mustn't replace the primary's), and only its folder is taken.
    """
    db = SessionLocal()
    try:
        item = db.get(SavedItem, item_id)
        if item is None or not item.raw_content:
            return
        result = classify(
            item.url, item.platform or "generic", item.raw_content,
            folders.user_folder_names(db, item.user_id),
        )
        if result is None:
            return  # all models failed: the upgrade job retries it later
        keep_text = item.classified_by is not None
        vector = None if keep_text else embed_one(embedding_text(result.value.title, result.value.summary))
        if not lock_item(db, item):
            return
        keep_text = item.classified_by is not None  # re-checked under the lock
        apply_classification(db, item, result, keep_text=keep_text)
        if not keep_text and vector is not None:
            item.embedding = vector
        db.commit()
        log.info("item %s: folder suggested (%s) by %s", item_id, item.folder_suggestion, result.model)
    except Exception:
        db.rollback()
        log.exception("folder suggestion for item %s failed", item_id)
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
    classified, or from before the column existed) or another model's id --
    plus items still waiting for an AI folder (folder_by "ai", not placed;
    e.g. the suggestion call failed). "user" text is never touched: such
    items only get their folder. Stops at the first sign the primary is
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
                    SavedItem.classified_by.not_in([str(PRIMARY), "user"]),
                    and_(SavedItem.folder_by == "ai", SavedItem.folder_id.is_(None))),
            )
            .order_by(SavedItem.created_at.desc())
        )
        if _upgrade_skip:
            query = query.where(SavedItem.id.not_in(_upgrade_skip))
        for item in db.scalars(query.limit(limit)).all():
            before = item.classified_by
            result = classify(
                item.url, item.platform or "generic", item.raw_content,
                folders.user_folder_names(db, item.user_id), chain=[PRIMARY],
            )
            if result is None:
                if not llm.is_available(PRIMARY):
                    log.info("upgrade: primary model unavailable, stopping")
                    break
                _upgrade_skip.add(item.id)
                continue
            keep_text = item.classified_by == "user"
            vector = None if keep_text else embed_one(embedding_text(result.value.title, result.value.summary))
            # Re-read under a row lock (see lock_item): the user may have
            # edited the item or chosen a folder during the AI call.
            if not lock_item(db, item):
                continue
            keep_text = item.classified_by == "user"  # re-checked: edited meanwhile = the user's text wins
            apply_classification(db, item, result, keep_text=keep_text)
            if not keep_text and vector is not None:
                item.embedding = vector
            if item.folder_by == "ai" and item.folder_id is None:
                # Couldn't be placed (e.g. the user is at the folder limit):
                # don't pick it again on every run.
                _upgrade_skip.add(item.id)
            db.commit()  # per item: a later failure doesn't lose earlier progress
            log.info("upgrade: item %s re-classified (%s -> %s)", item.id, before, result.model)
    except Exception:
        db.rollback()
        log.exception("upgrade run failed")
    finally:
        db.close()
        _upgrade_lock.release()
