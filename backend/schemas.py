"""
Pydantic schema: bentuk request dan response API.

Sengaja terpisah dari models.py (SQLAlchemy). Model = bentuk data di database,
schema = bentuk data di kawat. Keduanya mirip tapi tidak sama — password mentah
masuk lewat schema tapi tidak pernah ada di model; password_hash ada di model
tapi haram muncul di schema response.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

from classifier import Category

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


class ItemUpdate(BaseModel):
    """PATCH /items/{id}: cuma field yang DIKIRIM yang diubah (exclude_unset).

    url sengaja tidak bisa diedit: link beda = item beda, simpan baru saja.
    """

    title: str | None = Field(default=None, min_length=1, max_length=300)
    summary: str | None = Field(default=None, max_length=2000)
    category: Category | None = None

    # mode="before": strip SEBELUM min_length dicek -- kalau sesudahnya,
    # judul "   " lolos min_length lalu tersimpan sebagai string kosong.
    @field_validator("title", "summary", mode="before")
    @classmethod
    def strip_text(cls, v):
        return v.strip() if isinstance(v, str) else v


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


class SearchFilters(BaseModel):
    """Bagian terstruktur dari hybrid retrieval: disaring di WHERE, bukan lewat
    vektor. "video masak bulan lalu" = "masak" (semantik) + created_at (filter)
    -- tanggal tidak bisa "dipahami" embedding, jadi harus jadi kolom."""

    category: Category | None = None
    created_after: datetime | None = None  # inklusif
    created_before: datetime | None = None  # eksklusif

    @model_validator(mode="after")
    def range_is_valid(self):
        if self.created_after and self.created_before and self.created_after >= self.created_before:
            raise ValueError("created_after harus sebelum created_before.")
        return self


class SearchRequest(SearchFilters):
    query: str = Field(min_length=1, max_length=500)
    limit: int = Field(default=10, ge=1, le=50)


class SearchResult(ItemPublic):
    # Cosine similarity 0..1 (makin tinggi makin mirip). Cuma bermakna untuk
    # membandingkan hasil dalam SATU pencarian -- angkanya tidak bisa dibaca
    # sebagai persentase relevansi (teks acak pun bisa dapat ~0.6).
    score: float


class AnswerRequest(SearchFilters):
    query: str = Field(min_length=1, max_length=500)


class AnswerResponse(BaseModel):
    # Menyebut sumber dengan penanda [1], [2], ... = indeks (mulai 1) ke
    # `sources`. None = Gemini gagal; client tampilkan sources saja.
    answer: str | None
    sources: list[SearchResult]
