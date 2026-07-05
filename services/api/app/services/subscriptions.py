"""Subscription tiers, entitlements, and usage limits."""

from __future__ import annotations

from copy import deepcopy
from datetime import UTC, date, datetime, timedelta
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.db_models import User

settings = get_settings()

TIER_FREE = "free"
TIER_TRAIN = "train"
TIER_FUEL = "fuel"
TIER_TRAIN_FUEL = "train_fuel"
TIER_COACH_PRO = "coach_pro"
TIER_ELITE = "elite"

TIER_RANK = {
    TIER_FREE: 0,
    TIER_TRAIN: 1,
    TIER_FUEL: 1,
    TIER_TRAIN_FUEL: 2,
    TIER_COACH_PRO: 3,
    TIER_ELITE: 4,
}

USAGE_KEYS = (
    "form_sessions",
    "chat_messages",
    "chat_messages_week",
    "food_scans",
    "voice_cues",
    "workout_generations",
    "nutrition_generations",
)

# None = unlimited for the period
TIER_LIMITS: dict[str, dict[str, int | None]] = {
    TIER_FREE: {
        "form_sessions": 3,
        "chat_messages": None,
        "chat_messages_week": 5,
        "food_scans": 3,
        "voice_cues": 0,
        "workout_generations": 1,
        "nutrition_generations": 1,
        "reminders": 1,
        "progress_history_days": 7,
    },
    TIER_TRAIN: {
        "form_sessions": None,
        "chat_messages": 20,
        "chat_messages_week": None,
        "food_scans": 0,
        "voice_cues": 20,
        "workout_generations": None,
        "nutrition_generations": 0,
        "reminders": 5,
        "progress_history_days": 90,
    },
    TIER_FUEL: {
        "form_sessions": 0,
        "chat_messages": 10,
        "chat_messages_week": None,
        "food_scans": 30,
        "voice_cues": 0,
        "workout_generations": 0,
        "nutrition_generations": None,
        "reminders": 3,
        "progress_history_days": 30,
    },
    TIER_TRAIN_FUEL: {
        "form_sessions": None,
        "chat_messages": 20,
        "chat_messages_week": None,
        "food_scans": 30,
        "voice_cues": 20,
        "workout_generations": None,
        "nutrition_generations": None,
        "reminders": 5,
        "progress_history_days": 90,
    },
    TIER_COACH_PRO: {
        "form_sessions": None,
        "chat_messages": None,
        "chat_messages_week": None,
        "food_scans": 60,
        "voice_cues": None,
        "workout_generations": None,
        "nutrition_generations": 4,
        "reminders": None,
        "progress_history_days": None,
    },
    TIER_ELITE: {
        "form_sessions": None,
        "chat_messages": None,
        "chat_messages_week": None,
        "food_scans": None,
        "voice_cues": None,
        "workout_generations": None,
        "nutrition_generations": None,
        "reminders": None,
        "progress_history_days": None,
    },
}

TIER_FEATURES: dict[str, list[str]] = {
    TIER_FREE: [
        "Workout & food logging",
        "Gamification (XP, badges, streaks)",
        "1 AI workout plan",
        "1 AI nutrition plan",
        "3 form CV sessions / month",
        "5 coach messages / week",
        "3 food photo scans / month",
        "7-day progress history",
        "1 reminder",
    ],
    TIER_TRAIN: [
        "Weekly AI workout plan refresh",
        "Unlimited form CV",
        "Clinical ROM & stability scores",
        "20 Arabic voice cues / month",
        "20 coach messages / month",
        "90-day progress history",
        "5 reminders",
    ],
    TIER_FUEL: [
        "Weekly AI nutrition plan",
        "Personalized macro targets",
        "30 food photo scans / month",
        "Unlimited manual food logging",
        "10 nutrition coach messages / month",
        "30-day progress history",
        "3 reminders",
    ],
    TIER_TRAIN_FUEL: [
        "Everything in Train + Fuel",
        "Bundle discount vs separate plans",
    ],
    TIER_COACH_PRO: [
        "Unlimited AI coach chat",
        "Weekly workout & nutrition plans",
        "Unlimited form CV",
        "60 food photo scans / month",
        "Unlimited Arabic voice coaching",
        "Coach memory & context",
        "Full progress analytics",
        "Unlimited reminders",
    ],
    TIER_ELITE: [
        "Everything in Coach Pro",
        "Unlimited meal logging & food photo scans",
        "Unlimited nutrition plan regeneration",
        "Advanced form analytics & trends",
        "Arabic clinical session reports",
        "Custom 4–12 week periodization",
        "Data export (CSV/PDF)",
        "Proactive daily coach check-ins",
    ],
}

