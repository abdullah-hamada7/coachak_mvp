"""Vision routes: food analysis and form sessions."""

import base64
import logging

from fastapi import APIRouter, Depends, File, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.db_models import FormSession, User
from app.services.elevenlabs import synthesize_speech
from app.services.gamification import XP_REWARDS, award_xp, check_and_award_badges
from app.services.groq import analyze_food_image
from app.services.subscriptions import check_feature_access, consume_feature
from app.services.usda import ground_food_items

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/vision", tags=["vision"])


class FormCorrectionEvent(BaseModel):
    timestamp_ms: int
    cue: str
    severity: str = "info"


class FormSessionUpload(BaseModel):
    exercise: str
    rep_count: int
    improper_rep_count: int = Field(default=0, ge=0)
    target_reps: int | None = Field(default=None, ge=0)
    duration_seconds: int
    difficulty: str | None = None
    corrections: list[FormCorrectionEvent] = Field(default_factory=list)
    avg_rom_score: float | None = Field(default=None, ge=0, le=1)
    form_score: int | None = Field(default=None, ge=0, le=100)
    form_grade: str | None = None
    clinical_rom_score: int | None = Field(default=None, ge=0, le=100)
    clinical_stability_score: int | None = Field(default=None, ge=0, le=100)
    clinical_asymmetry_deg: int | None = Field(default=None, ge=0)
    clinical_weight_shift_pct: int | None = Field(default=None, ge=0)
    eccentric_seconds: float | None = Field(default=None, ge=0)
    concentric_seconds: float | None = Field(default=None, ge=0)
    clinical_diagnosis_ar: str | None = None
    clinical_observations_ar: list[str] | None = None


class CoachSpeakRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)


@router.post("/coach/speak")
async def coach_speak(
    body: CoachSpeakRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Synthesize Arabic coaching speech via ElevenLabs. Always returns text; audio when configured."""
    from app.services.subscriptions import effective_tier, tier_limits

    text = body.text.strip()
    settings = get_settings()
    audio_b64: str | None = None
    voice_limit = tier_limits(effective_tier(user)).get("voice_cues")

    if voice_limit != 0 and settings.elevenlabs_api_key:
        check_feature_access(user, "voice_cues")
        try:
            audio_bytes = await synthesize_speech(text)
            audio_b64 = base64.b64encode(audio_bytes).decode("ascii")
            consume_feature(user, "voice_cues")
            await db.flush()
        except Exception:
            logger.exception("ElevenLabs TTS failed for coaching cue")

    return {
        "text": text,
        "audio_base64": audio_b64,
        "has_audio": audio_b64 is not None,
    }


@router.post("/food/analyze")
async def analyze_food(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    check_feature_access(user, "food_scans")
    image_bytes = await file.read()
    mime = file.content_type or "image/jpeg"
    analysis = await analyze_food_image(image_bytes, mime)

    items = analysis.get("items", [])
    grounded = await ground_food_items(items)

    total_cal = sum(i.get("calories") or 0 for i in grounded)
    total_p = sum(i.get("protein_g") or 0 for i in grounded)
    total_c = sum(i.get("carbs_g") or 0 for i in grounded)
    total_f = sum(i.get("fat_g") or 0 for i in grounded)

    consume_feature(user, "food_scans")
    await db.flush()

    return {
        "items": grounded,
        "total_calories": total_cal,
        "total_protein_g": total_p,
        "total_carbs_g": total_c,
        "total_fat_g": total_f,
        "notes": analysis.get("notes"),
    }


def form_score_xp_bonus(form_score: int | None) -> int:
    """Bonus XP for strong form (0–100 avg score from session)."""
    if form_score is None:
        return 0
    if form_score >= 90:
        return 20
    if form_score >= 80:
        return 15
    if form_score >= 70:
        return 10
    if form_score >= 60:
        return 5
    return 0


@router.post("/form/session")
async def upload_form_session(
    body: FormSessionUpload,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    check_feature_access(user, "form_sessions")
    meta = {
        "type": "session_meta",
        "improper_rep_count": body.improper_rep_count,
        "difficulty": body.difficulty,
        "form_score": body.form_score,
        "form_grade": body.form_grade,
        "target_reps": body.target_reps or 0,
        "clinical_rom_score": body.clinical_rom_score,
        "clinical_stability_score": body.clinical_stability_score,
        "clinical_asymmetry_deg": body.clinical_asymmetry_deg,
        "clinical_weight_shift_pct": body.clinical_weight_shift_pct,
        "eccentric_seconds": body.eccentric_seconds,
        "concentric_seconds": body.concentric_seconds,
        "clinical_diagnosis_ar": body.clinical_diagnosis_ar,
        "clinical_observations_ar": body.clinical_observations_ar,
    }
    session = FormSession(
        user_id=user.id,
        exercise=body.exercise,
        rep_count=body.rep_count,
        duration_seconds=body.duration_seconds,
        corrections=[meta, *[c.model_dump() for c in body.corrections]],
        avg_rom_score=body.avg_rom_score,
    )
    db.add(session)

    # Award XP only when the athlete hits or exceeds their set target reps
    target = body.target_reps or 0
    target_met = body.rep_count >= target if target > 0 else (body.rep_count > 0)

    xp_awarded = 0
    form_bonus = 0
    badges: list = []
    if target_met:
        base_xp = XP_REWARDS["form_session"]
        form_bonus = form_score_xp_bonus(body.form_score)
        xp_awarded = base_xp + form_bonus
        await award_xp(db, user, base_xp, "form_session")
        if form_bonus > 0:
            await award_xp(db, user, form_bonus, "form_score_bonus")
        badges = await check_and_award_badges(db, user)

    consume_feature(user, "form_sessions")
    await db.commit()
    return {
        "status": "recorded",
        "rep_count": body.rep_count,
        "improper_rep_count": body.improper_rep_count,
        "target_reps": target,
        "target_met": target_met,
        "difficulty": body.difficulty,
        "form_score": body.form_score,
        "form_grade": body.form_grade,
        "form_score_bonus": form_bonus,
        "xp_awarded": xp_awarded,
        "new_badges": badges,
    }
