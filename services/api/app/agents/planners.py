"""Workout and nutrition plan generation agents."""

from __future__ import annotations

from urllib.parse import quote_plus
from typing import Any

from app.models.db_models import User
from app.services.fitness_rules import (
    EXERCISE_LIBRARY,
    calculate_macro_targets,
    calculate_tdee,
    filter_exercises,
    validate_workout_plan,
)
from app.services.groq import generate_structured


async def generate_workout_plan(user: User, rag_context: str = "") -> dict[str, Any]:
    equipment = user.equipment or ["bodyweight"]
    experience = user.experience_level or "beginner"
    days = user.workout_days_per_week or 3
    goal = user.primary_goal or "general_fitness"
    injuries = user.injuries or []

    available = filter_exercises(equipment, experience)
    exercise_names = [e["name"] for e in available[:12]]

    schema_hint = (
        '{"title": str, "weeks": 4, "sessions": [{"day_label": str, "week_number": int, '
        '"focus": str, "exercises": [{"name": str, "muscle_groups": [str], '
        '"sets": [{"reps": int, "rpe": float}], "notes": str}], "estimated_minutes": int}], '
        '"progression_notes": str}'
    )

    prompt = (
        f"Create a 4-week {goal.replace('_', ' ')} program for a {experience} trainee.\n"
        f"Training days per week: {days}\n"
        f"Available equipment: {', '.join(equipment)}\n"
        f"Injuries/limitations: {', '.join(injuries) or 'none'}\n"
        f"Use ONLY these exercises: {', '.join(exercise_names)}\n"
        f"Context: {rag_context[:2000]}"
    )

    try:
        plan = await generate_structured(
            prompt,
            schema_hint,
            system="You are an expert strength coach. Apply progressive overload and safe programming.",
        )
    except Exception:
        plan = {}

    if not plan or not plan.get("sessions") or not isinstance(plan.get("sessions"), list):
        plan = _fallback_workout_plan(days, goal, available)

    passed, issues, suggestions = validate_workout_plan(plan, injuries)
    if not passed:
        plan = _apply_safety_fixes(plan, issues, available)
        passed, _, _ = validate_workout_plan(plan, injuries)

    plan = _enrich_workout_plan(plan, available)
    plan["safety_validated"] = passed
    if not passed:
        plan["safety_issues"] = issues
        plan["safety_suggestions"] = suggestions

    return plan


async def generate_nutrition_plan(user: User, rag_context: str = "") -> dict[str, Any]:
    weight = user.weight_kg or 70
    height = user.height_cm or 170
    age = user.age or 30
    sex = user.sex or "male"
    activity = user.activity_level or "moderate"
    goal = user.primary_goal or "general_fitness"
    diet = user.dietary_preference or "omnivore"

    tdee = calculate_tdee(weight, height, age, sex, activity)
    macros = calculate_macro_targets(tdee, goal, weight)

    schema_hint = (
        '{"title": str, "tdee": int, "target_macros": {"calories": int, "protein_g": float, '
        '"carbs_g": float, "fat_g": float, "fiber_g": float}, '
        '"daily_plans": [{"day_label": str, "meals": [{"meal_type": str, "items": '
        '[{"name": str, "portion": str, "calories": int, "protein_g": float, '
        '"carbs_g": float, "fat_g": float}], "total_calories": int}]}], '
        '"hydration_liters": float, "notes": str}'
    )

    prompt = (
        f"Create a 7-day meal plan for {goal.replace('_', ' ')}.\n"
        f"Diet: {diet}\n"
        f"Daily targets: {macros['calories']} cal, {macros['protein_g']}g protein, "
        f"{macros['carbs_g']}g carbs, {macros['fat_g']}g fat\n"
        f"Context: {rag_context[:2000]}"
    )

    try:
        plan = await generate_structured(
            prompt,
            schema_hint,
            system="You are a sports nutritionist. Create practical, balanced meal plans.",
        )
    except Exception:
        plan = {}

    if (
        not plan
        or not plan.get("daily_plans")
        or not isinstance(plan.get("daily_plans"), list)
        or len(plan.get("daily_plans", [])) < 7
    ):
        plan = _fallback_nutrition_plan(tdee, macros, diet)

    plan["tdee"] = tdee
    plan["target_macros"] = macros
    plan["food_suggestions"] = _macro_food_suggestions(macros, diet)
    return plan