PLAN_CATALOG: list[dict[str, Any]] = [
    {
        "product_id": "coachak_train_monthly_egp",
        "tier": TIER_TRAIN,
        "name": "Train",
        "name_ar": "تدريب",
        "billing_period": "monthly",
        "price_egp": 399,
        "trial_days": 0,
        "popular": False,
    },
    {
        "product_id": "coachak_train_annual_egp",
        "tier": TIER_TRAIN,
        "name": "Train Annual",
        "name_ar": "تدريب — سنوي",
        "billing_period": "annual",
        "price_egp": 2999,
        "trial_days": 0,
        "popular": False,
    },
    {
        "product_id": "coachak_fuel_monthly_egp",
        "tier": TIER_FUEL,
        "name": "Fuel",
        "name_ar": "تغذية",
        "billing_period": "monthly",
        "price_egp": 299,
        "trial_days": 0,
        "popular": False,
    },
    {
        "product_id": "coachak_fuel_annual_egp",
        "tier": TIER_FUEL,
        "name": "Fuel Annual",
        "name_ar": "تغذية — سنوي",
        "billing_period": "annual",
        "price_egp": 2499,
        "trial_days": 0,
        "popular": False,
    },
    {
        "product_id": "coachak_bundle_train_fuel_monthly_egp",
        "tier": TIER_TRAIN_FUEL,
        "name": "Train + Fuel",
        "name_ar": "تدريب + تغذية",
        "billing_period": "monthly",
        "price_egp": 549,
        "trial_days": 0,
        "popular": False,
    },
    {
        "product_id": "coachak_pro_monthly_egp",
        "tier": TIER_COACH_PRO,
        "name": "Coach Pro",
        "name_ar": "كوتش برو",
        "billing_period": "monthly",
        "price_egp": 599,
        "trial_days": 7,
        "popular": True,
    },
    {
        "product_id": "coachak_pro_quarterly_egp",
        "tier": TIER_COACH_PRO,
        "name": "Coach Pro Quarterly",
        "name_ar": "كوتش برو — ٣ أشهر",
        "billing_period": "quarterly",
        "price_egp": 1599,
        "trial_days": 7,
        "popular": False,
    },
    {
        "product_id": "coachak_pro_annual_egp",
        "tier": TIER_COACH_PRO,
        "name": "Coach Pro Annual",
        "name_ar": "كوتش برو — سنوي",
        "billing_period": "annual",
        "price_egp": 4999,
        "trial_days": 7,
        "popular": False,
    },
    {
        "product_id": "coachak_elite_monthly_egp",
        "tier": TIER_ELITE,
        "name": "Elite",
        "name_ar": "نخبة",
        "billing_period": "monthly",
        "price_egp": 899,
        "trial_days": 0,
        "popular": False,
    },
    {
        "product_id": "coachak_elite_annual_egp",
        "tier": TIER_ELITE,
        "name": "Elite Annual",
        "name_ar": "نخبة — سنوي",
        "billing_period": "annual",
        "price_egp": 7999,
        "trial_days": 0,
        "popular": False,
    },
]

PRODUCT_BY_ID = {p["product_id"]: p for p in PLAN_CATALOG}

BILLING_MONTHS = {
    "monthly": 1,
    "quarterly": 3,
    "annual": 12,
}


