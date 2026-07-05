"""Fitness science guardrails for plan validation."""

from __future__ import annotations

CONTRAINDICATED_EXERCISES: dict[str, list[str]] = {
    "lower_back": ["barbell_back_squat", "deadlift", "good_morning", "overhead_squat"],
    "knee": ["jump_squat", "box_jump", "deep_lunge"],
    "shoulder": ["overhead_press", "upright_row", "behind_neck_press"],
    "wrist": ["front_squat", "clean_and_press"],
}

EXERCISE_LIBRARY: list[dict] = [
    {"id": "goblet_squat", "name": "Goblet Squat", "muscles": ["quads", "glutes"], "equipment": ["dumbbell", "kettlebell"], "pattern": "squat"},
    {"id": "barbell_back_squat", "name": "Barbell Back Squat", "muscles": ["quads", "glutes"], "equipment": ["barbell", "rack"], "pattern": "squat"},
    {"id": "bodyweight_squat", "name": "Bodyweight Squat", "muscles": ["quads", "glutes"], "equipment": ["bodyweight"], "pattern": "squat"},
    {"id": "push_up", "name": "Push-Up", "muscles": ["chest", "triceps"], "equipment": ["bodyweight"], "pattern": "push"},
    {"id": "dumbbell_bench_press", "name": "Dumbbell Bench Press", "muscles": ["chest", "triceps"], "equipment": ["dumbbell", "bench"], "pattern": "push"},
    {"id": "dumbbell_row", "name": "Dumbbell Row", "muscles": ["back", "biceps"], "equipment": ["dumbbell"], "pattern": "pull"},
    {"id": "lat_pulldown", "name": "Lat Pulldown", "muscles": ["back", "biceps"], "equipment": ["cable"], "pattern": "pull"},
    {"id": "romanian_deadlift", "name": "Romanian Deadlift", "muscles": ["hamstrings", "glutes"], "equipment": ["barbell", "dumbbell"], "pattern": "hinge"},
    {"id": "deadlift", "name": "Conventional Deadlift", "muscles": ["back", "hamstrings", "glutes"], "equipment": ["barbell"], "pattern": "hinge"},
    {"id": "dumbbell_curl", "name": "Dumbbell Bicep Curl", "muscles": ["biceps"], "equipment": ["dumbbell"], "pattern": "isolation"},
    {"id": "plank", "name": "Plank", "muscles": ["core"], "equipment": ["bodyweight"], "pattern": "core"},
    {"id": "walking_lunge", "name": "Walking Lunge", "muscles": ["quads", "glutes"], "equipment": ["bodyweight", "dumbbell"], "pattern": "lunge"},
    {"id": "overhead_press", "name": "Overhead Press", "muscles": ["shoulders", "triceps"], "equipment": ["barbell", "dumbbell"], "pattern": "push"},
    {"id": "hip_thrust", "name": "Hip Thrust", "muscles": ["glutes", "hamstrings"], "equipment": ["barbell", "bench"], "pattern": "hinge"},
    {"id": "leg_press", "name": "Leg Press", "muscles": ["quads", "glutes"], "equipment": ["machine"], "pattern": "squat"},
]


def calculate_tdee(
    weight_kg: float,
    height_cm: float,
    age: int,
    sex: str,
    activity_level: str,
) -> int:
    """Mifflin-St Jeor BMR with activity multiplier."""
    if sex == "male":
        bmr = 10 * weight_kg + 6.25 * height_cm - 5 * age + 5
    else:
        bmr = 10 * weight_kg + 6.25 * height_cm - 5 * age - 161

    multipliers = {
        "sedentary": 1.2,
        "light": 1.375,
        "moderate": 1.55,
        "active": 1.725,
        "very_active": 1.9,
    }
    return int(bmr * multipliers.get(activity_level, 1.55))


def calculate_macro_targets(tdee: int, goal: str, weight_kg: float) -> dict:
    """Goal-adjusted macro targets."""
    adjustments = {
        "fat_loss": -500,
        "hypertrophy": 250,
        "strength": 200,
        "mobility": 0,
        "general_fitness": 0,
    }
    calories = max(1200, tdee + adjustments.get(goal, 0))
    protein_g = round(weight_kg * (2.2 if goal in ("hypertrophy", "strength") else 1.8), 1)
    fat_g = round(calories * 0.25 / 9, 1)
    carbs_g = round((calories - protein_g * 4 - fat_g * 9) / 4, 1)
    return {
        "calories": calories,
        "protein_g": protein_g,
        "carbs_g": max(50, carbs_g),
        "fat_g": fat_g,
        "fiber_g": 30,
    }


def validate_workout_plan(plan: dict, injuries: list[str]) -> tuple[bool, list[str], list[str]]:
    """Validate workout plan against safety rules."""
    issues: list[str] = []
    suggestions: list[str] = []

    blocked: set[str] = set()
    for injury in injuries:
        for ex_id in CONTRAINDICATED_EXERCISES.get(injury.lower().replace(" ", "_"), []):
            blocked.add(ex_id)

    for session in plan.get("sessions", []):
        for exercise in session.get("exercises", []):
            name_lower = exercise.get("name", "").lower().replace(" ", "_")
            for blocked_id in blocked:
                lib_entry = next((e for e in EXERCISE_LIBRARY if e["id"] == blocked_id), None)
                if lib_entry and lib_entry["name"].lower().replace(" ", "_") in name_lower:
                    issues.append(f"Exercise '{exercise['name']}' contraindicated for injuries: {injuries}")
                    suggestions.append(f"Replace '{exercise['name']}' with a safer alternative like goblet squat or leg press")

            for s in exercise.get("sets", []):
                if s.get("rpe") and s["rpe"] > 9.5:
                    issues.append(f"RPE {s['rpe']} too high for safe programming in '{exercise['name']}'")
                    suggestions.append("Cap working sets at RPE 8-9 for most trainees")

    return len(issues) == 0, issues, suggestions


def filter_exercises(equipment: list[str], experience: str) -> list[dict]:
    """Filter exercise library by available equipment."""
    if not equipment:
        equipment = ["bodyweight"]
    available = set(e.lower() for e in equipment)
    available.add("bodyweight")

    filtered = [e for e in EXERCISE_LIBRARY if any(eq in available for eq in e["equipment"])]
    if experience == "beginner":
        filtered = [e for e in filtered if e["pattern"] in ("squat", "push", "pull", "core", "hinge")]
    return filtered
