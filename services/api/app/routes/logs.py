"""Logging routes for workouts and food."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.db_models import FoodEntry, User, WorkoutLog
from app.services.gamification import XP_REWARDS, award_xp, check_and_award_badges

router = APIRouter(prefix="/logs", tags=["logs"])


class WorkoutLogCreate(BaseModel):
    session_label: str
    exercises_completed: list[str] = Field(default_factory=list)
    duration_minutes: int | None = None
    notes: str | None = None
    completed_at: datetime | None = None


class FoodItem(BaseModel):
    name: str
    portion_estimate: str = "1 serving"
    confidence: float = Field(default=1.0, ge=0, le=1)
    usda_fdc_id: int | None = None
    calories: float | None = None
    protein_g: float | None = None
    carbs_g: float | None = None
    fat_g: float | None = None

    @field_validator("name", mode="before")
    @classmethod
    def normalize_name(cls, value: object) -> str:
        text = str(value or "").strip()
        return text or "Meal"

    @field_validator("confidence", mode="before")
    @classmethod
    def normalize_confidence(cls, value: object) -> float:
        if value is None:
            return 1.0
        confidence = float(value)
        if confidence > 1:
            confidence /= 100
        return max(0.0, min(1.0, confidence))

    @field_validator("calories", "protein_g", "carbs_g", "fat_g", mode="before")
    @classmethod
    def normalize_numbers(cls, value: object) -> float | None:
        if value is None or value == "":
            return None
        return float(value)


class FoodLogCreate(BaseModel):
    items: list[FoodItem]
    meal_type: str = "other"
    logged_at: datetime | None = None

    @model_validator(mode="after")
    def require_items(self) -> "FoodLogCreate":
        if not self.items:
            raise ValueError("At least one food item is required")
        return self


@router.post("/workout")
async def log_workout(
    body: WorkoutLogCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    log = WorkoutLog(
        user_id=user.id,
        session_label=body.session_label,
        exercises_completed=body.exercises_completed,
        duration_minutes=body.duration_minutes,
        notes=body.notes,
        completed_at=body.completed_at or datetime.now(UTC),
    )
    db.add(log)
    await award_xp(db, user, XP_REWARDS["workout_complete"], "workout_complete")
    badges = await check_and_award_badges(db, user)
    await db.flush()
    return {"status": "logged", "xp_awarded": XP_REWARDS["workout_complete"], "new_badges": badges}


@router.post("/food")
async def log_food(
    body: FoodLogCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not body.items:
        raise HTTPException(status_code=400, detail="At least one food item is required")

    total_cal = sum(i.calories or 0 for i in body.items)
    total_p = sum(i.protein_g or 0 for i in body.items)
    total_c = sum(i.carbs_g or 0 for i in body.items)
    total_f = sum(i.fat_g or 0 for i in body.items)

    entry = FoodEntry(
        user_id=user.id,
        meal_type=body.meal_type,
        items=[i.model_dump() for i in body.items],
        total_calories=total_cal,
        total_protein_g=total_p,
        total_carbs_g=total_c,
        total_fat_g=total_f,
        logged_at=body.logged_at or datetime.now(UTC),
    )
    db.add(entry)
    await award_xp(db, user, XP_REWARDS["food_log"], "food_log")
    await db.flush()
    return {
        "status": "logged",
        "totals": {"calories": total_cal, "protein_g": total_p, "carbs_g": total_c, "fat_g": total_f},
        "xp_awarded": XP_REWARDS["food_log"],
    }