def default_usage_counters() -> dict[str, Any]:
    return {
        "form_sessions": 0,
        "chat_messages": 0,
        "chat_messages_week": 0,
        "food_scans": 0,
        "voice_cues": 0,
        "workout_generations": 0,
        "nutrition_generations": 0,
        "week_start": date.today().isoformat(),
    }


def is_owner(user: User) -> bool:
    return user.email.lower() in settings.owner_email_set


def effective_tier(user: User) -> str:
    if is_owner(user):
        return TIER_ELITE
    tier = user.subscription_tier or TIER_FREE
    if tier == TIER_FREE:
        return TIER_FREE
    expires = user.subscription_expires_at
    if expires is not None:
        exp = expires if expires.tzinfo else expires.replace(tzinfo=UTC)
        if datetime.now(UTC) > exp:
            return TIER_FREE
    return tier


def tier_limits(tier: str) -> dict[str, int | None]:
    return deepcopy(TIER_LIMITS.get(tier, TIER_LIMITS[TIER_FREE]))


def _month_start(dt: datetime) -> datetime:
    return datetime(dt.year, dt.month, 1, tzinfo=UTC)


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


def ensure_usage_period(user: User) -> dict[str, Any]:
    counters = dict(user.usage_counters or default_usage_counters())
    now = datetime.now(UTC)
    period_start = user.usage_period_start
    if period_start is None:
        user.usage_period_start = _month_start(now)
    else:
        ps = period_start if period_start.tzinfo else period_start.replace(tzinfo=UTC)
        if ps < _month_start(now):
            for key in USAGE_KEYS:
                counters[key] = 0
            user.usage_period_start = _month_start(now)

    week_start_str = counters.get("week_start")
    current_week = _week_start(date.today()).isoformat()
    if week_start_str != current_week:
        counters["chat_messages_week"] = 0
        counters["week_start"] = current_week

    user.usage_counters = counters
    return counters


def _usage_value(counters: dict[str, Any], feature: str) -> int:
    return int(counters.get(feature, 0) or 0)


def check_feature_access(user: User, feature: str, amount: int = 1) -> None:
    if is_owner(user):
        return
    tier = effective_tier(user)
    limits = tier_limits(tier)
    limit = limits.get(feature)

    if limit == 0:
        raise _limit_error(user, feature, tier, 0, 0)

    counters = ensure_usage_period(user)
    used = _usage_value(counters, feature)

    if feature == "chat_messages" and limits.get("chat_messages_week") is not None:
        week_limit = limits["chat_messages_week"]
        week_used = _usage_value(counters, "chat_messages_week")
        if week_limit is not None and week_used + amount > week_limit:
            raise _limit_error(user, "chat_messages_week", tier, week_limit, week_used)
        return

    if limit is None:
        return

    if used + amount > limit:
        raise _limit_error(user, feature, tier, limit, used)


def consume_feature(user: User, feature: str, amount: int = 1) -> None:
    if is_owner(user):
        return
    counters = ensure_usage_period(user)
    counters[feature] = _usage_value(counters, feature) + amount
    if feature == "chat_messages":
        counters["chat_messages_week"] = _usage_value(counters, "chat_messages_week") + amount
    user.usage_counters = counters


def _upgrade_tier_for_feature(feature: str, tier: str | None = None) -> str:
    if feature == "nutrition_generations" and tier == TIER_COACH_PRO:
        return TIER_ELITE
    if feature == "food_scans" and tier == TIER_COACH_PRO:
        return TIER_ELITE
    mapping = {
        "form_sessions": TIER_TRAIN,
        "workout_generations": TIER_TRAIN,
        "voice_cues": TIER_TRAIN,
        "food_scans": TIER_FUEL,
        "nutrition_generations": TIER_FUEL,
        "chat_messages": TIER_COACH_PRO,
        "chat_messages_week": TIER_COACH_PRO,
    }
    return mapping.get(feature, TIER_COACH_PRO)


FEATURE_LABELS: dict[str, str] = {
    "form_sessions": "form analysis sessions",
    "chat_messages": "coach messages",
    "chat_messages_week": "coach messages this week",
    "food_scans": "food photo scans",
    "voice_cues": "voice coaching cues",
    "workout_generations": "workout plan generations",
    "nutrition_generations": "nutrition plan generations",
}