def _enrich_workout_plan(plan: dict, available: list[dict]) -> dict:
    library = {e["name"].lower(): e for e in EXERCISE_LIBRARY}
    available_by_name = {e["name"].lower(): e for e in available}

    for session in plan.get("sessions", []):
        for exercise in session.get("exercises", []):
            name = exercise.get("name", "Exercise")
            meta = library.get(name.lower()) or available_by_name.get(name.lower()) or {}
            muscles = exercise.get("muscle_groups") or meta.get("muscles", [])
            pattern = meta.get("pattern", "strength")
            exercise["muscle_groups"] = muscles
            exercise["description"] = exercise.get("description") or _exercise_description(name, muscles, pattern)
            exercise["mechanism"] = exercise.get("mechanism") or _exercise_mechanism(pattern)
            exercise["video_url"] = exercise.get("video_url") or _exercise_video_url(name)

            sets = exercise.get("sets") if isinstance(exercise.get("sets"), list) else []
            if not sets:
                sets = [{"reps": 10, "rpe": 7.0}, {"reps": 10, "rpe": 7.5}, {"reps": 10, "rpe": 8.0}]
            exercise["sets"] = sets
            exercise["sets_summary"] = _sets_summary(sets)
    return plan


def _exercise_description(name: str, muscles: list[str], pattern: str) -> str:
    target = ", ".join(muscles) if muscles else "the target muscles"
    return f"{name} is a {pattern.replace('_', ' ')} movement that trains {target} while reinforcing control and posture."


def _exercise_mechanism(pattern: str) -> str:
    cues = {
        "squat": "Brace your core, keep feet planted, sit between the hips, and drive through the mid-foot to stand tall.",
        "push": "Set the shoulder blades, lower with control, press without shrugging, and keep wrists stacked.",
        "pull": "Start by setting the shoulder blade, pull the elbow toward the ribs, and avoid twisting the torso.",
        "hinge": "Push hips back, keep the spine neutral, load the hamstrings, and stand by driving hips forward.",
        "core": "Brace as if taking a punch, keep ribs and pelvis stacked, and breathe without losing tension.",
        "lunge": "Step with control, keep the front knee tracking over toes, and push through the front foot.",
        "isolation": "Keep the upper arm stable, move through the target joint, and control the lowering phase.",
    }
    return cues.get(pattern, "Move through a controlled range, keep joints stacked, and stop if form breaks down.")


def _exercise_video_url(name: str) -> str:
    return f"https://www.youtube.com/results?search_query={quote_plus(name + ' proper exercise form tutorial')}"


def _sets_summary(sets: list[dict]) -> str:
    parts = []
    for index, item in enumerate(sets, start=1):
        reps = item.get("reps", "?")
        rpe = item.get("rpe")
        parts.append(f"Set {index}: {reps} reps" + (f" @ RPE {rpe}" if rpe is not None else ""))
    return " | ".join(parts)


