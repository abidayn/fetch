"""
Folder logic shared by routers/folders.py, routers/items.py, enrichment.py and
backfill_enrichment.py.

Who decides an item's folder (data-model.md, "Folders: who decides"):
- folder_by = "user": the user picked it. The AI never touches it.
- folder_by = "ai":   the user tapped "Let AI pick". The classifier's
                      folder_suggestion is applied by apply_ai_folder -- right
                      away if the item is already classified, otherwise by
                      enrichment when it finishes.
- folder_by = NULL:   nobody asked; the item is Unfiled.

The AI's suggestion is only ever turned into a real folder here, when the user
asked for it. Classification itself creates nothing.
"""

import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models import Folder

MAX_NAME_LEN = 40
# The folder names go into every classification prompt (classifier.py), so
# their number is capped to keep the prompt small.
MAX_FOLDERS = 50


def normalize_name(raw: str) -> str:
    """Trim and collapse inner whitespace: "  Gym   stuff " -> "Gym stuff".
    Case is kept -- uniqueness is case-insensitive in the database instead."""
    return " ".join(raw.split())


def user_folder_names(db: Session, user_id: uuid.UUID) -> list[str]:
    """The user's folder names, for the classification prompt."""
    return list(db.scalars(
        select(Folder.name).where(Folder.user_id == user_id).order_by(func.lower(Folder.name))
    ))


def count_folders(db: Session, user_id: uuid.UUID) -> int:
    return db.scalar(select(func.count()).select_from(Folder).where(Folder.user_id == user_id))


def find_by_name(db: Session, user_id: uuid.UUID, name: str) -> Folder | None:
    # Same expression as the unique index (lower(name)), so "recipes" finds "Recipes".
    return db.scalar(
        select(Folder).where(Folder.user_id == user_id, func.lower(Folder.name) == name.lower())
    )


def get_or_create(db: Session, user_id: uuid.UUID, name: str) -> Folder | None:
    """The folder with this name (case-insensitive), created if missing.
    None when the user is at MAX_FOLDERS and it doesn't exist yet."""
    existing = find_by_name(db, user_id, name)
    if existing is not None:
        return existing
    if count_folders(db, user_id) >= MAX_FOLDERS:
        return None
    try:
        # SAVEPOINT: if another request created the same name a moment ago,
        # the unique index rejects this insert, and only the savepoint is
        # rolled back -- not the caller's whole transaction (and its row lock).
        with db.begin_nested():
            folder = Folder(user_id=user_id, name=name)
            db.add(folder)
    except IntegrityError:
        return find_by_name(db, user_id, name)
    return folder


def suggestion_from_model(raw: str) -> str | None:
    """Clean the classifier's `folder` answer for storage in folder_suggestion.
    Truncated rather than rejected: a long name must not fail classification."""
    name = normalize_name(raw)[:MAX_NAME_LEN].strip()
    return name or None


def apply_ai_folder(db: Session, item) -> None:
    """Place an item the user asked the AI to file, using its folder_suggestion.

    Call with the item row locked (SELECT ... FOR UPDATE), so this and a
    concurrent PUT /items/{id}/folder can't interleave. Does nothing unless
    the item is waiting for the AI (folder_by == "ai" and not placed yet) and
    a suggestion exists -- so an item the AI already placed is never moved,
    e.g. by the upgrade job re-classifying it later.
    """
    if item.folder_by != "ai" or item.folder_id is not None or not item.folder_suggestion:
        return
    folder = get_or_create(db, item.user_id, item.folder_suggestion)
    if folder is not None:
        item.folder = folder
        item.folder_id = folder.id
