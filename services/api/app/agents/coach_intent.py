"""Coach message intent classification — keeps plan generation separate from advice."""

from __future__ import annotations

import re

INTENT_CHAT = "chat"
INTENT_WORKOUT = "workout"
INTENT_NUTRITION = "nutrition"
INTENT_BOTH = "both"

# Conversational advice — never auto-generate multi-week plans.
ADVICE_PATTERNS = (
    "what should i eat",
    "what to eat",
    "what can i eat",
    "what do i eat",
    "how many calories",
    "how much protein",
    "how much should i eat",
    "post-workout",
    "post workout",
    "pre-workout",
    "pre workout",
    "after workout",
    "before workout",
    "postworkout",
    "how am i progressing",
    "how am i doing",
    "my progress",
    "form check",
    "check my form",
    "hurt my",
    "pain in",
    "injury",
    "injured",
    "sore",
    "recovery",
    "rest day",
    "plateau",
    "stuck on",
    "can't lift",
    "cannot lift",
    "substitute",
    "swap ",
    "replace ",
    "instead of",
    "only have",
    "don't have",
    "do not have",
    "no gym",
    "at home",
    "how many sets",
    "how many reps",
    "should i do",
    "is it okay",
    "is it ok",
    "can i eat",
    "good to eat",
)

PLAN_REQUEST_PATTERNS = (
    "generate plan",
    "create plan",
    "new plan",
    "make me a plan",
    "build me a plan",
    "give me a plan",
    "workout plan",
    "training plan",
    "exercise plan",
    "nutrition plan",
    "meal plan",
    "food plan",
    "training program",
    "exercise program",
    "generate workout",
    "create workout",
    "generate nutrition",
    "create nutrition",
    "generate meal",
    "create meal",
    "update plan",
    "adjust plan",
    "change my plan",
    "modify plan",
    "refresh plan",
    "regenerate plan",
    "redo my plan",
    "rebuild my plan",
)

NUTRITION_WORDS = ("nutrition", "meal", "meals", "diet", "macro", "macros", "calorie", "calories", "food")
WORKOUT_WORDS = ("workout", "training", "exercise", "lift", "lifting", "hypertrophy", "strength", "session")


def _normalize(message: str) -> str:
    return re.sub(r"\s+", " ", message.lower().strip())


def _contains_phrase(message: str, phrase: str) -> bool:
    return phrase in message


def _contains_word(message: str, word: str) -> bool:
    return re.search(rf"\b{re.escape(word)}\b", message) is not None


def _has_any_phrase(message: str, phrases: tuple[str, ...]) -> bool:
    return any(_contains_phrase(message, phrase) for phrase in phrases)


def _has_any_word(message: str, words: tuple[str, ...]) -> bool:
    return any(_contains_word(message, word) for word in words)


def classify_message_intent(message: str) -> str:
    """Return chat | workout | nutrition | both."""
    msg = _normalize(message)

    if _has_any_phrase(msg, ADVICE_PATTERNS):
        return INTENT_CHAT

    wants_plan = _has_any_phrase(msg, PLAN_REQUEST_PATTERNS)
    has_nutrition = _has_any_word(msg, NUTRITION_WORDS) or _contains_phrase(msg, "food plan")
    has_workout = _has_any_word(msg, WORKOUT_WORDS) or _contains_phrase(msg, "workout plan")

    if wants_plan:
        if has_nutrition and has_workout:
            return INTENT_BOTH
        if has_nutrition:
            return INTENT_NUTRITION
        if has_workout:
            return INTENT_WORKOUT
        if _contains_word(msg, "plan") or _contains_word(msg, "program"):
            return INTENT_BOTH
        return INTENT_CHAT

    return INTENT_CHAT
