"""Neva's voice: hearing a spoken question and saying her reply.

Client request, 2026-10-27: voice chat with Neva, built the way the industry
builds it and cheap to run. The app records a question; the backend hears it,
Neva answers, and her reply comes back as speech.

Three paid steps, each the cheapest that does the job:

  * Hearing. The recording goes straight into Neva's answering call
    (`neva_service.chat(audio=...)`). Gemini Flash-Lite writes the transcript
    for the chat bubble and the history at the same time, so the user waits
    for one model call, not two. A 3 s question costs about $0.00003.
  * Answering. The usual Neva call, told to keep spoken replies to a few plain
    sentences (`NEVA_VOICE_RULES`): speech is billed by length.
  * Speaking. Google Cloud Text-to-Speech, Chirp 3 HD voices. Measured from
    this server, Gemini's own TTS took 4-6 s before the first sound whatever
    the length, streaming included, which put Neva's voice ~10 s after the
    user stopped talking. Chirp covers 53 locales; any other language
    (Sinhala, for one) is spoken by Gemini 3.8 Flash-Lite TTS instead, slower
    but in 100+ languages. Both use the same voice, Sulafat ("warm").

What keeps it cheap:
  * Every clip is cached on disk by engine + voice + text, so a replay or a
    repeated phrase costs nothing; the app keeps its own copy as well.
  * /neva/speak only speaks text this server wrote and signed for that user
    (`sign`/`verify`), so it cannot be used as a free TTS service.
  * A daily allowance of spoken seconds per user, an off switch, and the
    platform-wide `spend_guard`. Past any of them Neva answers in text.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import io
import logging
import os
import re
import time
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx

from app.core.config import settings
from app.services import spend_guard, telemetry

logger = logging.getLogger(__name__)

# Settings keys, edited in Admin > Settings > Neva voice.
K_ENABLED = "neva_voice_enabled"
K_DAILY_SECONDS = "neva_voice_daily_seconds"
K_TTS_KEY = "google_tts_api_key"
DEFAULT_DAILY_SECONDS = 600

# Re-read at most this often. The API runs several processes, so an admin
# change reaches all of them within a minute rather than at once.
_CONFIG_TTL = 60.0
_config: dict = {}
_config_at: float = 0.0

_TIMEOUT_S = 30.0
_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta"
_CLOUD_TTS_URL = "https://texttospeech.googleapis.com/v1/text:synthesize"

_TRANSCRIBE_MODEL = "gemini-2.5-flash-lite"
_TRANSCRIBE_SYSTEM = (
    "Transcribe exactly what the speaker says, word for word, in the language "
    "they speak. Output only the transcript. If there is no speech, output nothing."
)
_NO_SPEECH_RE = re.compile(r"^\W*(no speech|silence|inaudible|\[?blank\]?)\W*$", re.IGNORECASE)

# Gemini TTS for languages Chirp does not cover: (model, telemetry SKU).
_GEMINI_TTS_MODELS = (
    ("gemini-3.8-flash-lite-tts", "gemini_tts_lite"),
    ("gemini-3.8-flash-tts", "gemini_tts_flash"),
)
_GEMINI_STYLE = "warm, friendly and relaxed, like a well-travelled friend"

VOICE = "Sulafat"

# Chirp 3 HD locales (Cloud docs, 2026-10-27), keyed by the language code
# Neva tags her reply with. Where a language has several, the first choice.
_CHIRP_LOCALES = {
    "ar": "ar-XA", "bn": "bn-IN", "bg": "bg-BG", "yue": "yue-HK", "hr": "hr-HR",
    "cs": "cs-CZ", "da": "da-DK", "nl": "nl-NL", "en": "en-US", "et": "et-EE",
    "fi": "fi-FI", "fr": "fr-FR", "de": "de-DE", "el": "el-GR", "gu": "gu-IN",
    "he": "he-IL", "iw": "he-IL", "hi": "hi-IN", "hu": "hu-HU", "id": "id-ID",
    "it": "it-IT", "ja": "ja-JP", "kn": "kn-IN", "ko": "ko-KR", "lv": "lv-LV",
    "lt": "lt-LT", "ml": "ml-IN", "zh": "cmn-CN", "cmn": "cmn-CN", "mr": "mr-IN",
    "nb": "nb-NO", "no": "nb-NO", "pl": "pl-PL", "pt": "pt-BR", "pa": "pa-IN",
    "ro": "ro-RO", "ru": "ru-RU", "sr": "sr-RS", "sk": "sk-SK", "sl": "sl-SI",
    "es": "es-US", "sw": "sw-KE", "sv": "sv-SE", "ta": "ta-IN", "te": "te-IN",
    "th": "th-TH", "tr": "tr-TR", "uk": "uk-UA", "ur": "ur-IN", "vi": "vi-VN",
}
# Regional variants Chirp also has, used when the tag names one.
_CHIRP_REGIONAL = {
    "en-au": "en-AU", "en-in": "en-IN", "en-gb": "en-GB", "en-us": "en-US",
    "fr-ca": "fr-CA", "nl-be": "nl-BE", "es-es": "es-ES", "es-us": "es-US",
}

# What one reply may cost in speech: ~40 s at a normal speaking pace.
MAX_SPOKEN_CHARS = 600
# The first clip is one short sentence so playback starts early; the rest
# are grouped so a reply is two or three requests, not ten.
_FIRST_CHUNK_MIN = 30
_CHUNK_MAX = 250

# The app records at most 30 s of 16 kHz mono WAV: 960 KB.
MAX_CLIP_BYTES = 1_200_000
# The app's 32 kbps AAC is 120 KB for 30 s; its length is not read from the
# header, so it is held to a size instead.
MAX_COMPRESSED_BYTES = 400_000
MAX_CLIP_SECONDS = 31.0

# Outside app/static on purpose: that directory is served publicly.
_CACHE_DIR = Path(os.environ.get("NEVA_VOICE_CACHE_DIR", "/app/neva_voice_cache"))
_CACHE_MAX_BYTES = 500 * 1024 * 1024
_CACHE_MAX_AGE_S = 30 * 86400
_PRUNE_EVERY = 50
_writes = 0

_MIME_EXT = {"audio/mpeg": "mp3", "audio/wav": "wav"}


class VoiceBlocked(Exception):
    """Speech refused. `reason` is "voice_off" or "voice_quota"; the app
    answers in text."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


