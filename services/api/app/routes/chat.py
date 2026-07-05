"""Coach chat routes with SSE streaming."""

import json
import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sse_starlette.sse import EventSourceResponse

from app.agents.coach_graph import run_coach
from app.agents.coach_intent import INTENT_BOTH, INTENT_NUTRITION, INTENT_WORKOUT, classify_message_intent
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.db_models import NutritionPlanRecord, User, WorkoutPlanRecord
from app.services.subscriptions import check_feature_access, consume_feature

router = APIRouter(prefix="/chat", tags=["chat"])
logger = logging.getLogger("coachak.chat")


class ChatRequest(BaseModel):
    message: str
    thread_id: str | None = None


def _check_plan_entitlements(user: User, intent: str) -> None:
    if intent in (INTENT_WORKOUT, INTENT_BOTH):
        check_feature_access(user, "workout_generations")
    if intent in (INTENT_NUTRITION, INTENT_BOTH):
        check_feature_access(user, "nutrition_generations")


def _consume_plan_usage(user: User, plan_type: str | None) -> None:
    if plan_type in ("workout", "both"):
        consume_feature(user, "workout_generations")
    if plan_type in ("nutrition", "both"):
        consume_feature(user, "nutrition_generations")


@router.post("/stream")
async def chat_stream(
    body: ChatRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    check_feature_access(user, "chat_messages")
    intent = classify_message_intent(body.message)
    _check_plan_entitlements(user, intent)

    async def event_generator():
        yield {"event": "start", "data": json.dumps({"status": "thinking"})}

        try:
            result = await run_coach(db, user, body.message, body.thread_id)
        except HTTPException as exc:
            if exc.status_code == 402:
                yield {
                    "event": "error",
                    "data": json.dumps({"status": "subscription_limit", "detail": exc.detail}),
                }
                yield {"event": "done", "data": json.dumps({"status": "complete"})}
                return
            raise
        except Exception:
            logger.exception("Coach stream failed")
            result = {
                "thread_id": body.thread_id or "fallback",
                "response": "I hit a temporary coaching error. Try again in a moment, or ask for a workout or nutrition plan.",
                "intent": "chat",
                "plan_type": None,
                "plan": None,
            }

        plan_type = result.get("plan_type")
        plan = result.get("plan")

        if plan and plan_type == "workout":
            await _deactivate_plans(db, user, WorkoutPlanRecord)
            db.add(WorkoutPlanRecord(user_id=user.id, plan_data=plan, is_active=True))
        elif plan and plan_type == "nutrition":
            await _deactivate_plans(db, user, NutritionPlanRecord)
            db.add(NutritionPlanRecord(user_id=user.id, plan_data=plan, is_active=True))
        elif plan and plan_type == "both" and isinstance(plan, dict):
            workout_plan = plan.get("workout")
            nutrition_plan = plan.get("nutrition")
            if workout_plan:
                await _deactivate_plans(db, user, WorkoutPlanRecord)
                db.add(WorkoutPlanRecord(user_id=user.id, plan_data=workout_plan, is_active=True))
            if nutrition_plan:
                await _deactivate_plans(db, user, NutritionPlanRecord)
                db.add(NutritionPlanRecord(user_id=user.id, plan_data=nutrition_plan, is_active=True))

        if plan_type:
            _consume_plan_usage(user, plan_type)

        consume_feature(user, "chat_messages")
        await db.flush()

        yield {"event": "message", "data": json.dumps({
            "thread_id": result["thread_id"],
            "content": result["response"],
            "intent": result.get("intent"),
            "plan_type": plan_type,
        })}

        if plan:
            yield {"event": "plan", "data": json.dumps({
                "plan_type": plan_type,
                "plan": plan,
            })}

        yield {"event": "done", "data": json.dumps({"status": "complete"})}

    return EventSourceResponse(event_generator())


async def _deactivate_plans(db, user, model):
    from sqlalchemy import update
    await db.execute(
        update(model).where(model.user_id == user.id, model.is_active == True).values(is_active=False)
    )
