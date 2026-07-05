"""User profile routes."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.db_models import User

router = APIRouter(prefix="/users", tags=["users"])


class UserProfileUpdate(BaseModel):
    display_name: str | None = None
    age: int | None = Field(default=None, ge=13, le=100)
    sex: str | None = None
    weight_kg: float | None = Field(default=None, gt=0)
    height_cm: float | None = Field(default=None, gt=0)
    activity_level: str | None = None
    experience_level: str | None = None
    injuries: list[str] | None = None
    equipment: list[str] | None = None
    dietary_preference: str | None = None
    workout_days_per_week: int | None = Field(default=None, ge=1, le=7)
    primary_goal: str | None = None
    onboarding_complete: bool | None = None


class UserProfileResponse(BaseModel):
    id: UUID
    email: str
    display_name: str
    age: int | None = None
    sex: str | None = None
    weight_kg: float | None = None
    height_cm: float | None = None
    activity_level: str | None = None
    experience_level: str | None = None
    injuries: list[str] = []
    equipment: list[str] = []
    dietary_preference: str | None = None
    workout_days_per_week: int | None = None
    primary_goal: str | None = None
    onboarding_complete: bool = False
    created_at: datetime


def _to_response(user: User) -> UserProfileResponse:
    return UserProfileResponse(
        id=user.id,
        email=user.email,
        display_name=user.display_name,
        age=user.age,
        sex=user.sex,
        weight_kg=user.weight_kg,
        height_cm=user.height_cm,
        activity_level=user.activity_level,
        experience_level=user.experience_level,
        injuries=user.injuries or [],
        equipment=user.equipment or [],
        dietary_preference=user.dietary_preference,
        workout_days_per_week=user.workout_days_per_week,
        primary_goal=user.primary_goal,
        onboarding_complete=user.onboarding_complete,
        created_at=user.created_at,
    )


@router.get("/me", response_model=UserProfileResponse)
async def get_profile(user: User = Depends(get_current_user)):
    return _to_response(user)


@router.patch("/me", response_model=UserProfileResponse)
async def update_profile(
    body: UserProfileUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(user, field, value)
    await db.flush()
    return _to_response(user)
