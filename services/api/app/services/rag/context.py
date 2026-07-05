"""RAG context assembly with relevance filtering and citations."""

from __future__ import annotations

from app.core.config import get_settings

settings = get_settings()


def categories_for_message(intent: str, message: str) -> list[str] | None:
    """Map coach intent + message keywords to knowledge categories."""
    msg = message.lower()

    nutrition_terms = (
        "protein",
        "calorie",
        "meal",
        "eat",
        "diet",
        "macro",
        "carb",
        "nutrition",
        "food",
        "supplement",
    )
    if intent == "nutrition" or any(term in msg for term in nutrition_terms):
        return ["nutrition"]

    form_terms = (
        "form",
        "squat",
        "push-up",
        "pushup",
        "curl",
        "lunge",
        "deadlift",
        "bench",
        "press",
        "row",
        "hip hinge",
        "pose",
        "technique",
        "rom",
        "valgus",
    )
    if any(term in msg for term in form_terms):
        return ["pose-detection", "exercise-science", "exercises"]

    if intent in ("workout", "both"):
        return ["exercise-science", "exercises", "coaching", "pose-detection"]

    workout_terms = (
        "workout",
        "training",
        "exercise",
        "rep",
        "set",
        "overload",
        "hypertrophy",
        "strength",
    )
    if any(term in msg for term in workout_terms):
        return ["exercise-science", "exercises", "coaching"]

    return None


def format_rag_context(
    chunks: list[dict],
    *,
    max_chunks: int = 4,
    max_chars_per_chunk: int = 450,
    min_score: float | None = None,
) -> str:
    """Build LLM context from retrieved chunks, filtering low-relevance results."""
    if not chunks:
        return ""

    threshold = min_score if min_score is not None else settings.rag_min_rrf_score
    lines: list[str] = []
    for chunk in chunks[:max_chunks]:
        score = float(chunk.get("score") or 0)
        if score < threshold:
            continue
        title = chunk.get("title", "Source")
        source = chunk.get("source_file", "")
        content = (chunk.get("content") or "")[:max_chars_per_chunk]
        citation = f"{title} ({source})" if source else title
        lines.append(f"[{citation} | relevance={score:.2f}]: {content}")

    return "\n".join(lines)
