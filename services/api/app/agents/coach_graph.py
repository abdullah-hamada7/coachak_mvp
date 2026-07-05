"""LangGraph coach orchestrator with multi-agent routing."""

from __future__ import annotations

import json
import uuid
from typing import Any, TypedDict

from langgraph.graph import END, StateGraph

from app.agents.coach_intent import (
    INTENT_BOTH,
    INTENT_CHAT,
    INTENT_NUTRITION,
    INTENT_WORKOUT,
    classify_message_intent,
)
from app.agents.planners import generate_nutrition_plan, generate_workout_plan
from app.models.db_models import User
from app.services.fitness_rules import validate_workout_plan
from app.services.groq import generate_text
from app.core.config import get_settings
from app.services.memory import retrieve_episodic_memory, retrieve_knowledge, store_coach_message
from app.services.rag.context import categories_for_message, format_rag_context

settings = get_settings()


class CoachState(TypedDict, total=False):
    user: dict
    message: str
    thread_id: str
    intent: str
    rag_context: str
    episodic_context: str
    response: str
    plan: dict | None
    plan_type: str | None
    nutrition_plan: dict | None
    safety_result: dict | None
    db: Any
    _retry: int


async def classify_intent(state: CoachState) -> CoachState:
    state["intent"] = classify_message_intent(state["message"])
    return state


async def retrieve_context(state: CoachState) -> CoachState:
    db = state.get("db")
    if db is None:
        state["rag_context"] = ""
        state["episodic_context"] = ""
        return state

    intent = state.get("intent", INTENT_CHAT)
    categories = categories_for_message(intent, state["message"])
    knowledge = await retrieve_knowledge(db, state["message"], categories=categories)
    state["rag_context"] = format_rag_context(
        knowledge,
        min_score=settings.rag_min_rrf_score,
    )

    user_data = state.get("user", {})
    if user_data.get("id"):
        from uuid import UUID

        episodic = await retrieve_episodic_memory(
            db,
            UUID(str(user_data["id"])),
            state["message"],
            thread_id=state.get("thread_id"),
            exclude_content=state["message"],
        )
        state["episodic_context"] = "\n".join(
            f"{e['role']}: {e['content'][:200]}" for e in episodic
        )
    return state


async def route_workout(state: CoachState) -> CoachState:
    user_dict = state["user"]
    user = _dict_to_user(user_dict)
    plan = await generate_workout_plan(user, state.get("rag_context", ""))

    passed, issues, suggestions = validate_workout_plan(plan, user.injuries or [])
    state["safety_result"] = {"passed": passed, "issues": issues, "suggestions": suggestions}

    if not passed and state.get("_retry", 0) < 2:
        state["_retry"] = state.get("_retry", 0) + 1
        plan = await generate_workout_plan(user, state.get("rag_context", "") + "\nAvoid: " + "; ".join(issues))

    state["plan"] = plan
    state["plan_type"] = "workout"
    state["response"] = (
        f"I've created your **{plan.get('title', 'Workout Plan')}** with "
        f"{len(plan.get('sessions', []))} sessions over {plan.get('weeks', 4)} weeks. "
        f"{plan.get('progression_notes', '')}"
    )
    return state


async def route_nutrition(state: CoachState) -> CoachState:
    user = _dict_to_user(state["user"])
    plan = await generate_nutrition_plan(user, state.get("rag_context", ""))
    state["nutrition_plan"] = plan
    state["plan"] = plan
    state["plan_type"] = "nutrition"
    macros = plan.get("target_macros", {})
    state["response"] = (
        f"Your nutrition plan targets **{macros.get('calories', 2000)} calories/day** with "
        f"{macros.get('protein_g', 150)}g protein. {plan.get('notes', '')}"
    )
    return state


async def route_both(state: CoachState) -> CoachState:
    state = await route_workout(state)
    workout_plan = state["plan"]
    workout_text = state["response"]

    user = _dict_to_user(state["user"])
    nutrition_plan = await generate_nutrition_plan(user, state.get("rag_context", ""))
    macros = nutrition_plan.get("target_macros", {})
    nutrition_text = (
        f"Your nutrition plan targets **{macros.get('calories', 2000)} calories/day** with "
        f"{macros.get('protein_g', 150)}g protein. {nutrition_plan.get('notes', '')}"
    )

    state["nutrition_plan"] = nutrition_plan
    state["plan"] = {"workout": workout_plan, "nutrition": nutrition_plan}
    state["plan_type"] = "both"
    state["response"] = f"{workout_text}\n\n{nutrition_text}"
    return state


