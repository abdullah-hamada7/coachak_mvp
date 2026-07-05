"""RAG pipeline unit tests."""

import pytest

from app.services.rag.chunking import chunk_document
from app.services.rag.context import categories_for_message, format_rag_context
from app.services.rag.embeddings import embed_text, feature_hash_embedding, tokenize
from app.services.rag.retrieval import _reciprocal_rank_fusion, _sanitize_fts_query


def test_tokenize_lowercases_and_filters_short_tokens():
    tokens = tokenize("Squat Form: Knee Valgus at 90°")
    assert "squat" in tokens
    assert "form" in tokens
    assert "knee" in tokens


def test_feature_hash_embedding_deterministic():
    e1 = feature_hash_embedding("progressive overload principles")
    e2 = feature_hash_embedding("progressive overload principles")
    assert e1 == e2


def test_feature_hash_embedding_dimension():
    e = feature_hash_embedding("test query", dim=768)
    assert len(e) == 768


def test_similar_texts_have_higher_cosine_than_unrelated():
    a = feature_hash_embedding("squat knee valgus form correction")
    b = feature_hash_embedding("squat knee tracking push knees out")
    c = feature_hash_embedding("post workout protein meal timing")
    sim_ab = sum(x * y for x, y in zip(a, b))
    sim_ac = sum(x * y for x, y in zip(a, c))
    assert sim_ab > sim_ac


@pytest.mark.asyncio
async def test_embed_text_async_wrapper():
    e = await embed_text("deadlift hip hinge")
    assert len(e) == 768


def test_chunk_markdown_by_headers():
    content = (
        "# Title\n\nIntro paragraph with enough text to pass chunk thresholds.\n\n"
        "## Section A\n\nDetail A with sufficient content for chunking.\n\n"
        "## Section B\n\nDetail B with sufficient content for chunking."
    )
    chunks = chunk_document(content, "Squat Form")
    assert len(chunks) >= 2
    assert any("Section A" in c.title for c in chunks)


def test_chunk_respects_overlap_for_long_text():
    paragraph = "word " * 300
    content = f"{paragraph.strip()}\n\n{paragraph.strip()}"
    chunks = chunk_document(content, "Long Doc", max_chars=400, overlap=80)
    assert len(chunks) >= 2


def test_chunk_json_exercises():
    content = (
        '{"exercises": ['
        '{"id": "squat", "name": "Squat", "pattern": "squat"},'
        '{"id": "curl", "name": "Curl", "pattern": "isolation"}'
        "]}"
    )
    chunks = chunk_document(content, "Exercise Library")
    assert len(chunks) == 2
    assert "Squat" in chunks[0].title


def test_rrf_favors_items_in_both_lists():
    scores = _reciprocal_rank_fusion([["a", "b", "c"], ["a", "d"]])
    assert scores["a"] > scores["b"]
    assert scores["a"] > scores["d"]


def test_sanitize_fts_query_strips_punctuation():
    assert _sanitize_fts_query("What's knee valgus?") == "what knee valgus"


def test_categories_for_form_questions():
    cats = categories_for_message("chat", "check my squat form")
    assert cats is not None
    assert "pose-detection" in cats


def test_categories_for_nutrition():
    cats = categories_for_message("chat", "how much protein after workout")
    assert cats == ["nutrition"]


def test_format_rag_context_filters_low_scores():
    chunks = [
        {"title": "Good", "content": "Useful info", "source_file": "a.md", "score": 0.05},
        {"title": "Weak", "content": "Noise", "source_file": "b.md", "score": 0.001},
    ]
    context = format_rag_context(chunks, min_score=0.012)
    assert "Good" in context
    assert "Weak" not in context
    assert "relevance=" in context
