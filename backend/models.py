"""
SQLAlchemy model, mengikuti docs/data-model.md.

Kalau ada perbedaan antara file ini dan data-model.md, data-model.md yang benar
dan file ini yang harus menyesuaikan.
"""

import uuid
from datetime import datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import DateTime, ForeignKey, Index, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    email: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    items: Mapped[list["SavedItem"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class SavedItem(Base):
    __tablename__ = "saved_items"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    # Satu-satunya data yang pasti ada saat user menekan "share".
    url: Mapped[str] = mapped_column(Text, nullable=False)

    # Semua kolom di bawah ini hasil pengayaan — boleh kosong sampai
    # scraping / Gemini / embedding selesai (atau gagal).
    platform: Mapped[str | None] = mapped_column(Text, nullable=True)
    title: Mapped[str | None] = mapped_column(Text, nullable=True)
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    embedding: Mapped[list[float] | None] = mapped_column(Vector(768), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    user: Mapped["User"] = relationship(back_populates="items")

    @property
    def processed(self) -> bool:
        """raw_content NULL = belum diproses; "" atau berisi = sudah (enrichment.py)."""
        return self.raw_content is not None

    @property
    def has_content(self) -> bool:
        """Ekstraksi berhasil membaca isi link. Membedakan dua kasus "sudah
        diproses tapi tanpa ringkasan": link tidak terbaca (False) vs Gemini
        gagal padahal isinya ada (True, bisa diulang lewat backfill)."""
        return bool(self.raw_content)

    __table_args__ = (
        Index("idx_saved_items_user_id", "user_id"),
        # HNSW = index approximate nearest neighbor untuk pencarian vektor.
        # Operator class HARUS cocok dengan operator di query: vector_cosine_ops
        # hanya dipakai untuk `<=>`. Query yang ORDER BY `<->` (L2) akan
        # diam-diam mengabaikan index ini dan kembali memindai seluruh tabel.
        Index(
            "idx_saved_items_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
    )
