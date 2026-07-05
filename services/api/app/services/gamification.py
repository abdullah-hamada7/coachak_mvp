"""Gamification service: XP, streaks, badges."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db_models import AchievementRecord, FoodEntry, FormSession, HabitRecord, User, WorkoutLog, XPLedger

XP_REWARDS = {
    "workout_complete": 50,
    "food_log": 20,
    "macro_target": 30,
    "form_session": 40,
    "habit_check": 10,
}

BADGE_DEFINITIONS = {
    "first_workout": {"name": "First Steps", "description": "Complete your first workout"},
    "streak_7": {"name": "Week Warrior", "description": "7-day workout streak"},
    "reps_100": {"name": "Century Club", "description": "Track 100 reps with form analysis"},
    "macro_week": {"name": "Macro Master", "description": "Hit macro targets for 7 days"},
    "first_form": {"name": "Form Focus", "description": "Complete first form analysis session"},
}


def xp_to_level(total_xp: int) -> int:
    return max(1, total_xp // 200 + 1)


async def award_xp(db: AsyncSession, user: User, amount: int, reason: str) -> int:
    user.total_xp += amount
    db.add(XPLedger(user_id=user.id, amount=amount, reason=reason))
    return user.total_xp


async def check_and_award_badges(db: AsyncSession, user: User) -> list[str]:
    earned: list[str] = []
    existing = await db.execute(select(AchievementRecord.badge_id).where(AchievementRecord.user_id == user.id))
    existing_ids = set(existing.scalars().all())

    workout_count = await db.scalar(select(func.count()).select_from(WorkoutLog).where(WorkoutLog.user_id == user.id))
    form_reps = await db.scalar(
        select(func.coalesce(func.sum(FormSession.rep_count), 0)).where(FormSession.user_id == user.id)
    )
    form_count = await db.scalar(select(func.count()).select_from(FormSession).where(FormSession.user_id == user.id))

    checks = [
        ("first_workout", workout_count and workout_count >= 1),
        ("first_form", form_count and form_count >= 1),
        ("reps_100", form_reps and form_reps >= 100),
        ("streak_7", await _workout_streak(db, user.id) >= 7),
    ]

    for badge_id, condition in checks:
        if condition and badge_id not in existing_ids:
            db.add(AchievementRecord(user_id=user.id, badge_id=badge_id))
            earned.append(badge_id)

    return earned


async def _workout_streak(db: AsyncSession, user_id: UUID) -> int:
    result = await db.execute(
        select(WorkoutLog.completed_at)
        .where(WorkoutLog.user_id == user_id)
        .order_by(WorkoutLog.completed_at.desc())
        .limit(30)
    )
    dates = sorted({row.completed_at.date() for row in result}, reverse=True)
    if not dates:
        return 0

    streak = 0
    expected = date.today()
    for d in dates:
        if d == expected or d == expected - timedelta(days=1):
            streak += 1
            expected = d - timedelta(days=1)
        else:
            break
    return streak


async def _logging_streak(db: AsyncSession, user_id: UUID) -> int:
    result = await db.execute(
        select(FoodEntry.logged_at)
        .where(FoodEntry.user_id == user_id)
        .order_by(FoodEntry.logged_at.desc())
        .limit(30)
    )
    dates = sorted({row.logged_at.date() for row in result}, reverse=True)
    if not dates:
        return 0

    streak = 0
    expected = date.today()
    for d in dates:
        if d == expected or d == expected - timedelta(days=1):
            streak += 1
            expected = d - timedelta(days=1)
        else:
            break
    return streak


async def get_gamification_state(db: AsyncSession, user: User) -> dict:
    achievements = await db.execute(select(AchievementRecord).where(AchievementRecord.user_id == user.id))
    habits = await db.execute(select(HabitRecord).where(HabitRecord.user_id == user.id))
    today = date.today().isoformat()

    badge_list = []
    for ach in achievements.scalars():
        defn = BADGE_DEFINITIONS.get(ach.badge_id, {"name": ach.badge_id, "description": ""})
        badge_list.append({
            "id": ach.badge_id,
            "name": defn["name"],
            "description": defn["description"],
            "earned_at": ach.earned_at,
        })

    habit_list = []
    for h in habits.scalars():
        habit_list.append({
            "id": h.id,
            "name": h.name,
            "target_per_day": h.target_per_day,
            "checked_today": h.last_checked_date == today,
            "streak": h.current_streak,
        })

    return {
        "total_xp": user.total_xp,
        "level": xp_to_level(user.total_xp),
        "workout_streak": await _workout_streak(db, user.id),
        "logging_streak": await _logging_streak(db, user.id),
        "badges": badge_list,
        "habits": habit_list,
    }


async def check_habit(db: AsyncSession, habit: HabitRecord) -> HabitRecord:
    today = date.today().isoformat()
    if habit.last_checked_date == today:
        return habit

    yesterday = (date.today() - timedelta(days=1)).isoformat()
    if habit.last_checked_date == yesterday:
        habit.current_streak += 1
    else:
        habit.current_streak = 1
    habit.last_checked_date = today
    return habit
