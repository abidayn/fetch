"""
Pydantic schemas: the shape of API requests and responses.

Deliberately separate from models.py (SQLAlchemy). Model = shape of the data in
the database, schema = shape of the data on the wire. They look alike but
aren't the same -- the raw password comes in through a schema but never exists
in a model; password_hash exists in the model but must never appear in a
response schema.
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
        # The limit is 72 BYTES, not 72 characters -- one non-ASCII character
        # can take 2-4 bytes, so a plain max_length isn't accurate enough.
        if len(v.encode("utf-8")) > BCRYPT_MAX_BYTES:
            raise ValueError(f"Password exceeds {BCRYPT_MAX_BYTES} bytes.")
        return v


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserPublic(BaseModel):
    """The user shape allowed out of the API. No password_hash here."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ItemCreate(BaseModel):
    # The client only sends the url: title, summary and category are filled
    # in automatically by AI enrichment (enrichment.py).
    url: str


class ItemUpdate(BaseModel):
    """PATCH /items/{id}: only fields that are SENT get changed (exclude_unset).

    url deliberately can't be edited: a different link = a different item, save a new one.
    """

    title: str | None = Field(default=None, min_length=1, max_length=300)
    summary: str | None = Field(default=None, max_length=2000)
    category: Category | None = None

    # mode="before": strip BEFORE min_length is checked -- if it ran after,
    # a title of "   " would pass min_length and be saved as an empty string.
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
    processed: bool  # False = enrichment not finished (UI shows "processing")
    has_content: bool  # False = the link's content couldn't be read (see SavedItem.has_content)
    created_at: datetime


class SearchFilters(BaseModel):
    """The structured part of hybrid retrieval: filtered in WHERE, not via the
    vector. "cooking videos from last month" = "cooking" (semantic) +
    created_at (filter) -- embeddings can't "understand" dates, so they have
    to be a column."""

    category: Category | None = None
    created_after: datetime | None = None  # inclusive
    created_before: datetime | None = None  # exclusive

    @model_validator(mode="after")
    def range_is_valid(self):
        if self.created_after and self.created_before and self.created_after >= self.created_before:
            raise ValueError("created_after must be before created_before.")
        return self


class SearchRequest(SearchFilters):
    query: str = Field(min_length=1, max_length=500)
    limit: int = Field(default=10, ge=1, le=50)


class SearchResult(ItemPublic):
    # Cosine similarity 0..1 (higher = more similar). Only meaningful for
    # comparing results within ONE search -- the number can't be read as a
    # relevance percentage (even random text can score ~0.6).
    score: float


class AnswerRequest(SearchFilters):
    query: str = Field(min_length=1, max_length=500)


class AnswerResponse(BaseModel):
    # Sources are cited with markers [1], [2], ... = 1-based index into
    # `sources`. None = Gemini failed; the client shows just the sources.
    answer: str | None
    sources: list[SearchResult]
