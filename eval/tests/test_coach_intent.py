"""Tests for coach chat intent classification."""

import pytest

from app.agents.coach_intent import (
    INTENT_BOTH,
    INTENT_CHAT,
    INTENT_NUTRITION,
    INTENT_WORKOUT,
    classify_message_intent,
)


@pytest.mark.parametrize(
    ("message", "expected"),
    [
        ("What should I eat post-workout?", INTENT_CHAT),
        ("what should i eat after workout", INTENT_CHAT),
        ("How many calories should I eat to lose fat?", INTENT_CHAT),
        ("I only have dumbbells now", INTENT_CHAT),
        ("How am I progressing?", INTENT_CHAT),
        ("My knee hurts during squats", INTENT_CHAT),
        ("Can I swap bench press for dumbbells?", INTENT_CHAT),
        ("How many sets should I do for bench press?", INTENT_CHAT),
        ("Create a workout plan for me", INTENT_WORKOUT),
        ("Generate a training program for hypertrophy", INTENT_WORKOUT),
        ("Create a nutrition plan for me", INTENT_NUTRITION),
        ("generate meal plan", INTENT_NUTRITION),
        ("Create workout and meal plan", INTENT_BOTH),
        ("Regenerate my workout and nutrition plan", INTENT_BOTH),
        ("Please constrain my schedule", INTENT_CHAT),
    ],
)
def test_classify_message_intent(message: str, expected: str):
    assert classify_message_intent(message) == expected
