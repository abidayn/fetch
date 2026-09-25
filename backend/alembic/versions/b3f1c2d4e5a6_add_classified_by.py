"""add classified_by to saved_items

Revision ID: b3f1c2d4e5a6
Revises: 66de89f6cd67
Create Date: 2026-09-25 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b3f1c2d4e5a6'
down_revision: Union[str, Sequence[str], None] = '66de89f6cd67'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Nullable, no default: existing rows stay NULL ("unknown"), and the
    # currently deployed code (which doesn't know this column) keeps working,
    # so this can be applied before the new code is deployed.
    op.add_column('saved_items', sa.Column('classified_by', sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('saved_items', 'classified_by')