async def route_chat(state: CoachState) -> CoachState:
    user = state.get("user", {})
    system = (
        "You are Coachak, an expert AI fitness coach. Be motivating, concise, and evidence-based. "
        "Never prescribe dangerous exercises. Reference the user's profile when relevant. "
        "Answer the user's actual question directly. "
        "For nutrition questions (including post-workout meals), give practical food and macro advice. "
        "For equipment limits (e.g. only dumbbells), suggest exercise swaps — do not generate a full multi-week plan. "
        "For progress checks, summarize what to track and give actionable next steps. "
        "Do not say you created a multi-week plan unless the user explicitly asked for one."
    )
    prompt = (
        f"User profile: {json.dumps(user, default=str)}\n"
        f"Knowledge context:\n{state.get('rag_context', '')}\n"
        f"Past conversations:\n{state.get('episodic_context', '')}\n"
        f"User message: {state['message']}"
    )
    state["response"] = await generate_text(prompt, system=system)
    state["plan"] = None
    state["plan_type"] = None
    return state


async def safety_check(state: CoachState) -> CoachState:
    if state.get("plan_type") not in ("workout", "both") or not state.get("plan"):
        return state

    workout_plan = state["plan"]
    if state.get("plan_type") == "both" and isinstance(workout_plan, dict):
        workout_plan = workout_plan.get("workout") or workout_plan

    user = _dict_to_user(state["user"])
    passed, issues, suggestions = validate_workout_plan(workout_plan, user.injuries or [])
    state["safety_result"] = {"passed": passed, "issues": issues, "suggestions": suggestions}
    if not passed:
        state["response"] += f"\n\n⚠️ Safety note: {'; '.join(suggestions[:2])}"
    return state


def route_by_intent(state: CoachState) -> str:
    intent = state.get("intent", INTENT_CHAT)
    if intent == INTENT_WORKOUT:
        return "workout"
    if intent == INTENT_NUTRITION:
        return "nutrition"
    if intent == INTENT_BOTH:
        return "both"
    return "chat"


def build_coach_graph():
    graph = StateGraph(CoachState)
    graph.add_node("classify", classify_intent)
    graph.add_node("retrieve", retrieve_context)
    graph.add_node("workout", route_workout)
    graph.add_node("nutrition", route_nutrition)
    graph.add_node("both", route_both)
    graph.add_node("chat", route_chat)
    graph.add_node("safety", safety_check)

    graph.set_entry_point("classify")
    graph.add_edge("classify", "retrieve")
    graph.add_conditional_edges(
        "retrieve",
        route_by_intent,
        {
            "workout": "workout",
            "nutrition": "nutrition",
            "both": "both",
            "chat": "chat",
        },
    )
    graph.add_edge("workout", "safety")
    graph.add_edge("both", "safety")
    graph.add_edge("safety", END)
    graph.add_edge("nutrition", END)
    graph.add_edge("chat", END)

    return graph.compile()


def _dict_to_user(d: dict) -> User:
    user = User(
        email=d.get("email", ""),
        hashed_password="",
        display_name=d.get("display_name", ""),
    )
    user.id = d.get("id") if isinstance(d.get("id"), uuid.UUID) else uuid.UUID(str(d["id"]))
    user.age = d.get("age")
    user.sex = d.get("sex")
    user.weight_kg = d.get("weight_kg")
    user.height_cm = d.get("height_cm")
    user.activity_level = d.get("activity_level")
    user.experience_level = d.get("experience_level")
    user.injuries = d.get("injuries", [])
    user.equipment = d.get("equipment", [])
    user.dietary_preference = d.get("dietary_preference")
    user.workout_days_per_week = d.get("workout_days_per_week")
    user.primary_goal = d.get("primary_goal")
    return user


async def run_coach(
    db,
    user: User,
    message: str,
    thread_id: str | None = None,
) -> dict[str, Any]:
    graph = build_coach_graph()
    thread_id = thread_id or str(uuid.uuid4())

    user_dict = {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "age": user.age,
        "sex": user.sex,
        "weight_kg": user.weight_kg,
        "height_cm": user.height_cm,
        "activity_level": user.activity_level,
        "experience_level": user.experience_level,
        "injuries": user.injuries or [],
        "equipment": user.equipment or [],
        "dietary_preference": user.dietary_preference,
        "workout_days_per_week": user.workout_days_per_week,
        "primary_goal": user.primary_goal,
    }

    result = await graph.ainvoke({
        "user": user_dict,
        "message": message,
        "thread_id": thread_id,
        "db": db,
    })

    response = result.get("response", "")
    await store_coach_message(db, user.id, thread_id, "user", message)
    await store_coach_message(db, user.id, thread_id, "assistant", response)

    return {
        "thread_id": thread_id,
        "response": response,
        "intent": result.get("intent"),
        "plan": result.get("plan"),
        "plan_type": result.get("plan_type"),
        "safety_result": result.get("safety_result"),
    }
