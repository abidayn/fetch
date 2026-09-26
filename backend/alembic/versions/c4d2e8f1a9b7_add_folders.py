"""add folders table and folder columns to saved_items

Revision ID: c4d2e8f1a9b7
Revises: b3f1c2d4e5a6
Create Date: 2026-09-26 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'c4d2e8f1a9b7'
down_revision: Union[str, Sequence[str], None] = 'b3f1c2d4e5a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Purely additive (a new table + nullable columns, no defaults): the
    # currently deployed code, which doesn't know about folders, keeps
    # working, so this can be applied before the new code is deployed.
    op.create_table(
        'folders',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('name', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    # Case-insensitive uniqueness per user (see data-model.md, table folders).
    op.create_index('uq_folders_user_name', 'folders', ['user_id', sa.text('lower(name)')], unique=True)

    op.add_column('saved_items', sa.Column('folder_id', postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column('saved_items', sa.Column('folder_by', sa.Text(), nullable=True))
    op.add_column('saved_items', sa.Column('folder_suggestion', sa.Text(), nullable=True))
    op.create_foreign_key(
        'saved_items_folder_id_fkey', 'saved_items', 'folders', ['folder_id'], ['id'], ondelete='SET NULL'
    )
    op.create_index('idx_saved_items_folder_id', 'saved_items', ['folder_id'])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('idx_saved_items_folder_id', table_name='saved_items')
    op.drop_constraint('saved_items_folder_id_fkey', 'saved_items', type_='foreignkey')
    op.drop_column('saved_items', 'folder_suggestion')
    op.drop_column('saved_items', 'folder_by')
    op.drop_column('saved_items', 'folder_id')
    op.drop_index('uq_folders_user_name', table_name='folders')
    op.drop_table('folders')
