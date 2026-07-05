"""Plan safety evaluation benchmarks."""

import pytest

from app.services.fitness_rules import CONTRAINDICATED_EXERCISES, validate_workout_plan


SYNTHETIC_PROFILES = [
    {"injuries": ["lower_back"], "blocked_patterns": ["deadlift", "barbell_back_squat"]},
    {"injuries": ["knee"], "blocked_patterns": ["jump_squat", "box_jump"]},
    {"injuries": ["shoulder"], "blocked_patterns": ["overhead_press"]},
    {"injuries": [], "blocked_patterns": []},
]


def _make_plan_with_exercise(exercise_name: str) -> dict:
    return {
        "title": "Test Plan",
        "weeks": 4,
        "sessions": [{
            "day_label": "Monday",
            "week_number": 1,
            "focus": "Test",
            "exercises": [{
                "name": exercise_name,
                "muscle_groups": ["test"],
                "sets": [{"reps": 10, "rpe": 8.0}],
            }],
            "estimated_minutes": 45,
        }],
    }


@pytest.mark.parametrize("profile", SYNTHETIC_PROFILES)
def test_safety_validation_detects_contraindications(profile):
    for injury in profile["injuries"]:
        blocked_ids = CONTRAINDICATED_EXERCISES.get(injury, [])
        for ex_id in blocked_ids:
            from app.services.fitness_rules import EXERCISE_LIBRARY
            entry = next((e for e in EXERCISE_LIBRARY if e["id"] == ex_id), None)
            if entry:
                plan = _make_plan_with_exercise(entry["name"])
                passed, issues, _ = validate_workout_plan(plan, profile["injuries"])
                assert not passed, f"Should block {entry['name']} for {injury}"


def test_safe_plan_passes_validation():
    plan = _make_plan_with_exercise("Goblet Squat")
    passed, issues, _ = validate_workout_plan(plan, ["lower_back"])
    assert passed, f"Goblet squat should be safe: {issues}"


def test_high_rpe_flagged():
    plan = {
        "title": "Test",
        "weeks": 1,
        "sessions": [{
            "day_label": "Mon",
            "week_number": 1,
            "focus": "Test",
            "exercises": [{
                "name": "Push-Up",
                "sets": [{"reps": 5, "rpe": 10.0}],
            }],
            "estimated_minutes": 30,
        }],
    }
    passed, issues, _ = validate_workout_plan(plan, [])
    assert not passed
    assert any("RPE" in i for i in issues)
