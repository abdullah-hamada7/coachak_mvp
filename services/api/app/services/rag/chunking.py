"""Semantic document chunking with structure-aware boundaries."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

_HEADER_RE = re.compile(r"^(#{1,3})\s+(.+)$", re.MULTILINE)
_PARAGRAPH_RE = re.compile(r"\n\s*\n+")


@dataclass
class DocumentChunk:
    title: str
    content: str
    chunk_index: int


def chunk_document(
    content: str,
    title: str,
    *,
    max_chars: int = 900,
    overlap: int = 150,
) -> list[DocumentChunk]:
    """Split markdown/text by headers and paragraphs with overlap."""
    content = content.strip()
    if not content:
        return []

    if content.startswith("{"):
        json_chunks = _chunk_json(content, title)
        if json_chunks:
            return json_chunks

    sections = _split_markdown_sections(content)
    chunks: list[DocumentChunk] = []
    chunk_index = 0

    for section_title, section_body in sections:
        section_label = section_title or title
        for piece in _split_with_overlap(section_body, max_chars=max_chars, overlap=overlap):
            body = piece.strip()
            if len(body) < 15:
                continue
            chunk_content = f"## {section_label}\n\n{body}" if section_title else body
            chunks.append(
                DocumentChunk(
                    title=section_label if section_title else title,
                    content=chunk_content,
                    chunk_index=chunk_index,
                )
            )
            chunk_index += 1

    if not chunks and len(content.strip()) >= 15:
        chunks.append(DocumentChunk(title=title, content=content, chunk_index=0))

    return chunks


def _split_markdown_sections(content: str) -> list[tuple[str, str]]:
    matches = list(_HEADER_RE.finditer(content))
    if not matches:
        return [("", content)]

    sections: list[tuple[str, str]] = []
    if matches[0].start() > 0:
        preamble = content[: matches[0].start()].strip()
        if preamble:
            sections.append(("", preamble))

    for i, match in enumerate(matches):
        header = match.group(2).strip()
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        body = content[start:end].strip()
        if body:
            sections.append((header, body))

    return sections or [("", content)]


def _split_with_overlap(text: str, *, max_chars: int, overlap: int) -> list[str]:
    if len(text) <= max_chars:
        return [text]

    paragraphs = [p.strip() for p in _PARAGRAPH_RE.split(text) if p.strip()]
    if not paragraphs:
        return _fixed_window_split(text, max_chars=max_chars, overlap=overlap)

    pieces: list[str] = []
    current = ""
    for para in paragraphs:
        candidate = f"{current}\n\n{para}".strip() if current else para
        if len(candidate) <= max_chars:
            current = candidate
            continue
        if current:
            pieces.extend(_split_with_overlap(current, max_chars=max_chars, overlap=overlap))
        current = para if len(para) <= max_chars else ""

        if len(para) > max_chars:
            pieces.extend(_fixed_window_split(para, max_chars=max_chars, overlap=overlap))
            current = ""

    if current:
        pieces.append(current)

    return pieces


def _fixed_window_split(text: str, *, max_chars: int, overlap: int) -> list[str]:
    pieces: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        if end < len(text):
            boundary = text.rfind(" ", start + max_chars // 2, end)
            if boundary > start:
                end = boundary
        piece = text[start:end].strip()
        if piece:
            pieces.append(piece)
        if end >= len(text):
            break
        start = max(end - overlap, start + 1)
    return pieces


def _chunk_json(content: str, title: str) -> list[DocumentChunk]:
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        return []

    chunks: list[DocumentChunk] = []
    if isinstance(data, dict) and isinstance(data.get("exercises"), list):
        for i, exercise in enumerate(data["exercises"]):
            if not isinstance(exercise, dict):
                continue
            name = exercise.get("name", exercise.get("id", "Exercise"))
            body = json.dumps(exercise, ensure_ascii=True, indent=2)
            chunks.append(
                DocumentChunk(
                    title=f"{title}: {name}",
                    content=body,
                    chunk_index=i,
                )
            )
        return chunks

    chunks.append(
        DocumentChunk(
            title=title,
            content=json.dumps(data, ensure_ascii=True, indent=2)[:900],
            chunk_index=0,
        )
    )
    return chunks
