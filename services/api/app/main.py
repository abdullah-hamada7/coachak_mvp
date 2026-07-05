"""Coachak FastAPI application."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, select

from app.core.database import async_session_factory
from app.models.db_models import KnowledgeChunk
from app.routes import auth, chat, logs, plans, progress, subscriptions, users, vision
from app.services.memory import ingest_knowledge_corpus

logger = logging.getLogger("coachak.rag")


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with async_session_factory() as session:
        try:
            count = await ingest_knowledge_corpus(session)
            await session.commit()
            if count:
                logger.info("Ingested or refreshed %s knowledge chunks", count)
        except Exception as exc:
            logger.exception("Knowledge ingestion failed: %s", exc)
    yield


app = FastAPI(
    title="Coachak API",
    description="AI-powered fitness coaching platform",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(chat.router)
app.include_router(plans.router)
app.include_router(logs.router)
app.include_router(vision.router)
app.include_router(progress.router)
app.include_router(subscriptions.router)


@app.get("/health")
async def health():
    chunk_count = 0
    try:
        async with async_session_factory() as session:
            chunk_count = await session.scalar(select(func.count()).select_from(KnowledgeChunk)) or 0
    except Exception:
        chunk_count = -1
    return {
        "status": "ok",
        "service": "coachak-api",
        "knowledge_chunks": chunk_count,
    }
