"""Progress and gamification routes."""

from uuid import UUID

from datetime import UTC, date, datetime, time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.db_models import FoodEntry, FormSession, HabitRecord, NutritionPlanRecord, User, WorkoutLog
from app.services.gamification import (
    XP_REWARDS,
    award_xp,
    check_habit,
    get_gamification_state,
    xp_to_level,
)

router = APIRouter(prefix="", tags=["progress"])


class HabitCreate(BaseModel):
    name: str
    target_per_day: int = 1


@router.get("/progress/summary")
async def progress_summary(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    workouts = await db.scalar(select(func.count()).select_from(WorkoutLog).where(WorkoutLog.user_id == user.id))
    now_utc = datetime.now(UTC)
    today_start = datetime(now_utc.year, now_utc.month, now_utc.day, tzinfo=UTC)

    form_sessions = await db.scalar(select(func.count()).select_from(FormSession).where(FormSession.user_id == user.id))
    form_sessions_today = await db.scalar(
        select(func.count()).select_from(FormSession).where(
            FormSession.user_id == user.id,
            FormSession.created_at >= today_start,
        )
    )
    total_reps = await db.scalar(
        select(func.coalesce(func.sum(FormSession.rep_count), 0)).where(FormSession.user_id == user.id)
    )
    avg_cal = await db.scalar(
        select(func.avg(FoodEntry.total_calories)).where(FoodEntry.user_id == user.id)
    )

    today_cals = await db.scalar(
        select(func.coalesce(func.sum(FoodEntry.total_calories), 0)).where(FoodEntry.user_id == user.id, FoodEntry.logged_at >= today_start)
    )
    today_protein = await db.scalar(
        select(func.coalesce(func.sum(FoodEntry.total_protein_g), 0)).where(FoodEntry.user_id == user.id, FoodEntry.logged_at >= today_start)
    )
    today_carbs = await db.scalar(
        select(func.coalesce(func.sum(FoodEntry.total_carbs_g), 0)).where(FoodEntry.user_id == user.id, FoodEntry.logged_at >= today_start)
    )
    today_fat = await db.scalar(
        select(func.coalesce(func.sum(FoodEntry.total_fat_g), 0)).where(FoodEntry.user_id == user.id, FoodEntry.logged_at >= today_start)
    )

    nutrition = await db.execute(
        select(NutritionPlanRecord)
        .where(NutritionPlanRecord.user_id == user.id, NutritionPlanRecord.is_active == True)
        .order_by(NutritionPlanRecord.created_at.desc())
        .limit(1)
    )
    nutrition_plan = nutrition.scalar_one_or_none()

    target_macros = {
        "calories": 2000,
        "protein_g": 150,
        "carbs_g": 220,
        "fat_g": 65,
    }
    if nutrition_plan and isinstance(nutrition_plan.plan_data, dict):
        plan_targets = nutrition_plan.plan_data.get("target_macros", {})
        if plan_targets:
            target_macros["calories"] = plan_targets.get("calories", 2000)
            target_macros["protein_g"] = plan_targets.get("protein_g", 150)
            target_macros["carbs_g"] = plan_targets.get("carbs_g", 220)
            target_macros["fat_g"] = plan_targets.get("fat_g", 65)

    macro_adherence = None
    if avg_cal and target_macros["calories"]:
        macro_adherence = round(min(100, (avg_cal / target_macros["calories"]) * 100), 1)

    return {
        "workouts_completed": workouts or 0,
        "total_reps_tracked": int(total_reps or 0),
        "avg_daily_calories": round(avg_cal, 1) if avg_cal else None,
        "macro_adherence_pct": macro_adherence,
        "form_sessions": form_sessions or 0,
        "form_sessions_today": form_sessions_today or 0,
        "xp": user.total_xp,
        "level": xp_to_level(user.total_xp),
        "today_macros": {
            "calories": round(today_cals or 0, 1),
            "protein_g": round(today_protein or 0, 1),
            "carbs_g": round(today_carbs or 0, 1),
            "fat_g": round(today_fat or 0, 1),
        },
        "target_macros": target_macros,
    }


@router.get("/gamification/state")
async def gamification_state(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await get_gamification_state(db, user)


@router.post("/gamification/habits")
async def create_habit(
    body: HabitCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    habit = HabitRecord(user_id=user.id, name=body.name, target_per_day=body.target_per_day)
    db.add(habit)
    await db.flush()
    return {"id": habit.id, "name": habit.name}


@router.post("/gamification/habits/{habit_id}/check")
async def check_habit_today(
    habit_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(HabitRecord).where(HabitRecord.id == habit_id, HabitRecord.user_id == user.id)
    )
    habit = result.scalar_one_or_none()
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found")

    await check_habit(db, habit)
    await award_xp(db, user, XP_REWARDS["habit_check"], "habit_check")
    await db.flush()
    return {"checked": True, "streak": habit.current_streak, "xp_awarded": XP_REWARDS["habit_check"]}
