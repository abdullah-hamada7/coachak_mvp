"""Food log API validation tests."""

import pytest
from pydantic import ValidationError

from app.routes.logs import FoodItem, FoodLogCreate


def test_food_item_accepts_percentage_confidence():
    item = FoodItem(name="Chicken", confidence=85)
    assert item.confidence == 0.85


def test_food_item_defaults_empty_name():
    item = FoodItem(name="  ")
    assert item.name == "Meal"


def test_food_log_requires_items():
    with pytest.raises(ValidationError):
        FoodLogCreate(items=[])