class VoiceUnavailable(Exception):
    """No engine produced audio (or the transcript could not be made)."""


# ── Settings and allowance ──────────────────────────────────────────────────

def _as_int(value, default: int) -> int:
    try:
        return max(0, int(float(value)))
    except (TypeError, ValueError):
        return default


async def _load_config(force: bool = False) -> dict:
    global _config, _config_at
    now = time.time()
    if not force and _config and (now - _config_at) < _CONFIG_TTL:
        return _config
    try:
        from app.core.database import async_session
        from app.services.settings_service import SettingsService
        async with async_session() as db:
            svc = SettingsService(db)
            enabled = await svc.get_setting_fresh(K_ENABLED, "true")
            daily = await svc.get_setting_fresh(K_DAILY_SECONDS, str(DEFAULT_DAILY_SECONDS))
            key = await svc.get_setting_fresh(K_TTS_KEY, "")
        _config = {
            "enabled": (enabled or "").strip().lower() not in ("0", "false", "no", "off"),
            "daily_seconds": _as_int(daily, DEFAULT_DAILY_SECONDS),
            "tts_key": (key or "").strip().strip('"').strip("'"),
        }
        _config_at = now
    except Exception as e:
        logger.warning("neva_voice: could not load settings: %s", e)
        _config = _config or {"enabled": True, "daily_seconds": DEFAULT_DAILY_SECONDS, "tts_key": ""}
    return _config


