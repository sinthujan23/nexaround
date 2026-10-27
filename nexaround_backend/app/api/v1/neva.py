"""Neva chat with real places on a map — see `app.services.neva_service`.

Spoken questions and Neva's spoken replies: `app.services.neva_voice`.
"""
import asyncio
import json
import logging
from typing import Literal, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.schemas.place import PlaceResponse
from app.services import neva_service, neva_voice
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/neva", tags=["neva"])


class ChatMessageItem(BaseModel):
    role: str = Field(..., pattern="^(user|model|assistant)$")
    text: str = Field(..., min_length=1, max_length=4000)


class NevaChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    latitude: Optional[float] = Field(None, ge=-90.0, le=90.0)
    longitude: Optional[float] = Field(None, ge=-180.0, le=180.0)
    area: Optional[str] = Field(None, max_length=200)
    history: Optional[list[ChatMessageItem]] = Field(None, description="Recent conversation history")
    # "voice": a short reply the app will read aloud.
    mode: Literal["text", "voice"] = "text"


class SpeechChunk(BaseModel):
    text: str
    lang: str = ""
    sig: str


class NevaChatResponse(BaseModel):
    text: str
    # Empty unless Neva searched; then nearest first, pinned 1..n on the map.
    places: list[PlaceResponse] = []
    query: str = ""
    radius_m: int = 0
    # The reply as clips the app may ask /neva/speak to say, first one short.
    speech: list[SpeechChunk] = []
    lang: str = ""


class NevaVoiceResponse(NevaChatResponse):
    # What the user said, for their chat bubble and the history.
    transcript: str = ""
    # The day's spoken allowance (or the API budget) is used up: text only.
    voice_paused: bool = False


class SpeakRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=1000)
    lang: str = Field("", max_length=16)
    sig: str = Field(..., min_length=8, max_length=128)


async def _gemini_key(db: AsyncSession) -> str:
    raw_key = await SettingsService(db).get_setting("gemini_api_key")
    return (raw_key or "").strip().strip('"').strip("'")


def _history(raw: Optional[str]) -> Optional[list[dict]]:
    """The history form field: JSON in the same shape /neva/chat takes."""
    if not raw:
        return None
    try:
        items = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(items, list):
        return None
    history = []
    for item in items[-20:]:
        try:
            history.append(ChatMessageItem(**item).model_dump())
        except (TypeError, ValidationError):
            continue
    return history or None


@router.post("/chat", response_model=NevaChatResponse)
async def neva_chat(
    body: NevaChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """One Neva reply. "Where is…" questions come back with real places to map."""
    api_key = await _gemini_key(db)
    if not api_key:
        raise HTTPException(status_code=500, detail="Gemini API Key not configured")
    has_location = body.latitude is not None and body.longitude is not None
    history_list = [h.model_dump() for h in body.history] if body.history else None
    try:
        reply = await neva_service.chat(
            body.message,
            api_key=api_key,
            latitude=body.latitude if has_location else None,
            longitude=body.longitude if has_location else None,
            area=body.area or "",
            history=history_list,
            user_id=current_user.id,
            voice=body.mode == "voice",
        )
    except neva_service.NevaUnavailable as e:
        # The app answers through the plain proxy instead.
        logger.warning("Neva chat unavailable: %s", e)
        raise HTTPException(status_code=503, detail="Neva is unavailable right now.")
    if not reply["text"]:
        raise HTTPException(status_code=503, detail="Neva returned an empty reply.")
    # Signing costs nothing; speech is only made if the app asks for a clip.
    speech = neva_voice.speech_for(reply["text"], reply["lang"], current_user.id)
    return NevaChatResponse(**reply, speech=speech)


@router.post("/voice", response_model=NevaVoiceResponse)
async def neva_voice_turn(
    audio: UploadFile = File(..., description="The spoken question: 16 kHz mono WAV, at most 30 s"),
    latitude: Optional[float] = Form(None, ge=-90.0, le=90.0),
    longitude: Optional[float] = Form(None, ge=-180.0, le=180.0),
    area: Optional[str] = Form(None, max_length=200),
    history: Optional[str] = Form(None, max_length=60000, description="JSON list of {role, text}"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """A spoken question: what the user said, and Neva's short reply to say aloud."""
    if not await neva_voice.is_enabled():
        raise HTTPException(status_code=503, detail="voice_off")
    clip = await audio.read(neva_voice.MAX_CLIP_BYTES + 1)
    if len(clip) > neva_voice.MAX_CLIP_BYTES:
        raise HTTPException(status_code=413, detail="The recording is too long.")
    mime = neva_voice.clip_mime(clip)
    if mime is None:
        raise HTTPException(status_code=415, detail="The recording is not an audio file.")
    seconds = neva_voice.clip_seconds(clip, mime)
    if seconds is not None and seconds > neva_voice.MAX_CLIP_SECONDS:
        raise HTTPException(status_code=413, detail="The recording is too long.")
    api_key = await _gemini_key(db)
    if not api_key:
        raise HTTPException(status_code=500, detail="Gemini API Key not configured")

    paused = False
    try:
        await neva_voice.check(current_user.id)
    except neva_voice.VoiceBlocked as e:
        if e.reason == "voice_off":
            raise HTTPException(status_code=503, detail="voice_off")
        # Hearing and answering cost a fraction of a cent; only speech stops.
        paused = True

    has_location = latitude is not None and longitude is not None
    heard, reply = await asyncio.gather(
        neva_voice.transcribe(clip, mime, api_key),
        neva_service.chat(
            "",
            api_key=api_key,
            latitude=latitude if has_location else None,
            longitude=longitude if has_location else None,
            area=area or "",
            history=_history(history),
            user_id=current_user.id,
            audio=(clip, mime),
            voice=True,
        ),
        return_exceptions=True,
    )
    if isinstance(reply, neva_service.NevaUnavailable):
        logger.warning("Neva voice unavailable: %s", reply)
        raise HTTPException(status_code=503, detail="Neva is unavailable right now.")
    if isinstance(reply, BaseException):
        raise reply
    if isinstance(heard, BaseException):
        # The answer stands; the bubble just has no words to show.
        logger.warning("Neva voice: no transcript: %s", heard)
        heard = None
    if heard == "":
        raise HTTPException(status_code=422, detail="no_speech")
    if not reply["text"]:
        raise HTTPException(status_code=503, detail="Neva returned an empty reply.")

    speech = [] if paused else neva_voice.speech_for(reply["text"], reply["lang"], current_user.id)
    return NevaVoiceResponse(**reply, speech=speech, transcript=heard or "", voice_paused=paused)


@router.post("/speak")
async def neva_speak(
    body: SpeakRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """One clip of Neva's reply as audio. Only clips /neva/chat or /neva/voice
    signed for this user are spoken."""
    if not neva_voice.verify(current_user.id, body.lang, body.text, body.sig):
        raise HTTPException(status_code=403, detail="Unknown speech.")
    try:
        audio, mime = await neva_voice.synthesize(
            body.text, body.lang, user_id=current_user.id, api_key=await _gemini_key(db),
        )
    except neva_voice.VoiceBlocked as e:
        raise HTTPException(status_code=429, detail=e.reason)
    except neva_voice.VoiceUnavailable as e:
        logger.warning("Neva voice: no audio: %s", e)
        raise HTTPException(status_code=503, detail="Neva's voice is unavailable right now.")
    return Response(content=audio, media_type=mime, headers={"Cache-Control": "private, max-age=604800"})
