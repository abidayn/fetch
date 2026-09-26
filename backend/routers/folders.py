"""The user's folders: list (with item counts), create, rename, delete.

Filing an item into a folder is PUT /items/{id}/folder (routers/items.py).
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import folders
from database import get_db
from deps import get_current_user
from models import Folder, SavedItem, User
from schemas import FolderIn, FolderPublic

router = APIRouter(prefix="/folders", tags=["folders"])

DUPLICATE_NAME = "You already have a folder with that name."


def _get_own_folder(db: Session, folder_id: uuid.UUID, user: User) -> Folder:
    folder = db.get(Folder, folder_id)
    # 404 for another user's folder too, not 403 -- same reason as items:
    # a 403 would reveal that the folder exists.
    if folder is None or folder.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Folder not found.")
    return folder


def _public(folder: Folder, item_count: int) -> FolderPublic:
    return FolderPublic(id=folder.id, name=folder.name, item_count=item_count, created_at=folder.created_at)


def _count_items(db: Session, folder_id: uuid.UUID) -> int:
    return db.scalar(select(func.count()).select_from(SavedItem).where(SavedItem.folder_id == folder_id))


@router.get("", response_model=list[FolderPublic])
def list_folders(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Every folder with its item count, including empty ones: a folder the
    user just made should show up even before anything is in it."""
    rows = db.execute(
        select(Folder, func.count(SavedItem.id))
        .outerjoin(SavedItem, SavedItem.folder_id == Folder.id)
        .where(Folder.user_id == current_user.id)
        .group_by(Folder.id)
        .order_by(func.lower(Folder.name))
    ).all()
    return [_public(folder, count) for folder, count in rows]


@router.post("", response_model=FolderPublic, status_code=status.HTTP_201_CREATED)
def create_folder(
    payload: FolderIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if folders.count_folders(db, current_user.id) >= folders.MAX_FOLDERS:
        raise HTTPException(status.HTTP_409_CONFLICT, f"You can have up to {folders.MAX_FOLDERS} folders.")
    folder = Folder(user_id=current_user.id, name=payload.name)
    db.add(folder)
    try:
        db.commit()
    except IntegrityError:
        # The case-insensitive unique index (user_id, lower(name)) decides --
        # no check-then-insert race.
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, DUPLICATE_NAME)
    db.refresh(folder)
    return _public(folder, 0)


@router.patch("/{folder_id}", response_model=FolderPublic)
def rename_folder(
    folder_id: uuid.UUID,
    payload: FolderIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    folder = _get_own_folder(db, folder_id, current_user)
    folder.name = payload.name
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, DUPLICATE_NAME)
    return _public(folder, _count_items(db, folder.id))


@router.delete("/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_folder(
    folder_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The items aren't deleted, they become Unfiled. folder_by is cleared
    too: left as "ai", the upgrade job would see an item still "waiting for
    the AI" and file it again -- re-creating the folder the user just deleted."""
    folder = _get_own_folder(db, folder_id, current_user)
    db.execute(
        update(SavedItem)
        .where(SavedItem.folder_id == folder.id)
        .values(folder_id=None, folder_by=None)
    )
    db.delete(folder)
    db.commit()
