"""Subscription status, catalog, and activation routes."""

from pydantic import BaseModel, Field

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.db_models import User
from app.services.subscriptions import PLAN_CATALOG, activate_product, subscription_status_payload

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


class ActivateRequest(BaseModel):
    product_id: str = Field(min_length=1, max_length=100)


@router.get("/plans")
async def list_plans():
    return {"plans": PLAN_CATALOG, "currency": "EGP"}


@router.get("/status")
async def get_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    payload = subscription_status_payload(user)
    await db.flush()
    return payload


@router.post("/activate")
async def activate_subscription(
    body: ActivateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Activate a plan by product_id.

    MVP: called after App Store / Play purchase or for development testing.
    Production should validate receipts via RevenueCat or store webhooks.
    """
    payload = activate_product(user, body.product_id)
    await db.flush()
    return payload
