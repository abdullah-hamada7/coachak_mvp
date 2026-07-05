"""Add GIN index for knowledge chunk full-text search."""

from typing import Sequence, Union

from alembic import op

revision: str = "003_rag_fts"
down_revision: Union[str, None] = "002_subscriptions"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_knowledge_chunks_fts
        ON knowledge_chunks
        USING GIN (to_tsvector('english', coalesce(title, '') || ' ' || content))
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_knowledge_chunks_fts")
