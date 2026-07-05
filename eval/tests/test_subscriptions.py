"""Unit tests for subscription tiers and usage limits."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.models.db_models import User
from app.services.subscriptions import (
    TIER_COACH_PRO,
    TIER_ELITE,
    TIER_FREE,
    TIER_TRAIN,
    activate_product,
    check_feature_access,
    consume_feature,
    effective_tier,
    subscription_status_payload,
)


def _user(**kwargs) -> User:
    user = User(
        email="test@example.com",
        hashed_password="x",
        display_name="Test",
    )
    for key, value in kwargs.items():
        setattr(user, key, value)
    return user


def test_effective_tier_free_by_default():
    user = _user()
    assert effective_tier(user) == TIER_FREE


def test_effective_tier_expired_falls_back_to_free():
    user = _user(
        subscription_tier=TIER_COACH_PRO,
        subscription_expires_at=datetime.now(UTC) - timedelta(days=1),
    )
    assert effective_tier(user) == TIER_FREE


def test_free_chat_weekly_limit():
    user = _user(usage_counters={"chat_messages_week": 5, "week_start": datetime.now(UTC).date().isoformat()})
    with pytest.raises(HTTPException) as exc:
        check_feature_access(user, "chat_messages")
    assert exc.value.status_code == 402
    assert exc.value.detail["feature"] == "chat_messages_week"


def test_train_unlimited_form_sessions():
    user = _user(subscription_tier=TIER_TRAIN, subscription_expires_at=datetime.now(UTC) + timedelta(days=30))
    check_feature_access(user, "form_sessions")
    consume_feature(user, "form_sessions")
    assert user.usage_counters["form_sessions"] == 1


def test_free_blocks_nutrition_plan_after_quota():
    user = _user(usage_counters={"nutrition_generations": 1})
    with pytest.raises(HTTPException) as exc:
        check_feature_access(user, "nutrition_generations")
    assert exc.value.detail["upgrade_tier"] == "fuel"


def test_elite_unlimited_nutrition_generations():
    user = _user(
        subscription_tier=TIER_ELITE,
        subscription_expires_at=datetime.now(UTC) + timedelta(days=30),
        usage_counters={"nutrition_generations": 50},
    )
    check_feature_access(user, "nutrition_generations")
    consume_feature(user, "nutrition_generations")
    assert user.usage_counters["nutrition_generations"] == 51


def test_coach_pro_weekly_nutrition_cap():
    user = _user(
        subscription_tier=TIER_COACH_PRO,
        subscription_expires_at=datetime.now(UTC) + timedelta(days=30),
        usage_counters={"nutrition_generations": 4},
    )
    with pytest.raises(HTTPException) as exc:
        check_feature_access(user, "nutrition_generations")
    assert exc.value.detail["upgrade_tier"] == "elite"


def test_activate_pro_product():
    user = _user()
    status = activate_product(user, "coachak_pro_monthly_egp")
    assert status["tier"] == TIER_COACH_PRO
    assert user.subscription_product_id == "coachak_pro_monthly_egp"
    assert user.subscription_expires_at is not None


def test_subscription_status_includes_limits_and_usage():
    user = _user()
    payload = subscription_status_payload(user)
    assert payload["tier"] == TIER_FREE
    assert "limits" in payload
    assert payload["limits"]["form_sessions"] == 3
    assert payload["usage"]["form_sessions"] == 0