def _fallback_workout_plan(days: int, goal: str, available: list[dict]) -> dict:
    sessions = []
    day_labels = ["Monday", "Wednesday", "Friday", "Saturday", "Sunday", "Tuesday", "Thursday"]
    focuses = ["Full Body A", "Upper Body", "Lower Body", "Push", "Pull", "Legs", "Full Body B"]

    for week in range(1, 5):
        for i in range(days):
            ex_slice = available[i * 2 : i * 2 + 4] or available[:4]
            sessions.append({
                "day_label": day_labels[i % 7],
                "week_number": week,
                "focus": focuses[i % len(focuses)],
                "estimated_minutes": 45,
                "exercises": [
                    {
                        "name": e["name"],
                        "muscle_groups": e["muscles"],
                        "sets": [{"reps": 10, "rpe": 7.0}, {"reps": 10, "rpe": 7.5}, {"reps": 10, "rpe": 8.0}],
                        "notes": f"Week {week}: focus on controlled tempo",
                        "description": _exercise_description(e["name"], e["muscles"], e["pattern"]),
                        "mechanism": _exercise_mechanism(e["pattern"]),
                        "video_url": _exercise_video_url(e["name"]),
                    }
                    for e in ex_slice
                ],
            })

    return {
        "title": f"4-Week {goal.replace('_', ' ').title()} Program",
        "weeks": 4,
        "sessions": sessions,
        "progression_notes": "Add 2.5-5kg or 1-2 reps per week where possible.",
    }


def _fallback_nutrition_plan(tdee: int, macros: dict, diet: str) -> dict:
    meals_by_day = _meal_templates_by_day(diet)

    daily_plans = []
    for day, meals_template in zip(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], meals_by_day, strict=False):
        meals = []
        for m in meals_template:
            total = sum(i["calories"] for i in m["items"])
            meals.append({
                **m,
                "total_calories": total,
                "total_protein_g": round(sum(i.get("protein_g", 0) for i in m["items"]), 1),
                "total_carbs_g": round(sum(i.get("carbs_g", 0) for i in m["items"]), 1),
                "total_fat_g": round(sum(i.get("fat_g", 0) for i in m["items"]), 1),
            })
        daily_plans.append({"day_label": day, "meals": meals})

    return {
        "title": "Balanced Performance Meal Plan",
        "tdee": tdee,
        "target_macros": macros,
        "daily_plans": daily_plans,
        "food_suggestions": _macro_food_suggestions(macros, diet),
        "hydration_liters": 2.5,
        "notes": f"Plan tailored for {diet} diet with {macros['protein_g']}g daily protein target.",
    }


