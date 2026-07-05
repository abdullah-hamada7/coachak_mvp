"""RAG memory service with pgvector and hybrid retrieval."""

from __future__ import annotations

import hashlib
from pathlib import Path
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.db_models import CoachMessage, KnowledgeChunk
from app.services.rag.chunking import chunk_document
from app.services.rag.embeddings import EMBEDDING_VERSION, embed_text, feature_hash_embedding
from app.services.rag.retrieval import retrieve_episodic_memory as _retrieve_episodic_memory
from app.services.rag.retrieval import retrieve_knowledge_hybrid

settings = get_settings()


def _hash_embedding(text_content: str, dim: int | None = None) -> list[float]:
    """Backward-compatible alias used by eval tests."""
    return feature_hash_embedding(text_content, dim=dim)


def _file_content_hash(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()


async def ingest_knowledge_corpus(db: AsyncSession, *, force: bool = False) -> int:
    """Load fitness-knowledge corpus into pgvector with semantic chunking.

    Re-ingests files when content hash or embedding version changes.
    Removes chunks for deleted source files.
    """
    knowledge_dir = settings.knowledge_dir
    if not knowledge_dir.exists():
        return 0

    existing_rows = await db.execute(select(KnowledgeChunk))
    existing_by_source: dict[str, list[KnowledgeChunk]] = {}
    for row in existing_rows.scalars().all():
        existing_by_source.setdefault(row.source_file, []).append(row)

    disk_files: dict[str, Path] = {}
    for path in sorted(knowledge_dir.rglob("*")):
        if path.suffix not in (".md", ".json", ".txt"):
            continue
        rel = str(path.relative_to(knowledge_dir))
        disk_files[rel] = path

    if not force and not existing_by_source and not disk_files:
        return 0

    # Drop orphaned sources no longer on disk.
    orphaned = set(existing_by_source) - set(disk_files)
    if orphaned:
        await db.execute(delete(KnowledgeChunk).where(KnowledgeChunk.source_file.in_(orphaned)))

    ingested = 0
    for rel_path, path in disk_files.items():
        content = path.read_text(encoding="utf-8")
        if len(content.strip()) < 20:
            continue

        content_hash = _file_content_hash(content)
        category = path.parent.name if path.parent != knowledge_dir else "general"
        title = path.stem.replace("_", " ").title()

        current = existing_by_source.get(rel_path, [])
        if current and not force:
            meta = current[0].metadata_json or {}
            if (
                meta.get("content_hash") == content_hash
                and meta.get("embedding_version") == EMBEDDING_VERSION
            ):
                continue

        if current:
            await db.execute(delete(KnowledgeChunk).where(KnowledgeChunk.source_file == rel_path))

        doc_chunks = chunk_document(
            content,
            title,
            max_chars=settings.rag_chunk_size,
            overlap=settings.rag_chunk_overlap,
        )
        for doc_chunk in doc_chunks:
            embed_input = f"{doc_chunk.title}\n{doc_chunk.content}"
            embedding = await embed_text(embed_input)
            chunk = KnowledgeChunk(
                source_file=rel_path,
                category=category,
                title=doc_chunk.title,
                content=doc_chunk.content,
                embedding=embedding,
                metadata_json={
                    "file": path.name,
                    "content_hash": content_hash,
                    "chunk_index": doc_chunk.chunk_index,
                    "embedding_version": EMBEDDING_VERSION,
                },
            )
            db.add(chunk)
            ingested += 1

    await db.flush()
    return ingested


async def retrieve_knowledge(
    db: AsyncSession,
    query: str,
    limit: int = 5,
    *,
    categories: list[str] | None = None,
) -> list[dict]:
    """Hybrid vector + keyword search over knowledge corpus."""
    return await retrieve_knowledge_hybrid(
        db,
        query,
        limit=limit,
        candidate_limit=settings.rag_candidate_limit,
        categories=categories,
        min_rrf_score=settings.rag_min_rrf_score,
    )


async def store_coach_message(
    db: AsyncSession,
    user_id: UUID,
    thread_id: str,
    role: str,
    content: str,
) -> CoachMessage:
    embedding = await embed_text(content) if role == "user" else None
    msg = CoachMessage(
        user_id=user_id,
        thread_id=thread_id,
        role=role,
        content=content,
        embedding=embedding,
    )
    db.add(msg)
    await db.flush()
    return msg


async def retrieve_episodic_memory(
    db: AsyncSession,
    user_id: UUID,
    query: str,
    limit: int = 5,
    *,
    thread_id: str | None = None,
    exclude_content: str | None = None,
) -> list[dict]:
    return await _retrieve_episodic_memory(
        db,
        user_id,
        query,
        limit=limit,
        thread_id=thread_id,
        exclude_content=exclude_content,
    )