TIER_LABELS: dict[str, str] = {
    TIER_TRAIN: "Train",
    TIER_FUEL: "Fuel",
    TIER_TRAIN_FUEL: "Train + Fuel",
    TIER_COACH_PRO: "Coach Pro",
    TIER_ELITE: "Elite",
}


def _limit_message(feature: str, tier: str, limit: int, used: int) -> str:
    feature_label = FEATURE_LABELS.get(feature, feature.replace("_", " "))
    upgrade_tier = _upgrade_tier_for_feature(feature, tier)
    upgrade_label = TIER_LABELS.get(upgrade_tier, upgrade_tier.replace("_", " ").title())
    current_label = TIER_LABELS.get(tier, tier.replace("_", " ").title())

    if limit == 0:
        return (
            f"Your {current_label} plan does not include {feature_label}. "
            f"Upgrade to {upgrade_label} to unlock this feature."
        )
    return (
        f"You've used {used} of {limit} {feature_label} on your {current_label} plan. "
        f"Upgrade to {upgrade_label} to continue."
    )


def _limit_error(user: User, feature: str, tier: str, limit: int, used: int) -> HTTPException:
    upgrade_tier = _upgrade_tier_for_feature(feature, tier)
    message = _limit_message(feature, tier, limit, used)
    return HTTPException(
        status_code=status.HTTP_402_PAYMENT_REQUIRED,
        detail={
            "code": "subscription_limit",
            "feature": feature,
            "tier": tier,
            "limit": limit,
            "used": used,
            "upgrade_tier": upgrade_tier,
            "upgrade_plan": TIER_LABELS.get(upgrade_tier, upgrade_tier),
            "message": message,
            "title": "Upgrade your plan",
        },
    )


def subscription_status_payload(user: User) -> dict[str, Any]:
    tier = effective_tier(user)
    limits = tier_limits(tier)
    if is_owner(user):
        limits = {key: None for key in limits}
    counters = ensure_usage_period(user)
    usage = {key: _usage_value(counters, key) for key in USAGE_KEYS}

    return {
        "tier": tier,
        "stored_tier": TIER_ELITE if is_owner(user) else (user.subscription_tier or TIER_FREE),
        "product_id": user.subscription_product_id if not is_owner(user) else "owner_unlimited",
        "expires_at": user.subscription_expires_at.isoformat() if user.subscription_expires_at else None,
        "is_active": True if is_owner(user) else tier != TIER_FREE,
        "is_owner": is_owner(user),
        "limits": limits,
        "usage": usage,
        "features": TIER_FEATURES.get(tier, TIER_FEATURES[TIER_FREE]),
        "usage_period_start": user.usage_period_start.isoformat() if user.usage_period_start else None,
    }


def activate_product(user: User, product_id: str) -> dict[str, Any]:
    product = PRODUCT_BY_ID.get(product_id)
    if product is None:
        raise HTTPException(status_code=400, detail=f"Unknown product_id: {product_id}")

    months = BILLING_MONTHS[product["billing_period"]]
    now = datetime.now(UTC)
    base = user.subscription_expires_at
    if base is not None:
        base = base if base.tzinfo else base.replace(tzinfo=UTC)
        start = base if base > now else now
    else:
        start = now

    trial_days = int(product.get("trial_days") or 0)
    if trial_days and (user.subscription_expires_at is None or effective_tier(user) == TIER_FREE):
        expires = now + timedelta(days=trial_days)
    else:
        expires = start + timedelta(days=months * 30)

    # Upgrades keep higher tier rank
    new_tier = product["tier"]
    current = effective_tier(user)
    if TIER_RANK.get(new_tier, 0) < TIER_RANK.get(current, 0) and current != TIER_FREE:
        new_tier = current

    user.subscription_tier = new_tier
    user.subscription_product_id = product_id
    user.subscription_expires_at = expires
    user.usage_period_start = _month_start(now)
    user.usage_counters = default_usage_counters()

    return subscription_status_payload(user)
