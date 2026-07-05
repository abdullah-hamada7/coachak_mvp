"""Food analysis schema validation tests."""

import pytest

REQUIRED_ITEM_FIELDS = {"name", "portion_estimate", "confidence"}
REQUIRED_ANALYSIS_FIELDS = {"items"}


def validate_food_analysis(data: dict) -> list[str]:
    errors = []
    for field in REQUIRED_ANALYSIS_FIELDS:
        if field not in data:
            errors.append(f"Missing field: {field}")

    for i, item in enumerate(data.get("items", [])):
        for field in REQUIRED_ITEM_FIELDS:
            if field not in item:
                errors.append(f"Item {i} missing field: {field}")
        conf = item.get("confidence")
        if conf is not None and not (0 <= conf <= 1):
            errors.append(f"Item {i} confidence out of range: {conf}")

    return errors


SAMPLE_ANALYSES = [
    {
        "items": [
            {"name": "Grilled chicken", "portion_estimate": "150g", "confidence": 0.85},
            {"name": "Brown rice", "portion_estimate": "1 cup", "confidence": 0.75},
        ],
        "notes": "Balanced meal",
    },
    {
        "items": [
            {"name": "Salad", "portion_estimate": "1 bowl", "confidence": 0.6},
        ],
    },
]


INVALID_ANALYSES = [
    {"items": [{"name": "Chicken"}]},
    {"items": [{"name": "X", "portion_estimate": "1", "confidence": 1.5}]},
]


@pytest.mark.parametrize("analysis", SAMPLE_ANALYSES)
def test_valid_analyses_pass(analysis):
    errors = validate_food_analysis(analysis)
    assert errors == [], f"Unexpected errors: {errors}"


@pytest.mark.parametrize("analysis", INVALID_ANALYSES)
def test_invalid_analyses_fail(analysis):
    errors = validate_food_analysis(analysis)
    assert len(errors) > 0