async def refresh_config() -> dict:
    """Re-read now, after the admin saves; other processes follow within a minute."""
    return await _load_config(force=True)


async def is_enabled() -> bool:
    return (await _load_config())["enabled"]


def _allowance_key(user_id) -> str:
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return f"neva_voice:{telemetry._NS}:{user_id}:{day}"


async def _redis():
    from app.core.rate_limiter import get_redis_client
    return await get_redis_client()


async def seconds_today(user_id) -> float:
    """Seconds of speech made for this user today (UTC)."""
    if not user_id:
        return 0.0
    try:
        client = await _redis()
        if client is None:
            return 0.0
        value = await client.get(_allowance_key(user_id))
        return float(value) if value else 0.0
    except Exception:
        # Redis down reads as nothing spent, like spend_guard: a metrics
        # outage must not silence Neva.
        return 0.0


async def _add_seconds(user_id, seconds: float) -> None:
    if not user_id or seconds <= 0:
        return
    try:
        client = await _redis()
        if client is None:
            return
        key = _allowance_key(user_id)
        await client.incrbyfloat(key, round(seconds, 2))
        await client.expire(key, 2 * 86400)
    except Exception as e:
        logger.debug("neva_voice: allowance not recorded: %s", e)


async def check(user_id) -> None:
    """Raise VoiceBlocked if new speech should not be made for this user."""
    cfg = await _load_config()
    if not cfg["enabled"]:
        raise VoiceBlocked("voice_off")
    cap = cfg["daily_seconds"]
    if cap and user_id and await seconds_today(user_id) >= cap:
        raise VoiceBlocked("voice_quota")
    allowed, _reason = await spend_guard.allowed(user_id)
    if not allowed:
        raise VoiceBlocked("voice_quota")


# ── The recording ───────────────────────────────────────────────────────────

def clip_mime(clip: bytes) -> Optional[str]:
    """MIME type of an uploaded recording, from its first bytes; None if not audio."""
    if clip[:4] == b"RIFF" and clip[8:12] == b"WAVE":
        return "audio/wav"
    if clip[:4] == b"fLaC":
        return "audio/flac"
    if clip[:4] == b"OggS":
        return "audio/ogg"
    # The app's AAC, as .m4a (MP4) or raw ADTS frames: audio/aac to Gemini.
    if clip[4:8] == b"ftyp" or (len(clip) > 1 and clip[0] == 0xFF and clip[1] & 0xF6 == 0xF0):
        return "audio/aac"
    if clip[:3] == b"ID3" or (len(clip) > 1 and clip[0] == 0xFF and clip[1] & 0xE0 == 0xE0):
        return "audio/mp3"
    return None


def clip_seconds(clip: bytes, mime: str) -> Optional[float]:
    """Length of a WAV recording; None for other formats or a bad header."""
    if mime != "audio/wav":
        return None
    try:
        with wave.open(io.BytesIO(clip)) as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return None


async def transcribe(clip: bytes, mime: str, api_key: str) -> str:
    """What the user said, word for word; "" when there was no speech."""
    body = {
        "system_instruction": {"parts": [{"text": _TRANSCRIBE_SYSTEM}]},
        "contents": [{"role": "user", "parts": [
            {"inline_data": {"mime_type": mime, "data": base64.b64encode(clip).decode()}},
        ]}],
        "generationConfig": {"temperature": 0, "maxOutputTokens": 400},
    }
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT_S) as client:
            async with telemetry.track(
                "gemini", f"neva_transcribe:{_TRANSCRIBE_MODEL}", sku="gemini_flash_lite_audio",
            ) as t:
                resp = await client.post(
                    f"{_GEMINI_URL}/models/{_TRANSCRIBE_MODEL}:generateContent",
                    json=body,
                    headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
                )
                t.upstream(resp)
    except httpx.HTTPError as e:
        raise VoiceUnavailable(f"transcription failed: {e}") from e
    if resp.status_code != 200:
        raise VoiceUnavailable(f"transcription returned {resp.status_code}")
    try:
        parts = resp.json()["candidates"][0]["content"].get("parts") or []
    except (KeyError, IndexError, TypeError, AttributeError, ValueError):
        parts = []
    text = " ".join(
        "".join(str(p.get("text") or "") for p in parts if isinstance(p, dict)).split()
    )
    return "" if _NO_SPEECH_RE.match(text) else text


