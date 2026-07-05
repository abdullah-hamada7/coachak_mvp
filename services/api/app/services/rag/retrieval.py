"""Hybrid retrieval: vector similarity + PostgreSQL full-text search with RRF."""

from __future__ import annotations

import re
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.services.rag.embeddings import embed_text, tokenize

settings = get_settings()

RRF_K = 60
_QUERY_SANITIZE = re.compile(r"[^\w\s-]")


def _sanitize_fts_query(query: str) -> str:
    cleaned = _QUERY_SANITIZE.sub(" ", query.lower()).strip()
    tokens = [t for t in cleaned.split() if len(t) >= 2]
    return " ".join(tokens[:12])


def _reciprocal_rank_fusion(ranked_ids: list[list[str]]) -> dict[str, float]:
    scores: dict[str, float] = {}
    for ranked in ranked_ids:
        for rank, doc_id in enumerate(ranked):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (RRF_K + rank + 1)
    return scores


def _lexical_boost(query: str, row: dict) -> float:
    tokens = tokenize(query)
    if not tokens:
        return 0.0
    haystack = f"{row.get('title', '')} {row.get('content', '')}".lower()
    return sum(0.004 for token in tokens if token in haystack)


def _dedupe_by_source(results: list[dict], limit: int) -> list[dict]:
    seen: set[str] = set()
    deduped: list[dict] = []
    for row in results:
        source = row.get("source_file") or row.get("title") or ""
        if source in seen:
            continue
        seen.add(source)
        deduped.append(row)
        if len(deduped) >= limit:
            break
    return deduped


async def _search_knowledge(
    db: AsyncSession,
    query: str,
    embedding: list[float],
    *,
    candidate_limit: int,
    categories: list[str] | None,
) -> list[dict]:
    vec_str = "[" + ",".join(str(v) for v in embedding) + "]"
    category_filter = ""
    params: dict = {
        "vec": vec_str,
        "candidate_limit": candidate_limit,
    }
    if categories:
        category_filter = "AND category = ANY(:categories)"
        params["categories"] = categories

    vector_result = await db.execute(
        text(
            f"""
            SELECT id::text AS id, title, content, category, source_file,
                   1 - (embedding <=> :vec) AS vector_score
            FROM knowledge_chunks
            WHERE embedding IS NOT NULL
            {category_filter}
            ORDER BY embedding <=> :vec
            LIMIT :candidate_limit
            """
        ),
        params,
    )
    vector_rows = [dict(row) for row in vector_result.mappings().all()]

    fts_query = _sanitize_fts_query(query)
    keyword_rows: list[dict] = []
    if fts_query:
        fts_params = {**params, "query": fts_query}
        keyword_result = await db.execute(
            text(
                f"""
                SELECT id::text AS id, title, content, category, source_file,
                       ts_rank_cd(
                         to_tsvector('english', coalesce(title, '') || ' ' || content),
                         plainto_tsquery('english', :query)
                       ) AS keyword_score
                FROM knowledge_chunks
                WHERE to_tsvector('english', coalesce(title, '') || ' ' || content)
                      @@ plainto_tsquery('english', :query)
                {category_filter}
                ORDER BY keyword_score DESC
                LIMIT :candidate_limit
                """
            ),
            fts_params,
        )
        keyword_rows = [dict(row) for row in keyword_result.mappings().all()]

    vector_ids = [row["id"] for row in vector_rows]
    keyword_ids = [row["id"] for row in keyword_rows]
    rrf_scores = _reciprocal_rank_fusion([vector_ids, keyword_ids])

    row_by_id: dict[str, dict] = {}
    for row in vector_rows + keyword_rows:
        row_by_id[row["id"]] = row

    ranked = sorted(rrf_scores.items(), key=lambda item: item[1], reverse=True)
    results: list[dict] = []
    for doc_id, rrf_score in ranked:
        row = row_by_id[doc_id]
        score = rrf_score + _lexical_boost(query, row)
        results.append(
            {
                "title": row["title"],
                "content": row["content"],
                "category": row["category"],
                "source_file": row["source_file"],
                "score": round(score, 4),
                "vector_score": float(row.get("vector_score") or 0.0),
                "keyword_score": float(row.get("keyword_score") or 0.0),
            }
        )
    return results


async def retrieve_knowledge_hybrid(
    db: AsyncSession,
    query: str,
    *,
    limit: int = 5,
    candidate_limit: int = 20,
    categories: list[str] | None = None,
    min_rrf_score: float = 0.012,
) -> list[dict]:
    """Retrieve knowledge chunks using hybrid vector + keyword search."""
    if not query.strip():
        return []

    embedding = await embed_text(query)
    results = await _search_knowledge(
        db,
        query,
        embedding,
        candidate_limit=candidate_limit,
        categories=categories,
    )

    # Fallback: widen search if category filter is too strict.
    if categories and len([r for r in results if r["score"] >= min_rrf_score]) < limit:
        unfiltered = await _search_knowledge(
            db,
            query,
            embedding,
            candidate_limit=candidate_limit,
            categories=None,
        )
        merged = {r["source_file"] + r["title"]: r for r in results}
        for row in unfiltered:
            key = row["source_file"] + row["title"]
            if key not in merged or row["score"] > merged[key]["score"]:
                merged[key] = row
        results = sorted(merged.values(), key=lambda item: item["score"], reverse=True)

    filtered = [row for row in results if row["score"] >= min_rrf_score]
    return _dedupe_by_source(filtered, limit)


async def retrieve_episodic_memory(
    db: AsyncSession,
    user_id: UUID,
    query: str,
    *,
    thread_id: str | None = None,
    exclude_content: str | None = None,
    limit: int = 5,
    min_vector_score: float | None = None,
) -> list[dict]:
    """Retrieve relevant past coach conversations with score threshold."""
    min_score = min_vector_score if min_vector_score is not None else settings.rag_episodic_min_score
    embedding = await embed_text(query)
    vec_str = "[" + ",".join(str(v) for v in embedding) + "]"

    filters = ["user_id = :user_id", "embedding IS NOT NULL"]
    params: dict = {
        "user_id": str(user_id),
        "vec": vec_str,
        "limit": limit * 3,
    }
    if thread_id:
        filters.append("thread_id = :thread_id")
        params["thread_id"] = thread_id
    if exclude_content:
        filters.append("content <> :exclude_content")
        params["exclude_content"] = exclude_content

    where_clause = " AND ".join(filters)
    result = await db.execute(
        text(
            f"""
            SELECT role, content, thread_id, created_at,
                   1 - (embedding <=> :vec) AS score
            FROM coach_messages
            WHERE {where_clause}
            ORDER BY embedding <=> :vec
            LIMIT :limit
            """
        ),
        params,
    )
    rows = [dict(row) for row in result.mappings().all()]
    return [row for row in rows if float(row.get("score") or 0) >= min_score][:limit]
