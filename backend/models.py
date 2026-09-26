"""
SQLAlchemy models, following docs/data-model.md.

If this file and data-model.md disagree, data-model.md is right and this file
has to be brought in line.
"""

import uuid
from datetime import datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import DateTime, ForeignKey, Index, Text, func, text
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


class Folder(Base):
    """The user's own grouping of items (next to the AI's fixed `category`)."""

    __tablename__ = "folders"

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
    # Normalised by folders.normalize_name before it gets here.
    name: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        # Case-insensitive: "Recipes" and "recipes" are one folder. Also what
        # lets the AI's suggested name match an existing folder, and what makes
        # two simultaneous creations of one name end in a single folder.
        Index("uq_folders_user_name", "user_id", text("lower(name)"), unique=True),
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

    # The only data guaranteed to exist when the user taps "share".
    url: Mapped[str] = mapped_column(Text, nullable=False)

    # Every column below is an enrichment result -- allowed to be empty until
    # scraping / Gemini / embedding finish (or fail).
    platform: Mapped[str | None] = mapped_column(Text, nullable=True)
    title: Mapped[str | None] = mapped_column(Text, nullable=True)
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Who wrote title/summary/category: "gemini:<model>", "groq:<model>", or
    # "user". Lets fallback-model results be re-done by the primary model
    # later without ever overwriting the user's own edits (see data-model.md).
    classified_by: Mapped[str | None] = mapped_column(Text, nullable=True)
    embedding: Mapped[list[float] | None] = mapped_column(Vector(768), nullable=True)

    # Folders (see data-model.md, "Folders: who decides"). NULL folder_id =
    # Unfiled. folder_by: "user" | "ai" | NULL. "ai" with folder_id still NULL
    # = the user asked the AI to pick, and it hasn't placed the item yet.
    folder_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("folders.id", ondelete="SET NULL"),
        nullable=True,
    )
    folder_by: Mapped[str | None] = mapped_column(Text, nullable=True)
    # The classifier's proposed folder NAME (existing or new), written in the
    # same call as title/summary. Only turned into a real folder when the user
    # taps "Let AI pick" (folders.apply_ai_folder).
    folder_suggestion: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    user: Mapped["User"] = relationship(back_populates="items")
    folder: Mapped["Folder | None"] = relationship()

    @property
    def folder_name(self) -> str | None:
        """Sent with the item so the app can show "Saved to X" right after the
        AI created X, without first re-fetching the folder list."""
        return self.folder.name if self.folder is not None else None

    @property
    def processed(self) -> bool:
        """raw_content NULL = not processed yet; "" or text = processed (enrichment.py)."""
        return self.raw_content is not None

    @property
    def has_content(self) -> bool:
        """Extraction managed to read the link's content. Separates the two
        "processed but no summary" cases: link unreadable (False) vs Gemini
        failed even though there was content (True, retryable via backfill)."""
        return bool(self.raw_content)

    __table_args__ = (
        Index("idx_saved_items_user_id", "user_id"),
        Index("idx_saved_items_folder_id", "folder_id"),
        # HNSW = approximate-nearest-neighbour index for vector search.
        # The operator class MUST match the operator used in queries:
        # vector_cosine_ops only serves `<=>`. A query that ORDER BYs `<->`
        # (L2) silently ignores this index and falls back to a full table scan.
        Index(
            "idx_saved_items_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
    )
