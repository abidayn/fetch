"""add saved_items.author; mark existing Unsorted items as left there

Revision ID: d7a3e9c15b20
Revises: c4d2e8f1a9b7
Create Date: 2026-09-26 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd7a3e9c15b20'
down_revision: Union[str, Sequence[str], None] = 'c4d2e8f1a9b7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Nullable, no default: safe to apply before the code that uses it.
    op.add_column('saved_items', sa.Column('author', sa.Text(), nullable=True))

    # The author was always extracted, but only survived as an "Author: ..."
    # line inside raw_content (extraction.Extracted.to_text). Copy it out.
    # (?n) = newline-sensitive: ^/$ match at line breaks and . stops at one,
    # so this takes exactly that line's value.
    op.execute(r"""
        UPDATE saved_items
        SET author = NULLIF(btrim(substring(raw_content from '(?n)^Author: (.*)$')), '')
        WHERE raw_content LIKE '%Author: %'
    """)

    # Items saved before "nobody decided" meant "needs you" would otherwise
    # all land in the app's Needs you list. They've been Unsorted all along:
    # record that as the user's choice (folder_by = 'user', no folder).
    op.execute("""
        UPDATE saved_items
        SET folder_by = 'user'
        WHERE folder_id IS NULL AND folder_by IS NULL
    """)


def downgrade() -> None:
    """Downgrade schema."""
    # The "left in Unsorted" marks can't be told apart from real choices
    # afterwards, so they stay; they're harmless to the older code.
    op.drop_column('saved_items', 'author')
