"""Add subscription tier and usage tracking to users."""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "002_subscriptions"
down_revision: Union[str, None] = "001_initial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("subscription_tier", sa.String(length=30), nullable=False, server_default="free"))
    op.add_column("users", sa.Column("subscription_product_id", sa.String(length=100), nullable=True))
    op.add_column("users", sa.Column("subscription_expires_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("usage_period_start", sa.DateTime(timezone=True), nullable=True))
    op.add_column(
        "users",
        sa.Column("usage_counters", sa.dialects.postgresql.JSONB(), nullable=False, server_default="{}"),
    )


def downgrade() -> None:
    op.drop_column("users", "usage_counters")
    op.drop_column("users", "usage_period_start")
    op.drop_column("users", "subscription_expires_at")
    op.drop_column("users", "subscription_product_id")
    op.drop_column("users", "subscription_tier")
