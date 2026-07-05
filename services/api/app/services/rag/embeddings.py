"""Text embeddings for vector search.

Uses feature hashing over tokenized text — deterministic, no external API,
and meaningfully groups documents that share domain terms (unlike raw SHA256).
"""

from __future__ import annotations

import hashlib
import math
import re

from app.core.config import get_settings

settings = get_settings()

EMBEDDING_VERSION = "feature_hash_v1"
_TOKEN_RE = re.compile(r"[a-z0-9]+")


def tokenize(text: str) -> list[str]:
    return [t for t in _TOKEN_RE.findall(text.lower()) if len(t) >= 2]


def feature_hash_embedding(text_content: str, dim: int | None = None) -> list[float]:
    """Hash tokens into a fixed-size L2-normalized vector."""
    dim = dim or settings.embedding_dimensions
    vec = [0.0] * dim
    tokens = tokenize(text_content)
    if not tokens:
        return vec

    for token in tokens:
        digest = hashlib.blake2b(token.encode(), digest_size=8).digest()
        idx = int.from_bytes(digest[:4], "big") % dim
        sign = 1.0 if digest[4] & 1 else -1.0
        vec[idx] += sign

        # Bigrams improve phrase sensitivity for fitness terms.
        if len(token) > 4:
            for n in (2, 3):
                for i in range(len(token) - n + 1):
                    gram = token[i : i + n]
                    g_digest = hashlib.blake2b(gram.encode(), digest_size=8).digest()
                    g_idx = int.from_bytes(g_digest[:4], "big") % dim
                    g_sign = 1.0 if g_digest[4] & 1 else -1.0
                    vec[g_idx] += g_sign * 0.5

    norm = math.sqrt(sum(v * v for v in vec))
    if norm == 0:
        return vec
    return [v / norm for v in vec]


async def embed_text(text_content: str) -> list[float]:
    return feature_hash_embedding(text_content)
