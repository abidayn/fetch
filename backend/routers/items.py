"""CRUD for saved_items. Every route requires login (via get_current_user)."""

import logging
import uuid
from typing import get_args

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from classifier import Category
from database import get_db
from deps import get_current_user
from embeddings import embed_one, embedding_text
from enrichment import enrich_item
from models import SavedItem, User
from schemas import ItemCreate, ItemPublic, ItemUpdate

log = logging.getLogger(__name__)

router = APIRouter(prefix="/items", tags=["items"])


def _get_own_item(db: Session, item_id: uuid.UUID, user: User) -> SavedItem:
    item = db.get(SavedItem, item_id)
    # 404 is also used when the item belongs to ANOTHER user -- not only when
    # it doesn't exist. Deliberate: a 403 would leak "this item exists, it's
    # just not yours", revealing that another user's data exists.
    if item is None or item.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item not found.")
    return item


@router.post("", response_model=ItemPublic, status_code=status.HTTP_201_CREATED)
def create_item(
    payload: ItemCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Store just the url and reply 201 right away. Extraction + Gemini (4-9
    # seconds) run AFTER the response is sent -- saving a link must not wait
    # for, let alone fail because of, scraping or Gemini. See enrichment.py.
    item = SavedItem(user_id=current_user.id, url=payload.url)
    db.add(item)
    db.commit()
    db.refresh(item)
    background_tasks.add_task(enrich_item, item.id)
    return item


@router.get("", response_model=list[ItemPublic])
def list_items(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    items = db.scalars(
        select(SavedItem)
        .where(SavedItem.user_id == current_user.id)
        .order_by(SavedItem.created_at.desc())
    ).all()
    return items


# Must be registered BEFORE /{item_id}: FastAPI matches routes in order, and
# "categories" would be parsed as a UUID and fail with 422.
@router.get("/categories", response_model=list[str])
def list_categories(current_user: User = Depends(get_current_user)):
    """The fixed category list from classifier.py -- the single source for the
    app's edit dropdown, so there's no copy of the list in Flutter."""
    return list(get_args(Category))


@router.get("/{item_id}", response_model=ItemPublic)
def get_item(
    item_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return _get_own_item(db, item_id, current_user)


@router.patch("/{item_id}", response_model=ItemPublic)
def update_item(
    item_id: uuid.UUID,
    payload: ItemUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    item = _get_own_item(db, item_id, current_user)
    if not item.processed:
        # Background enrichment would OVERWRITE title/summary/category once it
        # finishes -- the user's edit would silently vanish. Reject for now.
        raise HTTPException(status.HTTP_409_CONFLICT, "The AI is still processing this item, try again shortly.")

    changes = payload.model_dump(exclude_unset=True)
    # Title & category may be omitted, but not cleared: without a title the
    # UI falls back to the raw URL, without a category the item disappears
    # from browse-by-category. Summary may be empty.
    if "title" in changes and changes["title"] is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Title can't be empty.")
    if "category" in changes and changes["category"] is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Category can't be empty.")
    if changes.get("summary") == "":
        changes["summary"] = None

    text_before = embedding_text(item.title, item.summary)
    for field, value in changes.items():
        setattr(item, field, value)

    # The vector is built from title+summary (embeddings.py). If those change
    # but the vector doesn't, search keeps using the OLD meaning. Changing
    # only the category needs no re-embed (category isn't part of the text).
    text_after = embedding_text(item.title, item.summary)
    if text_after != text_before:
        vector = embed_one(text_after) if text_after else None
        if vector is not None or not text_after:
            item.embedding = vector
        else:
            # Gemini failed: the old vector (similar meaning) is more useful
            # than NULL (item drops out of search). The edit is still saved.
            log.warning("re-embedding item %s failed, keeping the old vector", item_id)

    db.commit()
    db.refresh(item)
    return item


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(
    item_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    item = _get_own_item(db, item_id, current_user)
    db.delete(item)
    db.commit()
