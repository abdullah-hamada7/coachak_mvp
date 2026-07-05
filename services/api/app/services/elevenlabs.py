"""ElevenLabs text-to-speech for Arabic coaching cues."""

import logging

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

ELEVENLABS_TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"


async def synthesize_speech(text: str) -> bytes:
    """Return MP3 bytes for the given Arabic (or any) text."""
    settings = get_settings()
    if not settings.elevenlabs_api_key:
        raise RuntimeError("ELEVENLABS_API_KEY is not configured")

    url = ELEVENLABS_TTS_URL.format(voice_id=settings.elevenlabs_voice_id)
    payload = {
        "text": text,
        "model_id": settings.elevenlabs_model,
        "voice_settings": {
            "stability": 0.45,
            "similarity_boost": 0.8,
            "style": 0.2,
            "use_speaker_boost": True,
        },
    }
    headers = {
        "xi-api-key": settings.elevenlabs_api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, json=payload, headers=headers)
        if response.status_code >= 400:
            logger.error("ElevenLabs TTS error %s: %s", response.status_code, response.text[:300])
            response.raise_for_status()
        return response.content
