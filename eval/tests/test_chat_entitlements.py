"""Tests for chat route plan entitlement checks."""

import pytest
from fastapi import HTTPException

from app.agents.coach_intent import INTENT_WORKOUT
from app.models.db_models import User
from app.routes.chat import _check_plan_entitlements


def _user(**kwargs) -> User:
    user = User(email="t@example.com", hashed_password="x", display_name="Test")
    for key, value in kwargs.items():
        setattr(user, key, value)
    return user


def test_chat_plan_request_checks_workout_quota_for_free_user():
    user = _user(
        usage_counters={
            "workout_generations": 1,
            "week_start": "2026-06-23",
        }
    )
    with pytest.raises(HTTPException) as exc:
        _check_plan_entitlements(user, INTENT_WORKOUT)
    assert exc.value.status_code == 402


def test_chat_advice_does_not_require_workout_quota():
    from app.agents.coach_intent import INTENT_CHAT

    user = _user(
        usage_counters={
            "workout_generations": 1,
            "week_start": "2026-06-23",
        }
    )
    _check_plan_entitlements(user, INTENT_CHAT)
