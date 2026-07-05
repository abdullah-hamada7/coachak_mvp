"""USDA FoodData Central integration for macro grounding."""

from __future__ import annotations

import httpx

from app.core.config import get_settings

settings = get_settings()
USDA_BASE = "https://api.nal.usda.gov/fdc/v1"


async def search_food(query: str, page_size: int = 5) -> list[dict]:
    if not settings.usda_api_key:
        return _fallback_foods(query)

    params = {"api_key": settings.usda_api_key, "query": query, "pageSize": page_size}
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(f"{USDA_BASE}/foods/search", params=params)
        resp.raise_for_status()
        foods = resp.json().get("foods", [])
        return [
            {
                "fdc_id": f["fdcId"],
                "description": f.get("description", query),
                "calories": _extract_nutrient(f, "Energy"),
                "protein_g": _extract_nutrient(f, "Protein"),
                "carbs_g": _extract_nutrient(f, "Carbohydrate, by difference"),
                "fat_g": _extract_nutrient(f, "Total lipid (fat)"),
            }
            for f in foods
        ]


async def ground_food_items(items: list[dict]) -> list[dict]:
    """Map vision-detected items to USDA macros."""
    grounded = []
    for item in items:
        name = item.get("name", "food")
        results = await search_food(name, page_size=1)
        if results:
            best = results[0]
            grounded.append({
                **item,
                "usda_fdc_id": best["fdc_id"],
                "calories": best.get("calories") or _estimate_calories(name),
                "protein_g": best.get("protein_g") or 0,
                "carbs_g": best.get("carbs_g") or 0,
                "fat_g": best.get("fat_g") or 0,
            })
        else:
            grounded.append({
                **item,
                "calories": _estimate_calories(name),
                "protein_g": 10,
                "carbs_g": 20,
                "fat_g": 5,
            })
    return grounded


def _extract_nutrient(food: dict, name: str) -> float | None:
    for nutrient in food.get("foodNutrients", []):
        if nutrient.get("nutrientName") == name:
            return nutrient.get("value")
    return None


def _fallback_foods(query: str) -> list[dict]:
    estimates = {
        "chicken": {"calories": 165, "protein_g": 31, "carbs_g": 0, "fat_g": 3.6},
        "rice": {"calories": 130, "protein_g": 2.7, "carbs_g": 28, "fat_g": 0.3},
        "salad": {"calories": 50, "protein_g": 2, "carbs_g": 8, "fat_g": 1},
        "egg": {"calories": 78, "protein_g": 6, "carbs_g": 0.6, "fat_g": 5},
        "bread": {"calories": 80, "protein_g": 3, "carbs_g": 15, "fat_g": 1},
    }
    query_lower = query.lower()
    for key, macros in estimates.items():
        if key in query_lower:
            return [{"fdc_id": 0, "description": query, **macros}]
    return [{"fdc_id": 0, "description": query, "calories": 200, "protein_g": 10, "carbs_g": 25, "fat_g": 8}]


def _estimate_calories(name: str) -> float:
    return _fallback_foods(name)[0]["calories"]
