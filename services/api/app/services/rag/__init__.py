"""RAG pipeline: chunking, embeddings, hybrid retrieval, and context assembly."""

from app.services.rag.context import format_rag_context
from app.services.rag.embeddings import embed_text, feature_hash_embedding
from app.services.rag.retrieval import retrieve_knowledge_hybrid

__all__ = [
    "embed_text",
    "feature_hash_embedding",
    "format_rag_context",
    "retrieve_knowledge_hybrid",
]