def _meal_templates_by_day(diet: str) -> list[list[dict]]:
    protein_a = "Greek yogurt" if diet != "vegan" else "Soy yogurt"
    protein_b = "Grilled chicken breast" if diet not in ("vegetarian", "vegan") else "Tempeh"
    protein_c = "Salmon fillet" if diet not in ("vegetarian", "vegan") else "Tofu stir-fry"
    return [
        [
            {"meal_type": "breakfast", "items": [
                {"name": "Oatmeal with berries", "portion": "1 bowl", "calories": 350, "protein_g": 12, "carbs_g": 55, "fat_g": 8},
                {"name": protein_a, "portion": "150g", "calories": 130, "protein_g": 15, "carbs_g": 8, "fat_g": 4},
            ]},
            {"meal_type": "lunch", "items": [
                {"name": protein_b, "portion": "150g", "calories": 250, "protein_g": 45, "carbs_g": 0, "fat_g": 5},
                {"name": "Brown rice", "portion": "1 cup", "calories": 220, "protein_g": 5, "carbs_g": 45, "fat_g": 2},
                {"name": "Mixed vegetables", "portion": "1 cup", "calories": 80, "protein_g": 3, "carbs_g": 12, "fat_g": 1},
            ]},
            {"meal_type": "dinner", "items": [
                {"name": protein_c, "portion": "150g", "calories": 300, "protein_g": 35, "carbs_g": 5, "fat_g": 15},
                {"name": "Sweet potato", "portion": "200g", "calories": 180, "protein_g": 3, "carbs_g": 40, "fat_g": 0},
            ]},
            {"meal_type": "snack", "items": [
                {"name": "Protein shake", "portion": "1 scoop", "calories": 120, "protein_g": 25, "carbs_g": 3, "fat_g": 1},
            ]},
        ],
        [
            {"meal_type": "breakfast", "items": [
                {"name": "Egg scramble" if diet not in ("vegan",) else "Tofu scramble", "portion": "3 eggs / 200g tofu", "calories": 300, "protein_g": 24, "carbs_g": 8, "fat_g": 18},
                {"name": "Whole grain toast", "portion": "2 slices", "calories": 180, "protein_g": 8, "carbs_g": 32, "fat_g": 3},
            ]},
            {"meal_type": "lunch", "items": [
                {"name": "Turkey wrap" if diet not in ("vegetarian", "vegan") else "Chickpea wrap", "portion": "1 large wrap", "calories": 480, "protein_g": 38, "carbs_g": 55, "fat_g": 12},
                {"name": "Apple", "portion": "1 medium", "calories": 95, "protein_g": 0, "carbs_g": 25, "fat_g": 0},
            ]},
            {"meal_type": "dinner", "items": [
                {"name": "Lean beef bowl" if diet not in ("vegetarian", "vegan") else "Lentil bowl", "portion": "1 bowl", "calories": 560, "protein_g": 42, "carbs_g": 60, "fat_g": 16},
            ]},
            {"meal_type": "snack", "items": [
                {"name": "Cottage cheese" if diet != "vegan" else "Edamame", "portion": "200g", "calories": 180, "protein_g": 25, "carbs_g": 10, "fat_g": 5},
            ]},
        ],
        [
            {"meal_type": "breakfast", "items": [
                {"name": "Protein smoothie", "portion": "1 large", "calories": 420, "protein_g": 35, "carbs_g": 50, "fat_g": 8},
            ]},
            {"meal_type": "lunch", "items": [
                {"name": "Tuna quinoa salad" if diet not in ("vegetarian", "vegan") else "Quinoa bean salad", "portion": "1 bowl", "calories": 520, "protein_g": 38, "carbs_g": 58, "fat_g": 14},
            ]},
            {"meal_type": "dinner", "items": [
                {"name": "Chicken pasta" if diet not in ("vegetarian", "vegan") else "Chickpea pasta", "portion": "1 plate", "calories": 620, "protein_g": 45, "carbs_g": 75, "fat_g": 12},
            ]},
            {"meal_type": "snack", "items": [
                {"name": "Banana with peanut butter", "portion": "1 banana + 1 tbsp", "calories": 200, "protein_g": 5, "carbs_g": 30, "fat_g": 8},
            ]},
        ],
        [
            {"meal_type": "breakfast", "items": [
                {"name": "Overnight oats", "portion": "1 jar", "calories": 430, "protein_g": 25, "carbs_g": 60, "fat_g": 10},
            ]},
            {"meal_type": "lunch", "items": [
                {"name": "Chicken potato plate" if diet not in ("vegetarian", "vegan") else "Seitan potato plate", "portion": "1 plate", "calories": 560, "protein_g": 42, "carbs_g": 65, "fat_g": 10},
            ]},
            {"meal_type": "dinner", "items": [
                {"name": "Shrimp rice bowl" if diet not in ("vegetarian", "vegan") else "Tofu rice bowl", "portion": "1 bowl", "calories": 540, "protein_g": 40, "carbs_g": 62, "fat_g": 12},
            ]},
            {"meal_type": "snack", "items": [
                {"name": "Trail mix", "portion": "40g", "calories": 210, "protein_g": 6, "carbs_g": 18, "fat_g": 14},
            ]},
        ],
        [
            {"meal_type": "breakfast", "items": [
                {"name": "High-protein pancakes", "portion": "3 pancakes", "calories": 450, "protein_g": 32, "carbs_g": 55, "fat_g": 10},
            ]},
            {"meal_type": "lunch", "items": [
                {"name": "Chicken burrito bowl" if diet not in ("vegetarian", "vegan") else "Black bean burrito bowl", "portion": "1 bowl", "calories": 650, "protein_g": 45, "carbs_g": 78, "fat_g": 16},
            ]},
            {"meal_type": "dinner", "items": [
                {"name": "Cod with couscous" if diet not in ("vegetarian", "vegan") else "Halloumi couscous" if diet == "vegetarian" else "Tofu couscous", "portion": "1 plate", "calories": 520, "protein_g": 38, "carbs_g": 60, "fat_g": 12},
            ]},
            {"meal_type": "snack", "items": [
                {"name": "Greek yogurt parfait" if diet != "vegan" else "Soy yogurt parfait", "portion": "1 cup", "calories": 260, "protein_g": 22, "carbs_g": 32, "fat_g": 5},
            ]},
        ],
        [
            {"meal_type": "breakfast", "items": [
                {"name": "Avocado egg toast" if diet != "vegan" else "Avocado tofu toast", "portion": "2 slices", "calories": 460, "protein_g": 25, "carbs_g": 42, "fat_g": 22},
            ]},
            {"meal_type": "lunch", "items": [
                {"name": "Chicken pesto pasta" if diet not in ("vegetarian", "vegan") else "Pea pesto pasta", "portion": "1 plate", "calories": 650, "protein_g": 42, "carbs_g": 75, "fat_g": 18},
            ]},
            {"meal_type": "dinner", "items": [
                {"name": "Steak fajitas" if diet not in ("vegetarian", "vegan") else "Mushroom fajitas", "portion": "3 tortillas", "calories": 580, "protein_g": 40, "carbs_g": 62, "fat_g": 18},
            ]},
            {"meal_type": "snack", "items": [
                {"name": "Hummus and pita", "portion": "1 pita + 80g hummus", "calories": 310, "protein_g": 12, "carbs_g": 42, "fat_g": 10},
            ]},
        ],
        [
            {"meal_type": "breakfast", "items": [
                {"name": "Breakfast rice bowl", "portion": "1 bowl", "calories": 500, "protein_g": 30, "carbs_g": 65, "fat_g": 14},
            ]},
            {"meal_type": "lunch", "items": [
                {"name": "Salmon sushi bowl" if diet not in ("vegetarian", "vegan") else "Edamame sushi bowl", "portion": "1 bowl", "calories": 560, "protein_g": 35, "carbs_g": 70, "fat_g": 14},
            ]},
            {"meal_type": "dinner", "items": [
                {"name": "Roast chicken plate" if diet not in ("vegetarian", "vegan") else "Roast chickpea plate", "portion": "1 plate", "calories": 600, "protein_g": 44, "carbs_g": 62, "fat_g": 18},
            ]},
            {"meal_type": "snack", "items": [
                {"name": "Protein bar", "portion": "1 bar", "calories": 220, "protein_g": 20, "carbs_g": 24, "fat_g": 6},
            ]},
        ],
    ]


