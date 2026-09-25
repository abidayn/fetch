"""
Enriching an item after it's saved: metadata extraction -> Gemini
classification -> embedding (for RAG search).

Runs as a BackgroundTask after POST /items has already replied 201, so saving
a link never waits for (or depends on) scraping or Gemini.

Processing state is tracked in raw_content, with no extra column:
- raw_content IS NULL  -> not processed yet
- raw_content == ""    -> processed, but no content could be extracted
- anything else        -> processed, holds the extracted text
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
            item.title = result.title
            item.summary = result.summary
            item.category = result.category
        else:
            # Gemini failed / no content: use the extracted title if there is one.
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
            item_id, extracted.platform, extracted.sources, result is not None,
            item.embedding is not None,
        )
    except Exception:
        db.rollback()
        log.exception("enrichment of item %s failed", item_id)
    finally:
        db.close()
