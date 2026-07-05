"""SQLAlchemy database models."""

import uuid
from datetime import UTC, datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.config import get_settings
from app.core.database import Base

settings = get_settings()


def utcnow() -> datetime:
    return datetime.now(UTC)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(100))
    age: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sex: Mapped[str | None] = mapped_column(String(20), nullable=True)
    weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    height_cm: Mapped[float | None] = mapped_column(Float, nullable=True)
    activity_level: Mapped[str | None] = mapped_column(String(30), nullable=True)
    experience_level: Mapped[str | None] = mapped_column(String(30), nullable=True)
    injuries: Mapped[list] = mapped_column(JSONB, default=list)
    equipment: Mapped[list] = mapped_column(JSONB, default=list)
    dietary_preference: Mapped[str | None] = mapped_column(String(30), nullable=True)
    workout_days_per_week: Mapped[int | None] = mapped_column(Integer, nullable=True)
    primary_goal: Mapped[str | None] = mapped_column(String(30), nullable=True)
    onboarding_complete: Mapped[bool] = mapped_column(Boolean, default=False)
    total_xp: Mapped[int] = mapped_column(Integer, default=0)
    subscription_tier: Mapped[str] = mapped_column(String(30), default="free")
    subscription_product_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    subscription_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    usage_period_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    usage_counters: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    workout_plans = relationship("WorkoutPlanRecord", back_populates="user")
    nutrition_plans = relationship("NutritionPlanRecord", back_populates="user")
    coach_messages = relationship("CoachMessage", back_populates="user")
    habits = relationship("HabitRecord", back_populates="user")
    achievements = relationship("AchievementRecord", back_populates="user")


class WorkoutPlanRecord(Base):
    __tablename__ = "workout_plans"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    plan_data: Mapped[dict] = mapped_column(JSONB)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="workout_plans")


class NutritionPlanRecord(Base):
    __tablename__ = "nutrition_plans"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    plan_data: Mapped[dict] = mapped_column(JSONB)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="nutrition_plans")


class WorkoutLog(Base):
    __tablename__ = "workout_logs"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    session_label: Mapped[str] = mapped_column(String(200))
    exercises_completed: Mapped[list] = mapped_column(JSONB, default=list)
    duration_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    completed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class FoodEntry(Base):
    __tablename__ = "food_entries"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    meal_type: Mapped[str] = mapped_column(String(50), default="other")
    items: Mapped[list] = mapped_column(JSONB)
    total_calories: Mapped[float] = mapped_column(Float, default=0)
    total_protein_g: Mapped[float] = mapped_column(Float, default=0)
    total_carbs_g: Mapped[float] = mapped_column(Float, default=0)
    total_fat_g: Mapped[float] = mapped_column(Float, default=0)
    logged_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class CoachMessage(Base):
    __tablename__ = "coach_messages"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    thread_id: Mapped[str] = mapped_column(String(100), index=True)
    role: Mapped[str] = mapped_column(String(20))
    content: Mapped[str] = mapped_column(Text)
    embedding = mapped_column(Vector(settings.embedding_dimensions), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="coach_messages")


class KnowledgeChunk(Base):
    __tablename__ = "knowledge_chunks"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    source_file: Mapped[str] = mapped_column(String(500))
    category: Mapped[str] = mapped_column(String(100), index=True)
    title: Mapped[str] = mapped_column(String(300))
    content: Mapped[str] = mapped_column(Text)
    embedding = mapped_column(Vector(settings.embedding_dimensions), nullable=True)
    metadata_json: Mapped[dict] = mapped_column(JSONB, default=dict)


class FormSession(Base):
    __tablename__ = "form_sessions"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    exercise: Mapped[str] = mapped_column(String(100))
    rep_count: Mapped[int] = mapped_column(Integer)
    duration_seconds: Mapped[int] = mapped_column(Integer)
    corrections: Mapped[list] = mapped_column(JSONB, default=list)
    avg_rom_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class HabitRecord(Base):
    __tablename__ = "habits"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    target_per_day: Mapped[int] = mapped_column(Integer, default=1)
    current_streak: Mapped[int] = mapped_column(Integer, default=0)
    last_checked_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="habits")


class AchievementRecord(Base):
    __tablename__ = "achievements"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    badge_id: Mapped[str] = mapped_column(String(100))
    earned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="achievements")
    __table_args__ = (UniqueConstraint("user_id", "badge_id", name="uq_user_badge"),)


class XPLedger(Base):
    __tablename__ = "xp_ledger"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True)
    amount: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class EvalRun(Base):
    __tablename__ = "eval_runs"

    id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    suite_name: Mapped[str] = mapped_column(String(100))
    passed: Mapped[bool] = mapped_column(Boolean)
    results: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