def _macro_food_suggestions(macros: dict, diet: str) -> dict:
    protein = ["chicken breast", "Greek yogurt", "eggs", "tuna", "salmon"]
    if diet in ("vegetarian", "vegan"):
        protein = ["tofu", "tempeh", "lentils", "chickpeas", "soy yogurt", "edamame"]
    carbs = ["rice", "oats", "potatoes", "whole grain bread", "fruit", "pasta"]
    fats = ["olive oil", "avocado", "nuts", "peanut butter", "seeds"]
    fiber = ["berries", "beans", "leafy greens", "broccoli", "mixed vegetables"]
    return {
        "protein": {"target_g": macros.get("protein_g"), "foods": protein},
        "carbs": {"target_g": macros.get("carbs_g"), "foods": carbs},
        "fats": {"target_g": macros.get("fat_g"), "foods": fats},
        "fiber": {"target_g": macros.get("fiber_g"), "foods": fiber},
    }


def _apply_safety_fixes(plan: dict, issues: list[str], available: list[dict]) -> dict:
    safe_names = {e["name"] for e in available if e["id"] not in ("barbell_back_squat", "deadlift", "overhead_press")}
    replacements = list(safe_names)[:3] or ["Bodyweight Squat", "Push-Up", "Plank"]

    for session in plan.get("sessions", []):
        for i, exercise in enumerate(session.get("exercises", [])):
            for issue in issues:
                if exercise.get("name", "") in issue:
                    exercise["name"] = replacements[i % len(replacements)]
                    exercise["notes"] = "Modified for safety based on injury profile"
    return plan
