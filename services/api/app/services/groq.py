"""Groq LLM integration with graceful fallbacks."""

from __future__ import annotations

import base64
import json
import logging
from typing import Any

import httpx

from app.core.config import get_settings

settings = get_settings()
logger = logging.getLogger("coachak.groq")


async def generate_text(prompt: str, system: str | None = None) -> str:
    """Generate text; returns fallback string on any failure."""
    if not settings.groq_api_key:
        return _fallback_response(prompt)

    headers = {
        "Authorization": f"Bearer {settings.groq_api_key}",
        "Content-Type": "application/json",
    }

    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    payload = {
        "model": settings.groq_chat_model,
        "messages": messages,
        "temperature": 0.7,
    }

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post("https://api.groq.com/openai/v1/chat/completions", json=payload, headers=headers)
            resp.raise_for_status()
            data = resp.json()
            return data["choices"][0]["message"]["content"] or ""
    except Exception as exc:
        logger.warning("Groq generate_text failed, using fallback: %s", exc)
        return _fallback_response(prompt)


async def generate_structured(prompt: str, schema_hint: str, system: str | None = None) -> dict[str, Any]:
    """Generate structured JSON; returns {} on any failure."""
    if not settings.groq_api_key:
        return {}

    try:
        structured_prompt = (
            f"{prompt}\n\n"
            f"Respond ONLY with valid JSON matching this schema:\n{schema_hint}"
        )

        headers = {
            "Authorization": f"Bearer {settings.groq_api_key}",
            "Content-Type": "application/json",
        }

        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": structured_prompt})

        payload = {
            "model": settings.groq_chat_model,
            "messages": messages,
            "response_format": {"type": "json_object"},
            "temperature": 0.2,
        }

        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post("https://api.groq.com/openai/v1/chat/completions", json=payload, headers=headers)
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"]
            parsed = _parse_json(content)
            if not parsed:
                logger.warning("Groq returned unparseable JSON; falling back.")
            return parsed
    except Exception as exc:
        logger.warning("Groq generate_structured failed: %s", exc)
        return {}


async def analyze_food_image(image_bytes: bytes, mime_type: str = "image/jpeg") -> dict[str, Any]:
    """Analyze food image; returns fallback analysis on any failure."""
    if not settings.groq_api_key:
        return _fallback_food_analysis()

    # Encode image to Base64
    base64_image = base64.b64encode(image_bytes).decode("utf-8")

    headers = {
        "Authorization": f"Bearer {settings.groq_api_key}",
        "Content-Type": "application/json",
    }

    # Format OpenAI-compatible vision payload
    payload = {
        "model": settings.groq_vision_model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": (
                            "Analyze this food image. Identify each food item with portion estimate and confidence (0-1). "
                            "Return JSON: {\"items\": [{\"name\": str, \"portion_estimate\": str, \"confidence\": float}], "
                            "\"notes\": str}"
                        ),
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime_type};base64,{base64_image}"
                        },
                    },
                ],
            }
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
    }

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post("https://api.groq.com/openai/v1/chat/completions", json=payload, headers=headers)
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"]
            parsed = _parse_json(content)
            if not parsed.get("items"):
                return _fallback_food_analysis()
            return parsed
    except Exception as exc:
        logger.warning("Groq food analysis failed, using fallback: %s", exc)
        return _fallback_food_analysis()


def _parse_json(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        text = "\n".join(lines[1:-1] if lines[-1].startswith("```") else lines[1:])
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}") + 1
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end])
            except json.JSONDecodeError:
                return {}
        return {}


def _fallback_response(prompt: str) -> str:
    lower = prompt.lower()
    if "workout" in lower or "exercise" in lower:
        return "I recommend focusing on compound movements with progressive overload. Let me generate a plan for you."
    if "nutrition" in lower or "meal" in lower:
        return "A balanced approach with adequate protein will support your goals. I'll create a meal plan."
    return "I'm your Coachak AI coach. Tell me about your fitness goals and I'll help you reach them!"


def _fallback_food_analysis() -> dict[str, Any]:
    return {
        "items": [
            {"name": "Mixed meal", "portion_estimate": "1 plate", "confidence": 0.5},
        ],
        "notes": "Could not reach vision model; please confirm items manually.",
    }
