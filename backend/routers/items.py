"""CRUD saved_items. Semua route butuh login (lewat get_current_user)."""

import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from database import get_db
from deps import get_current_user
from enrichment import enrich_item
from models import SavedItem, User
from schemas import ItemCreate, ItemPublic

router = APIRouter(prefix="/items", tags=["items"])


@router.post("", response_model=ItemPublic, status_code=status.HTTP_201_CREATED)
def create_item(
    payload: ItemCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Simpan url saja lalu langsung balas 201. Ekstraksi + Gemini (4-9 detik)
    # jalan SETELAH response terkirim -- menyimpan link tidak boleh menunggu,
    # apalagi gagal, gara-gara scraping atau Gemini. Lihat enrichment.py.
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


@router.get("/{item_id}", response_model=ItemPublic)
def get_item(
    item_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    item = db.get(SavedItem, item_id)
    # 404 juga dipakai kalau item milik user LAIN — bukan cuma kalau item
    # memang tidak ada. Ini disengaja: 403 justru membocorkan "item ini ada,
    # cuma bukan milikmu", yang membocorkan keberadaan data user lain.
    if item is None or item.user_id != current_user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item tidak ditemukan.")
    return item


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(
    item_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    item = db.get(SavedItem, item_id)
    if item is None or item.user_id != current_user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item tidak ditemukan.")
    db.delete(item)
    db.commit()
