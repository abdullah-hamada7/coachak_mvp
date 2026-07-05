"""Coachak API core configuration."""

from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql+asyncpg://coachak:coachak@localhost:5432/coachak"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "dev-secret-change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7
    usda_api_key: str = ""
    groq_api_key: str = ""
    groq_chat_model: str = "llama-3.3-70b-versatile"
    groq_vision_model: str = "meta-llama/llama-4-scout-17b-16e-instruct"
    elevenlabs_api_key: str = ""
    elevenlabs_voice_id: str = "pNInz6obpgDQGcFmaJgB"
    elevenlabs_model: str = "eleven_multilingual_v2"
    fitness_knowledge_path: str = "../../packages/fitness-knowledge"
    embedding_dimensions: int = 768
    rag_chunk_size: int = 900
    rag_chunk_overlap: int = 150
    rag_candidate_limit: int = 20
    rag_min_rrf_score: float = 0.012
    rag_episodic_min_score: float = 0.15
    owner_emails: str = "chief.abdullah14@gmail.com"

    @property
    def owner_email_set(self) -> set[str]:
        return {email.strip().lower() for email in self.owner_emails.split(",") if email.strip()}

    @field_validator("groq_chat_model", mode="before")
    @classmethod
    def default_chat_model(cls, value: str | None) -> str:
        return value or "llama-3.3-70b-versatile"

    @field_validator("groq_vision_model", mode="before")
    @classmethod
    def default_vision_model(cls, value: str | None) -> str:
        if not value or value == "llama-3.2-11b-vision-preview":
            return "meta-llama/llama-4-scout-17b-16e-instruct"
        return value

    @property
    def knowledge_dir(self) -> Path:
        base = Path(__file__).resolve().parent.parent
        path = Path(self.fitness_knowledge_path)
        if not path.is_absolute():
            path = (base / path).resolve()
        return path


@lru_cache
def get_settings() -> Settings:
    return Settings()
