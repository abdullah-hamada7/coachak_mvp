"""Workout and nutrition plan routes."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.planners import generate_nutrition_plan, generate_workout_plan
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.db_models import NutritionPlanRecord, User, WorkoutPlanRecord
from app.services.memory import retrieve_knowledge
from app.services.subscriptions import check_feature_access, consume_feature

router = APIRouter(prefix="/plans", tags=["plans"])


class PlanResponse(BaseModel):
    id: UUID
    plan: dict
    is_active: bool
    created_at: datetime


@router.post("/workout/generate", response_model=PlanResponse)
async def generate_workout(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    check_feature_access(user, "workout_generations")
    rag = await retrieve_knowledge(db, f"workout plan {user.primary_goal}")
    context = "\n".join(k["content"][:300] for k in rag)
    plan = await generate_workout_plan(user, context)

    await db.execute(
        update(WorkoutPlanRecord)
        .where(WorkoutPlanRecord.user_id == user.id, WorkoutPlanRecord.is_active == True)
        .values(is_active=False)
    )
    record = WorkoutPlanRecord(user_id=user.id, plan_data=plan, is_active=True)
    db.add(record)
    consume_feature(user, "workout_generations")
    await db.flush()
    return PlanResponse(id=record.id, plan=plan, is_active=True, created_at=record.created_at)


@router.get("/workout/active", response_model=PlanResponse | None)
async def get_active_workout(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(WorkoutPlanRecord)
        .where(WorkoutPlanRecord.user_id == user.id, WorkoutPlanRecord.is_active == True)
        .order_by(WorkoutPlanRecord.created_at.desc())
        .limit(1)
    )
    record = result.scalar_one_or_none()
    if not record:
        return None
    return PlanResponse(id=record.id, plan=record.plan_data, is_active=True, created_at=record.created_at)


@router.post("/nutrition/generate", response_model=PlanResponse)
async def generate_nutrition(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    check_feature_access(user, "nutrition_generations")
    rag = await retrieve_knowledge(db, f"nutrition {user.primary_goal}")
    context = "\n".join(k["content"][:300] for k in rag)
    plan = await generate_nutrition_plan(user, context)

    await db.execute(
        update(NutritionPlanRecord)
        .where(NutritionPlanRecord.user_id == user.id, NutritionPlanRecord.is_active == True)
        .values(is_active=False)
    )
    record = NutritionPlanRecord(user_id=user.id, plan_data=plan, is_active=True)
    db.add(record)
    consume_feature(user, "nutrition_generations")
    await db.flush()
    return PlanResponse(id=record.id, plan=plan, is_active=True, created_at=record.created_at)


@router.get("/nutrition/active", response_model=PlanResponse | None)
async def get_active_nutrition(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(NutritionPlanRecord)
        .where(NutritionPlanRecord.user_id == user.id, NutritionPlanRecord.is_active == True)
        .order_by(NutritionPlanRecord.created_at.desc())
        .limit(1)
    )
    record = result.scalar_one_or_none()
    if not record:
        return None
    return PlanResponse(id=record.id, plan=record.plan_data, is_active=True, created_at=record.created_at)
