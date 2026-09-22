"""
Pydantic schema: bentuk request dan response API.

Sengaja terpisah dari models.py (SQLAlchemy). Model = bentuk data di database,
schema = bentuk data di kawat. Keduanya mirip tapi tidak sama — password mentah
masuk lewat schema tapi tidak pernah ada di model; password_hash ada di model
tapi haram muncul di schema response.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

BCRYPT_MAX_BYTES = 72


class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)

    @field_validator("password")
    @classmethod
    def password_fits_bcrypt(cls, v: str) -> str:
        # Batasnya 72 BYTE, bukan 72 karakter — satu karakter non-ASCII bisa
        # memakan 2-4 byte, jadi max_length biasa tidak cukup akurat.
        if len(v.encode("utf-8")) > BCRYPT_MAX_BYTES:
            raise ValueError(f"Password melebihi {BCRYPT_MAX_BYTES} byte.")
        return v


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserPublic(BaseModel):
    """Bentuk user yang boleh keluar dari API. Tidak ada password_hash di sini."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ItemCreate(BaseModel):
    # Title manual dari Fase 1 dihapus: sekarang title diisi otomatis oleh
    # pengayaan AI (enrichment.py). Client cukup kirim url.
    url: str


class ItemPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    url: str
    platform: str | None
    title: str | None
    summary: str | None
    category: str | None
    processed: bool  # False = pengayaan belum selesai (UI tampilkan "memproses")
    created_at: datetime


class SearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=500)
    limit: int = Field(default=10, ge=1, le=50)


class SearchResult(ItemPublic):
    # Cosine similarity 0..1 (makin tinggi makin mirip). Cuma bermakna untuk
    # membandingkan hasil dalam SATU pencarian -- angkanya tidak bisa dibaca
    # sebagai persentase relevansi (teks acak pun bisa dapat ~0.6).
    score: float


class AnswerRequest(BaseModel):
    query: str = Field(min_length=1, max_length=500)


class AnswerResponse(BaseModel):
    # Menyebut sumber dengan penanda [1], [2], ... = indeks (mulai 1) ke
    # `sources`. None = Gemini gagal; client tampilkan sources saja.
    answer: str | None
    sources: list[SearchResult]
