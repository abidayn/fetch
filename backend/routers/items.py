"""CRUD saved_items. Semua route butuh login (lewat get_current_user)."""

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
    # 404 juga dipakai kalau item milik user LAIN — bukan cuma kalau item
    # memang tidak ada. Ini disengaja: 403 justru membocorkan "item ini ada,
    # cuma bukan milikmu", yang membocorkan keberadaan data user lain.
    if item is None or item.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item tidak ditemukan.")
    return item


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


# Harus didaftarkan SEBELUM /{item_id}: FastAPI mencocokkan route berurutan,
# dan "categories" akan dicoba di-parse sebagai UUID lalu gagal 422.
@router.get("/categories", response_model=list[str])
def list_categories(current_user: User = Depends(get_current_user)):
    """Daftar kategori tetap dari classifier.py -- sumber tunggal untuk
    dropdown edit di app, supaya tidak ada salinan daftar di Flutter."""
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
        # Pengayaan di background akan MENIMPA title/summary/category begitu
        # selesai -- editan user hilang diam-diam. Tolak dulu, coba lagi nanti.
        raise HTTPException(status.HTTP_409_CONFLICT, "Item masih diproses AI, coba lagi sebentar.")

    changes = payload.model_dump(exclude_unset=True)
    # Title & kategori boleh tidak dikirim, tapi tidak boleh dikosongkan:
    # tanpa title UI jatuh ke URL mentah, tanpa kategori item hilang dari
    # browse per kategori. Summary boleh kosong.
    if "title" in changes and changes["title"] is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Judul tidak boleh kosong.")
    if "category" in changes and changes["category"] is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Kategori tidak boleh kosong.")
    if changes.get("summary") == "":
        changes["summary"] = None

    text_before = embedding_text(item.title, item.summary)
    for field, value in changes.items():
        setattr(item, field, value)

    # Vektor dibuat dari title+summary (embeddings.py). Kalau keduanya
    # berubah tapi vektornya tidak, pencarian tetap memakai makna LAMA.
    # Ganti kategori saja tidak perlu embed ulang (kategori bukan bagian teks).
    text_after = embedding_text(item.title, item.summary)
    if text_after != text_before:
        vector = embed_one(text_after) if text_after else None
        if vector is not None or not text_after:
            item.embedding = vector
        else:
            # Gemini gagal: vektor lama (makna mirip) lebih berguna daripada
            # NULL (item hilang dari pencarian). Edit tetap disimpan.
            log.warning("embed ulang item %s gagal, vektor lama dipertahankan", item_id)

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
