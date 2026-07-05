"""Macro math evaluation benchmarks."""

import pytest

from app.services.fitness_rules import calculate_macro_targets, calculate_tdee

REFERENCE_CASES = [
    {
        "weight_kg": 80,
        "height_cm": 180,
        "age": 30,
        "sex": "male",
        "activity_level": "moderate",
        "expected_tdee_range": (2400, 2800),
    },
    {
        "weight_kg": 65,
        "height_cm": 165,
        "age": 25,
        "sex": "female",
        "activity_level": "active",
        "expected_tdee_range": (2100, 2500),
    },
]


@pytest.mark.parametrize("case", REFERENCE_CASES)
def test_tdee_within_range(case):
    tdee = calculate_tdee(
        case["weight_kg"],
        case["height_cm"],
        case["age"],
        case["sex"],
        case["activity_level"],
    )
    low, high = case["expected_tdee_range"]
    assert low <= tdee <= high, f"TDEE {tdee} outside range [{low}, {high}]"


def test_fat_loss_reduces_calories():
    tdee = calculate_tdee(75, 175, 28, "male", "moderate")
    macros = calculate_macro_targets(tdee, "fat_loss", 75)
    assert macros["calories"] < tdee


def test_hypertrophy_protein_floor():
    macros = calculate_macro_targets(2500, "hypertrophy", 80)
    assert macros["protein_g"] >= 80 * 1.8


def test_macro_calories_consistent():
    macros = calculate_macro_targets(2500, "general_fitness", 70)
    computed = macros["protein_g"] * 4 + macros["carbs_g"] * 4 + macros["fat_g"] * 9
    assert abs(computed - macros["calories"]) < 50