# ── What gets spoken ────────────────────────────────────────────────────────

_ACTION_RE = re.compile(r"\[action:[^\]]*\]", re.IGNORECASE)
_URL_RE = re.compile(r"https?://\S+|www\.\S+")
_EMOJI_RE = re.compile(
    "[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍⃣]+"
)
_BULLET_RE = re.compile(r"^\s*(?:[*\-•]|\d+[.)])\s+")
_MARKS_RE = re.compile(r"[*_`#<>]+")
_ENDS_RE = re.compile(r"[.!?…:;,。！？]$")
_SENTENCE_RE = re.compile(r"(?<=[.!?…])\s+|(?<=[。！？])")


def _cap(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    cut = text[:limit]
    end = max(cut.rfind(p) for p in (". ", "! ", "? ", "。", "！", "？"))
    if end > limit // 3:
        return cut[:end + 1].strip()
    space = cut.rfind(" ")
    return (cut[:space] if space > limit // 3 else cut).rstrip(",;:—– ") + "…"


def speakable(text: str) -> str:
    """Neva's reply as it should sound: no chips, links, emoji or markdown,
    each list line its own sentence, at most MAX_SPOKEN_CHARS."""
    text = _ACTION_RE.sub(" ", text)
    text = _URL_RE.sub(" ", text)
    text = _EMOJI_RE.sub("", text)
    lines = []
    for raw in text.splitlines():
        line = _MARKS_RE.sub("", _BULLET_RE.sub("", raw))
        line = " ".join(line.split()).strip(" -—–")
        if not line:
            continue
        if not _ENDS_RE.search(line):
            line += "."
        lines.append(line)
    return _cap(" ".join(lines), MAX_SPOKEN_CHARS)


def chunks(text: str) -> list[str]:
    """Split spoken text into clips: a short first one, then up to _CHUNK_MAX."""
    sentences = [s.strip() for s in _SENTENCE_RE.split(text) if s and s.strip()]
    out: list[str] = []
    current = ""
    for sentence in sentences:
        if not out:
            current = f"{current} {sentence}".strip()
            if len(current) >= _FIRST_CHUNK_MIN:
                out.append(current)
                current = ""
            continue
        if current and len(current) + 1 + len(sentence) > _CHUNK_MAX:
            out.append(current)
            current = sentence
        else:
            current = f"{current} {sentence}".strip()
    if current:
        out.append(current)
    return out


def _signing_key() -> bytes:
    # Derived, so a speech signature can never double as anything else the
    # app secret signs.
    return hashlib.sha256(b"neva-voice:" + settings.SECRET_KEY.encode()).digest()


def sign(user_id, lang: str, text: str) -> str:
    msg = f"{user_id}\n{lang}\n{text}".encode()
    return hmac.new(_signing_key(), msg, hashlib.sha256).hexdigest()[:32]


def verify(user_id, lang: str, text: str, sig: str) -> bool:
    return hmac.compare_digest(sign(user_id, lang, text), sig or "")


def speech_for(text: str, lang: str, user_id, *, whole: bool = False) -> list[dict]:
    """Neva's reply as signed clips the app may ask /neva/speak to say.

    `whole` makes it one clip. Spoken replies are one to three sentences, and
    as separate clips each one waited for its own synthesis: the first test
    on a phone (2026-10-27) had up to 6 s of silence between sentences.
    """
    spoken = speakable(text)
    if not spoken:
        return []
    clips = [spoken] if whole else chunks(spoken)
    return [{"text": c, "lang": lang, "sig": sign(user_id, lang, c)} for c in clips]


# ── Making the audio ────────────────────────────────────────────────────────

def chirp_locale(lang: str) -> str:
    """The Chirp 3 HD locale for a language code, or "" when Chirp has none."""
    code = (lang or "").strip().lower().replace("_", "-")
    if not code:
        return ""
    return _CHIRP_REGIONAL.get(code) or _CHIRP_LOCALES.get(code.split("-")[0], "")


def _seconds(audio: bytes, mime: str) -> float:
    if mime == "audio/mpeg":
        return len(audio) / 4000.0  # Cloud TTS MP3 is 32 kbps
    try:
        with wave.open(io.BytesIO(audio)) as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return len(audio) / 48000.0  # 24 kHz 16-bit mono


def _cache_name(engine: str, text: str) -> str:
    return hashlib.sha256(f"{engine}|{VOICE}|{text}".encode()).hexdigest()[:40]


def _cache_read(name: str) -> Optional[tuple[bytes, str]]:
    for mime, ext in _MIME_EXT.items():
        path = _CACHE_DIR / f"{name}.{ext}"
        try:
            if path.stat().st_size > 0:
                path.touch()  # age is last use, so pruning drops the least used
                return path.read_bytes(), mime
        except OSError:
            continue
    return None


def _cache_write(name: str, audio: bytes, mime: str) -> None:
    global _writes
    try:
        _CACHE_DIR.mkdir(parents=True, exist_ok=True)
        path = _CACHE_DIR / f"{name}.{_MIME_EXT[mime]}"
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(audio)
        tmp.replace(path)
    except OSError as e:
        logger.warning("neva_voice: clip not cached: %s", e)
        return
    _writes += 1
    if _writes % _PRUNE_EVERY == 0:
        _prune()


def _prune() -> None:
    """Drop clips unused for 30 days, then the least used past 500 MB."""
    try:
        files = [(p, p.stat()) for p in _CACHE_DIR.iterdir() if p.is_file()]
    except OSError:
        return
    files.sort(key=lambda f: f[1].st_mtime)
    cutoff = time.time() - _CACHE_MAX_AGE_S
    total = sum(st.st_size for _, st in files)
    for path, st in files:
        if st.st_mtime >= cutoff and total <= _CACHE_MAX_BYTES:
            break
        try:
            path.unlink()
            total -= st.st_size
        except OSError:
            pass


async def _chirp(text: str, locale: str, key: str) -> Optional[tuple[bytes, str]]:
    """MP3 from Cloud TTS Chirp 3 HD, or None so Gemini can speak instead."""
    body = {
        "input": {"text": text},
        "voice": {"languageCode": locale, "name": f"{locale}-Chirp3-HD-{VOICE}"},
        "audioConfig": {"audioEncoding": "MP3"},
    }
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT_S) as client:
            async with telemetry.track(
                "google_cloud", "neva_tts:chirp3_hd", sku="cloud_tts_chirp3_hd",
            ) as t:
                resp = await client.post(
                    _CLOUD_TTS_URL, json=body,
                    headers={"Content-Type": "application/json", "x-goog-api-key": key},
                )
                t.upstream(resp)
                if resp.status_code == 200:
                    # Billed per character; the SKU's per-1k rate is per 1k characters.
                    t.tokens(prompt=len(text))
    except httpx.HTTPError as e:
        logger.warning("Neva voice: Chirp 3 HD failed for %s: %s", locale, e)
        return None
    if resp.status_code != 200:
        logger.warning("Neva voice: Chirp 3 HD returned %s for %s: %s",
                       resp.status_code, locale, resp.text[:200])
        return None
    try:
        data = resp.json().get("audioContent")
        return (base64.b64decode(data), "audio/mpeg") if data else None
    except (ValueError, TypeError):
        return None


def _interaction_audio(data: dict) -> Optional[bytes]:
    for step in data.get("steps") or []:
        if not isinstance(step, dict) or step.get("type") != "model_output":
            continue
        for part in step.get("content") or []:
            if isinstance(part, dict) and part.get("type") == "audio" and part.get("data"):
                return base64.b64decode(part["data"])
    return None


async def _gemini_tts(text: str, api_key: str) -> tuple[bytes, str]:
    """WAV from Gemini 3.8 TTS, which detects the language itself."""
    body = {
        "model": "",
        "input": [{"type": "user_input", "content": [{
            "type": "text",
            "text": text,
            "annotations": [{"type": "speech_metadata", "style": _GEMINI_STYLE}],
        }]}],
        "response_format": {"type": "audio"},
        "generation_config": {"speech_config": [{"voice": VOICE}]},
    }
    last_status = None
    async with httpx.AsyncClient(timeout=_TIMEOUT_S) as client:
        for model, sku in _GEMINI_TTS_MODELS:
            body["model"] = model
            try:
                async with telemetry.track("gemini", f"neva_tts:{model}", sku=sku) as t:
                    resp = await client.post(
                        f"{_GEMINI_URL}/interactions", json=body,
                        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
                    )
                    t.upstream(resp)
                    if resp.status_code == 200:
                        # The Interactions API names its counts differently
                        # from generateContent, which `upstream` reads.
                        usage = resp.json().get("usage") or {}
                        t.tokens(prompt=usage.get("total_input_tokens"),
                                 completion=usage.get("total_output_tokens"))
            except httpx.HTTPError as e:
                logger.warning("Neva voice: %s failed: %s", model, e)
                continue
            if resp.status_code == 200:
                audio = _interaction_audio(resp.json())
                if audio:
                    return audio, "audio/wav"
                last_status = "no audio"
                continue
            last_status = resp.status_code
            # A bad key or an exhausted quota will not improve on the next model.
            if resp.status_code in (400, 401, 403, 429):
                break
    raise VoiceUnavailable(f"Gemini TTS returned {last_status}")


async def speaks_fast(lang: str) -> bool:
    """True when Chirp will say a reply in `lang`: about a second, not Gemini's 4-6 s."""
    cfg = await _load_config()
    return bool(cfg["enabled"] and cfg["tts_key"] and chirp_locale(lang))


async def synthesize(
    text: str, lang: str, *, user_id, api_key: str, fast_only: bool = False,
) -> tuple[bytes, str]:
    """Audio for one signed clip, as (bytes, MIME type).

    Raises VoiceBlocked past the allowance or with voice off, VoiceUnavailable
    when no engine answered. A cached clip is served even past the allowance:
    it costs nothing. `fast_only` gives up rather than wait for Gemini when
    Chirp fails, for a caller that is holding the reply's text back meanwhile.
    """
    cfg = await _load_config()
    if not cfg["enabled"]:
        raise VoiceBlocked("voice_off")
    locale = chirp_locale(lang) if cfg["tts_key"] else ""
    name = _cache_name(f"chirp3hd:{locale}" if locale else "gemini", text)

    cached = await asyncio.to_thread(_cache_read, name)
    if cached is not None:
        async with telemetry.track("internal", "neva_tts", cache_key=name) as t:
            t.hit("disk")
        return cached

    await check(user_id)
    made = await _chirp(text, locale, cfg["tts_key"]) if locale else None
    if made is None:
        if fast_only:
            raise VoiceUnavailable("Chirp gave no audio")
        if not api_key:
            raise VoiceUnavailable("no TTS engine configured")
        made = await _gemini_tts(text, api_key)
    audio, mime = made
    await _add_seconds(user_id, _seconds(audio, mime))
    await asyncio.to_thread(_cache_write, name, audio, mime)
    return audio, mime
