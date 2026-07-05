"""Initial schema with pgvector extension."""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector

revision: str = "001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "users",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("hashed_password", sa.String(length=255), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=False),
        sa.Column("age", sa.Integer(), nullable=True),
        sa.Column("sex", sa.String(length=20), nullable=True),
        sa.Column("weight_kg", sa.Float(), nullable=True),
        sa.Column("height_cm", sa.Float(), nullable=True),
        sa.Column("activity_level", sa.String(length=30), nullable=True),
        sa.Column("experience_level", sa.String(length=30), nullable=True),
        sa.Column("injuries", sa.dialects.postgresql.JSONB(), nullable=True),
        sa.Column("equipment", sa.dialects.postgresql.JSONB(), nullable=True),
        sa.Column("dietary_preference", sa.String(length=30), nullable=True),
        sa.Column("workout_days_per_week", sa.Integer(), nullable=True),
        sa.Column("primary_goal", sa.String(length=30), nullable=True),
        sa.Column("onboarding_complete", sa.Boolean(), nullable=True),
        sa.Column("total_xp", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_users_email"), "users", ["email"], unique=True)

    op.create_table(
        "workout_plans",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("plan_data", sa.dialects.postgresql.JSONB(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_workout_plans_user_id"), "workout_plans", ["user_id"], unique=False)

    op.create_table(
        "nutrition_plans",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("plan_data", sa.dialects.postgresql.JSONB(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_nutrition_plans_user_id"), "nutrition_plans", ["user_id"], unique=False)

    op.create_table(
        "workout_logs",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("session_label", sa.String(length=200), nullable=False),
        sa.Column("exercises_completed", sa.dialects.postgresql.JSONB(), nullable=True),
        sa.Column("duration_minutes", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_workout_logs_user_id"), "workout_logs", ["user_id"], unique=False)

    op.create_table(
        "food_entries",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("meal_type", sa.String(length=50), nullable=True),
        sa.Column("items", sa.dialects.postgresql.JSONB(), nullable=False),
        sa.Column("total_calories", sa.Float(), nullable=True),
        sa.Column("total_protein_g", sa.Float(), nullable=True),
        sa.Column("total_carbs_g", sa.Float(), nullable=True),
        sa.Column("total_fat_g", sa.Float(), nullable=True),
        sa.Column("logged_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_food_entries_user_id"), "food_entries", ["user_id"], unique=False)

    op.create_table(
        "coach_messages",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("thread_id", sa.String(length=100), nullable=False),
        sa.Column("role", sa.String(length=20), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("embedding", Vector(768), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_coach_messages_thread_id"), "coach_messages", ["thread_id"], unique=False)
    op.create_index(op.f("ix_coach_messages_user_id"), "coach_messages", ["user_id"], unique=False)

    op.create_table(
        "knowledge_chunks",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("source_file", sa.String(length=500), nullable=False),
        sa.Column("category", sa.String(length=100), nullable=False),
        sa.Column("title", sa.String(length=300), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("embedding", Vector(768), nullable=True),
        sa.Column("metadata_json", sa.dialects.postgresql.JSONB(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_knowledge_chunks_category"), "knowledge_chunks", ["category"], unique=False)

    op.create_table(
        "form_sessions",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("exercise", sa.String(length=100), nullable=False),
        sa.Column("rep_count", sa.Integer(), nullable=False),
        sa.Column("duration_seconds", sa.Integer(), nullable=False),
        sa.Column("corrections", sa.dialects.postgresql.JSONB(), nullable=True),
        sa.Column("avg_rom_score", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_form_sessions_user_id"), "form_sessions", ["user_id"], unique=False)

    op.create_table(
        "habits",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("target_per_day", sa.Integer(), nullable=True),
        sa.Column("current_streak", sa.Integer(), nullable=True),
        sa.Column("last_checked_date", sa.String(length=10), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_habits_user_id"), "habits", ["user_id"], unique=False)

    op.create_table(
        "achievements",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("badge_id", sa.String(length=100), nullable=False),
        sa.Column("earned_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "badge_id", name="uq_user_badge"),
    )
    op.create_index(op.f("ix_achievements_user_id"), "achievements", ["user_id"], unique=False)

    op.create_table(
        "xp_ledger",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(length=200), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_xp_ledger_user_id"), "xp_ledger", ["user_id"], unique=False)

    op.create_table(
        "eval_runs",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("suite_name", sa.String(length=100), nullable=False),
        sa.Column("passed", sa.Boolean(), nullable=False),
        sa.Column("results", sa.dialects.postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    for table in [
        "eval_runs",
        "xp_ledger",
        "achievements",
        "habits",
        "form_sessions",
        "knowledge_chunks",
        "coach_messages",
        "food_entries",
        "workout_logs",
        "nutrition_plans",
        "workout_plans",
        "users",
    ]:
        op.drop_table(table)
