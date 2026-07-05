"""RAG faithfulness evaluation tests."""

import pytest

from app.services.memory import _hash_embedding
from app.services.rag.chunking import chunk_document
from app.services.rag.context import format_rag_context
from app.services.rag.embeddings import feature_hash_embedding


def test_embedding_deterministic():
    e1 = _hash_embedding("progressive overload principles")
    e2 = _hash_embedding("progressive overload principles")
    assert e1 == e2


def test_embedding_dimension():
    e = _hash_embedding("test query", dim=768)
    assert len(e) == 768


def test_knowledge_corpus_has_required_topics():
    from pathlib import Path

    knowledge_dir = Path(__file__).resolve().parent.parent.parent / "packages" / "fitness-knowledge"
    required = ["progressive_overload.md", "squat_form.md", "sports_nutrition.md"]
    found = [f for f in required if list(knowledge_dir.rglob(f))]
    assert len(found) == len(required), f"Missing corpus files: {set(required) - set(found)}"


def test_rag_context_format_includes_citations():
    chunks = [
        {
            "title": "Progressive Overload",
            "content": "Increase load by 2.5-5kg weekly.",
            "source_file": "exercise-science/progressive_overload.md",
            "score": 0.04,
        },
        {
            "title": "Squat Form",
            "content": "Knees track over toes.",
            "source_file": "pose-detection/squat_form.md",
            "score": 0.03,
        },
    ]
    context = format_rag_context(chunks)
    assert "Progressive Overload" in context
    assert "Squat Form" in context
    assert "progressive_overload.md" in context
    assert len(context) > 50


def test_semantic_chunking_produces_multiple_chunks_for_corpus_files():
    from pathlib import Path

    knowledge_dir = Path(__file__).resolve().parent.parent.parent / "packages" / "fitness-knowledge"
    squat = (knowledge_dir / "pose-detection" / "squat_form.md").read_text(encoding="utf-8")
    chunks = chunk_document(squat, "Squat Form")
    assert len(chunks) >= 2


def test_related_fitness_terms_embed_closer_than_unrelated():
    squat = feature_hash_embedding("squat depth knee valgus hip angle")
    lunge = feature_hash_embedding("lunge knee tracking hip flexion")
    nutrition = feature_hash_embedding("protein shake post workout meal")
    sim_squat_lunge = sum(a * b for a, b in zip(squat, lunge))
    sim_squat_nutrition = sum(a * b for a, b in zip(squat, nutrition))
    assert sim_squat_lunge > sim_squat_nutrition
