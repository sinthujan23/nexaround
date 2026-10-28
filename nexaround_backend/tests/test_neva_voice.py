"""Neva voice chat: spoken questions in, short spoken replies out.

Client request, 2026-10-27. Gemini's own TTS measured 4-6 s to the first
sound from this server, so Neva speaks through Cloud TTS Chirp 3 HD, with
Gemini TTS only for languages Chirp has no voice in. Cost is held by short
replies, a disk cache, signed clips and a daily allowance per user.
"""
import asyncio
import base64
import copy
import io
import uuid
import wave
from types import SimpleNamespace

import httpx
import pytest
from fastapi import HTTPException, UploadFile

from app.api.v1 import neva as neva_api
from app.services import neva_service, neva_voice, telemetry

USER = uuid.UUID("11111111-2222-3333-4444-555555555555")
OTHER = uuid.UUID("99999999-2222-3333-4444-555555555555")


def _wav(seconds=1.0, rate=16000) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00" * int(seconds * rate))
    return buf.getvalue()


def _reply(text):
    return {"candidates": [{"content": {"role": "model", "parts": [{"text": text}]}}]}


@pytest.fixture
def voice_config(monkeypatch, tmp_path):
    """Voice on, a Cloud TTS key, an empty cache, nothing spoken yet today."""
    cfg = {"enabled": True, "daily_seconds": 600, "tts_key": "cloud-key"}
    spent = {"seconds": 0.0}

    async def _load(force=False):
        return cfg

    async def _seconds_today(user_id):
        return spent["seconds"]

    async def _add(user_id, seconds):
        spent["seconds"] += seconds

    async def _allowed(user_id=None):
        return True, None

    monkeypatch.setattr(neva_voice, "_load_config", _load)
    monkeypatch.setattr(neva_voice, "seconds_today", _seconds_today)
    monkeypatch.setattr(neva_voice, "_add_seconds", _add)
    monkeypatch.setattr(neva_voice.spend_guard, "allowed", _allowed)
    monkeypatch.setattr(neva_voice, "_CACHE_DIR", tmp_path / "voice")
    return cfg, spent


@pytest.fixture
def engines(monkeypatch):
    """Both TTS engines scripted; every call recorded."""
    calls = {"chirp": [], "gemini": []}
    chirp_result = {"value": (b"ID3mp3" + b"\x00" * 3994, "audio/mpeg")}

    async def _chirp(text, locale, key):
        calls["chirp"].append((text, locale, key))
        return chirp_result["value"]

    async def _gemini(text, api_key):
        calls["gemini"].append(text)
        return _wav(2.0, 24000), "audio/wav"

    monkeypatch.setattr(neva_voice, "_chirp", _chirp)
    monkeypatch.setattr(neva_voice, "_gemini_tts", _gemini)
    return calls, chirp_result


def _speak(text, lang="en", user=USER):
    return asyncio.run(neva_voice.synthesize(text, lang, user_id=user, api_key="gem-key"))


# ── What gets spoken ────────────────────────────────────────────────────────

def test_speakable_drops_chips_links_emoji_and_markdown():
    reply = (
        "Since you're around Colombo, here are two ideas ✨\n"
        "* **Galle Face Green** — sunset snacks by the sea 🌅\n"
        "* **Gangaramaya Temple** — see https://example.com/temple\n"
        "[action:map|Explore Living Map]"
    )
    assert neva_voice.speakable(reply) == (
        "Since you're around Colombo, here are two ideas. "
        "Galle Face Green — sunset snacks by the sea. "
        "Gangaramaya Temple — see."
    )


def test_speakable_caps_a_long_reply_at_a_sentence():
    text = " ".join(f"Sentence number {i} is here." for i in range(60))
    spoken = neva_voice.speakable(text)
    assert len(spoken) <= neva_voice.MAX_SPOKEN_CHARS
    assert spoken.endswith(".")


def test_the_first_clip_is_short_so_playback_starts_early():
    text = ("Sure! The closest pharmacy is Healthguard, about 300 metres away. "
            "Another one is Union Chemists, a little further at 650 metres. "
            "I've pinned both on the map below so you can pick.")
    clips = neva_voice.chunks(text)
    assert clips[0] == "Sure! The closest pharmacy is Healthguard, about 300 metres away."
    assert len(clips) == 2
    assert all(len(c) <= 250 for c in clips)
    assert " ".join(clips) == text


def test_chinese_sentences_split_without_spaces():
    clips = neva_voice.chunks("你好！最近的药店在三百米外。我已经在地图上标出来了。")
    assert clips[0].endswith("。")


def test_a_clip_is_only_spoken_for_the_user_it_was_signed_for():
    sig = neva_voice.sign(USER, "en", "Hello there!")
    assert neva_voice.verify(USER, "en", "Hello there!", sig)
    assert not neva_voice.verify(USER, "en", "Say something else entirely", sig)
    assert not neva_voice.verify(OTHER, "en", "Hello there!", sig)
    assert not neva_voice.verify(USER, "fr", "Hello there!", sig)


def test_chirp_locales():
    assert neva_voice.chirp_locale("en") == "en-US"
    assert neva_voice.chirp_locale("en-GB") == "en-GB"
    assert neva_voice.chirp_locale("ar") == "ar-XA"
    assert neva_voice.chirp_locale("ml") == "ml-IN"
    assert neva_voice.chirp_locale("zh-CN") == "cmn-CN"
    assert neva_voice.chirp_locale("si") == "", "no Chirp voice for Sinhala"
    assert neva_voice.chirp_locale("") == ""


def test_recordings_are_recognised_by_their_bytes():
    assert neva_voice.clip_mime(_wav()) == "audio/wav"
    assert neva_voice.clip_mime(b"fLaC....") == "audio/flac"
    assert neva_voice.clip_mime(b"<html>not audio</html>") is None
    assert round(neva_voice.clip_seconds(_wav(2.5), "audio/wav"), 2) == 2.5


# ── Making the audio ────────────────────────────────────────────────────────

def test_chirp_speaks_a_covered_language(voice_config, engines):
    calls, _ = engines
    audio, mime = _speak("Hello there!", "en")
    assert mime == "audio/mpeg"
    assert calls["chirp"] == [("Hello there!", "en-US", "cloud-key")]
    assert calls["gemini"] == []


def test_gemini_speaks_a_language_chirp_has_no_voice_for(voice_config, engines):
    calls, _ = engines
    _audio, mime = _speak("ආයුබෝවන්!", "si")
    assert mime == "audio/wav"
    assert calls["chirp"] == [] and calls["gemini"] == ["ආයුබෝවන්!"]


def test_gemini_covers_a_chirp_failure(voice_config, engines):
    calls, chirp_result = engines
    chirp_result["value"] = None
    _audio, mime = _speak("Hello there!", "en")
    assert mime == "audio/wav" and len(calls["chirp"]) == 1 and len(calls["gemini"]) == 1


def test_without_a_cloud_key_gemini_speaks(voice_config, engines):
    cfg, _ = voice_config
    cfg["tts_key"] = ""
    calls, _ = engines
    _speak("Hello there!", "en")
    assert calls["chirp"] == [] and calls["gemini"] == ["Hello there!"]


def test_a_clip_is_bought_once_then_served_from_disk(voice_config, engines):
    calls, _ = engines
    first = _speak("Hello there!", "en")
    second = _speak("Hello there!", "en", user=OTHER)
    assert first == second
    assert len(calls["chirp"]) == 1


def test_spoken_seconds_count_toward_the_allowance(voice_config, engines):
    _, spent = voice_config
    _speak("Hello there!", "en")  # 4,000 bytes of 32 kbps MP3
    assert spent["seconds"] == pytest.approx(1.0)


def test_past_the_allowance_no_new_speech_is_made(voice_config, engines):
    _, spent = voice_config
    calls, _ = engines
    _speak("Already cached.", "en")
    spent["seconds"] = 600
    with pytest.raises(neva_voice.VoiceBlocked) as blocked:
        _speak("Something new.", "en")
    assert blocked.value.reason == "voice_quota"
    # A clip already on disk costs nothing, so it still plays.
    assert _speak("Already cached.", "en")[1] == "audio/mpeg"
    assert len(calls["chirp"]) == 1


def test_switched_off_nothing_is_spoken(voice_config, engines):
    cfg, _ = voice_config
    cfg["enabled"] = False
    with pytest.raises(neva_voice.VoiceBlocked) as blocked:
        _speak("Hello there!", "en")
    assert blocked.value.reason == "voice_off"


def test_a_spent_api_budget_stops_speech(voice_config, engines, monkeypatch):
    async def _blocked(user_id=None):
        return False, "daily cap"

    monkeypatch.setattr(neva_voice.spend_guard, "allowed", _blocked)
    with pytest.raises(neva_voice.VoiceBlocked):
        _speak("Hello there!", "en")


def test_chirp_is_recorded_with_its_character_count(monkeypatch):
    rows = []

    async def _capture(row):
        rows.append(row)

    async def _no_rates(force=False):
        return {}

    def _handler(request):
        assert request.headers["x-goog-api-key"] == "cloud-key"
        assert b"en-US-Chirp3-HD-Sulafat" in request.content
        return httpx.Response(200, json={"audioContent": "SUQzbXAz"})

    real_client = httpx.AsyncClient
    monkeypatch.setattr(neva_voice.httpx, "AsyncClient",
                        lambda **kw: real_client(transport=httpx.MockTransport(_handler), **kw))
    monkeypatch.setattr(telemetry, "_emit", _capture)
    monkeypatch.setattr(telemetry, "_load_rates", _no_rates)
    audio, mime = asyncio.run(neva_voice._chirp("Hello there!", "en-US", "cloud-key"))
    assert (audio, mime) == (b"ID3mp3", "audio/mpeg")
    assert rows[0]["sku"] == "cloud_tts_chirp3_hd"
    assert rows[0]["prompt_tokens"] == len("Hello there!")


def test_gemini_tts_usage_is_read_from_the_interactions_reply(monkeypatch):
    rows = []

    async def _capture(row):
        rows.append(row)

    async def _no_rates(force=False):
        return {}

    def _handler(request):
        return httpx.Response(200, json={
            "status": "completed",
            "usage": {"total_input_tokens": 24, "total_output_tokens": 177},
            "steps": [{"type": "model_output", "content": [
                {"type": "audio", "mime_type": "audio/wav", "data": "UklGRg=="},
            ]}],
        })

    real_client = httpx.AsyncClient
    monkeypatch.setattr(neva_voice.httpx, "AsyncClient",
                        lambda **kw: real_client(transport=httpx.MockTransport(_handler), **kw))
    monkeypatch.setattr(telemetry, "_emit", _capture)
    monkeypatch.setattr(telemetry, "_load_rates", _no_rates)
    audio, mime = asyncio.run(neva_voice._gemini_tts("Hello", "gem-key"))
    assert (audio, mime) == (b"RIFF", "audio/wav")
    assert (rows[0]["sku"], rows[0]["prompt_tokens"], rows[0]["completion_tokens"]) == (
        "gemini_tts_lite", 24, 177)


# ── Neva's reply in voice mode ──────────────────────────────────────────────

@pytest.fixture
def scripted(monkeypatch):
    """Gemini from a script. Bodies are copied: chat() edits its body between calls."""
    calls = []
    script = []

    async def _generate(body, api_key, operation, models=None):
        calls.append({"body": copy.deepcopy(body), "operation": operation, "models": models})
        return script.pop(0)

    async def _find_places(query, latitude, longitude, user_id=None):
        return [], 3000

    monkeypatch.setattr(neva_service, "_generate", _generate)
    monkeypatch.setattr(neva_service, "find_places", _find_places)
    return calls, script


def _call(query):
    return {"candidates": [{"content": {"role": "model", "parts": [
        {"functionCall": {"name": "find_places", "args": {"query": query}}}]}}]}


def _voice_chat(transcript, **kw):
    return asyncio.run(neva_service.chat(
        "", api_key="k", latitude=6.9, longitude=79.85, area="Colombo",
        audio=(_wav(), "audio/wav"), voice=True, transcript=transcript, **kw,
    ))


def test_voice_rules_keep_the_place_search():
    # The first wording made Neva skip find_places for spoken "near me"
    # questions and name pharmacies from memory.
    assert "call find_places first" in neva_service.NEVA_VOICE_RULES
    assert "only ever name places it returned" in neva_service.NEVA_VOICE_RULES


def test_a_spoken_near_me_answer_reads_the_transcript_on_flash_lite(scripted):
    calls, script = scripted
    script.extend([_call("pharmacy"), _reply("Nothing close by, sorry. [lang:en]")])

    async def _transcript():
        return "Is there a pharmacy near me?"

    reply = _voice_chat(_transcript())
    assert reply["text"] == "Nothing close by, sorry." and reply["lang"] == "en"
    first, second = calls
    assert "inline_data" in first["body"]["contents"][-1]["parts"][1]
    assert first["models"] is None or first["models"] == neva_service._MODELS
    asked = second["body"]["contents"][0]["parts"]
    assert len(asked) == 1 and "User Question (spoken): Is there a pharmacy near me?" in asked[0]["text"]
    assert second["operation"] == "neva_voice_places"
    assert second["models"] == neva_service._VOICE_PLACES_MODELS


def test_a_late_transcript_leaves_the_recording_in(scripted, monkeypatch):
    calls, script = scripted
    script.extend([_call("pharmacy"), _reply("Nothing close by. [lang:en]")])
    monkeypatch.setattr(neva_service, "_TRANSCRIPT_WAIT_S", 0.01)

    async def _slow():
        await asyncio.sleep(0.2)
        return "too late"

    _voice_chat(_slow())
    assert "inline_data" in calls[1]["body"]["contents"][0]["parts"][1]


def test_a_typed_near_me_answer_stays_on_flash(scripted):
    calls, script = scripted
    script.extend([_call("pharmacy"), _reply("Here are the closest. [lang:en]")])
    asyncio.run(neva_service.chat("pharmacy near me?", api_key="k", latitude=6.9, longitude=79.85))
    assert calls[1]["models"] == neva_service._MODELS
    assert calls[1]["operation"] == "neva_chat_places"


def test_the_language_tag_is_stripped_and_returned(scripted):
    calls, script = scripted
    script.append(_reply("Bonjour ! La pharmacie la plus proche est à 300 mètres.\n[lang:fr]"))
    reply = asyncio.run(neva_service.chat("pharmacie ?", api_key="k"))
    assert reply["text"] == "Bonjour ! La pharmacie la plus proche est à 300 mètres."
    assert reply["lang"] == "fr"
    system = calls[0]["body"]["system_instruction"]["parts"][0]["text"]
    assert system.startswith(neva_service.NEVA_SYSTEM_PROMPT)
    assert "[lang:en]" in system
    assert neva_service.NEVA_VOICE_RULES not in system, "typed chat keeps its full replies"


def test_a_recording_is_heard_directly_with_the_voice_rules(scripted):
    calls, script = scripted
    script.append(_reply("Sure, there's one 300 metres away. [lang:en]"))
    clip = _wav()
    reply = asyncio.run(neva_service.chat(
        "", api_key="k", latitude=6.9, longitude=79.85, area="Colombo",
        audio=(clip, "audio/wav"), voice=True,
    ))
    assert reply["text"] == "Sure, there's one 300 metres away." and reply["lang"] == "en"
    body = calls[0]["body"]
    assert calls[0]["operation"] == "neva_voice"
    assert body["generationConfig"]["maxOutputTokens"] == 300
    assert body["system_instruction"]["parts"][0]["text"].endswith(neva_service.NEVA_VOICE_RULES)
    question = body["contents"][-1]["parts"]
    assert "Colombo" in question[0]["text"] and "voice message" in question[0]["text"]
    assert question[1]["inline_data"]["mime_type"] == "audio/wav"


# ── The endpoints ───────────────────────────────────────────────────────────

@pytest.fixture
def endpoint(monkeypatch, voice_config, engines):
    heard = {"value": "Is there a pharmacy near me?"}
    answer = {"value": {"text": "Yes, one is 300 metres away.", "places": [], "query": "",
                        "radius_m": 0, "lang": "en"}}
    seen = {}

    async def _key(db):
        return "gem-key"

    async def _transcribe(clip, mime, api_key):
        if isinstance(heard["value"], Exception):
            raise heard["value"]
        return heard["value"]

    async def _chat(message, **kw):
        seen.update(kw)
        return answer["value"]

    monkeypatch.setattr(neva_api, "_gemini_key", _key)
    monkeypatch.setattr(neva_voice, "transcribe", _transcribe)
    monkeypatch.setattr(neva_service, "chat", _chat)
    return heard, answer, seen


def _voice_turn(clip=None, history=None):
    upload = UploadFile(filename="q.wav", file=io.BytesIO(clip if clip is not None else _wav()))
    return asyncio.run(neva_api.neva_voice_turn(
        audio=upload, latitude=6.9, longitude=79.85, area="Colombo", history=history,
        db=None, current_user=SimpleNamespace(id=USER),
    ))


def test_a_spoken_question_comes_back_with_its_transcript_and_signed_speech(endpoint):
    _, _, seen = endpoint
    out = _voice_turn(history='[{"role": "user", "text": "hi"}, {"role": "bogus", "text": "x"}]')
    assert out.transcript == "Is there a pharmacy near me?"
    assert out.text == "Yes, one is 300 metres away."
    assert [c.text for c in out.speech] == ["Yes, one is 300 metres away."]
    assert neva_voice.verify(USER, "en", out.speech[0].text, out.speech[0].sig)
    assert out.voice_paused is False
    assert seen["voice"] is True and seen["audio"][1] == "audio/wav"
    assert seen["history"] == [{"role": "user", "text": "hi"}], "malformed turns dropped"


def test_the_fast_voice_comes_back_with_the_text(endpoint, engines):
    calls, _ = engines
    out = _voice_turn()
    assert len(out.speech) == 1, "one clip: no gaps between sentences"
    assert out.audio_mime == "audio/mpeg"
    assert base64.b64decode(out.audio).startswith(b"ID3mp3")
    assert calls["chirp"] == [("Yes, one is 300 metres away.", "en-US", "cloud-key")]
    # Kept on disk, so the app's later /neva/speak for the same clip is free.
    assert _speak("Yes, one is 300 metres away.", "en")[1] == "audio/mpeg"
    assert len(calls["chirp"]) == 1


def test_without_the_fast_voice_the_app_fetches_the_clip(endpoint, engines, voice_config):
    cfg, _ = voice_config
    cfg["tts_key"] = ""
    calls, _ = engines
    out = _voice_turn()
    assert out.audio == "" and len(out.speech) == 1
    assert calls["gemini"] == [], "Gemini's 4-6 s would hold the text back"


def test_a_chirp_failure_does_not_hold_the_text_for_gemini(endpoint, engines):
    calls, chirp_result = engines
    chirp_result["value"] = None
    out = _voice_turn()
    assert out.audio == "" and len(out.speech) == 1
    assert calls["gemini"] == []


def test_the_whole_reply_is_one_clip():
    text = "Sure! The closest one is 300 metres away. I've pinned it on the map below."
    clips = neva_voice.speech_for(text, "en", USER, whole=True)
    assert [c["text"] for c in clips] == [text]
    assert len(neva_voice.speech_for(text, "en", USER)) == 2, "typed replies are still split"


def test_aac_recordings_are_recognised():
    assert neva_voice.clip_mime(b"\x00\x00\x00\x1cftypM4A \x00\x00\x00\x00") == "audio/aac"
    assert neva_voice.clip_mime(b"\xff\xf1\x50\x80\x00\x1f\xfc") == "audio/aac", "ADTS"
    assert neva_voice.clip_mime(b"\xff\xfb\x90\x64\x00") == "audio/mp3"


def test_an_aac_recording_reaches_neva_as_aac(endpoint):
    _, _, seen = endpoint
    _voice_turn(clip=b"\x00\x00\x00\x1cftypM4A " + b"\x00" * 4000)
    assert seen["audio"][1] == "audio/aac"


def test_an_oversized_compressed_recording_is_refused(endpoint):
    with pytest.raises(HTTPException) as err:
        _voice_turn(clip=b"\x00\x00\x00\x1cftypM4A " + b"\x00" * neva_voice.MAX_COMPRESSED_BYTES)
    assert err.value.status_code == 413


def test_silence_is_reported_not_answered(endpoint):
    heard, _, _ = endpoint
    heard["value"] = ""
    with pytest.raises(HTTPException) as err:
        _voice_turn()
    assert err.value.status_code == 422 and err.value.detail == "no_speech"


def test_a_failed_transcript_still_gets_an_answer(endpoint):
    heard, _, _ = endpoint
    heard["value"] = neva_voice.VoiceUnavailable("boom")
    out = _voice_turn()
    assert out.transcript == "" and out.text == "Yes, one is 300 metres away."


def test_past_the_allowance_neva_answers_in_text(endpoint, voice_config):
    _, spent = voice_config
    spent["seconds"] = 601
    out = _voice_turn()
    assert out.voice_paused is True and out.speech == []
    assert out.text == "Yes, one is 300 metres away."


def test_voice_switched_off_refuses_the_recording(endpoint, voice_config):
    cfg, _ = voice_config
    cfg["enabled"] = False
    with pytest.raises(HTTPException) as err:
        _voice_turn()
    assert err.value.status_code == 503 and err.value.detail == "voice_off"


def test_not_audio_is_refused(endpoint):
    with pytest.raises(HTTPException) as err:
        _voice_turn(clip=b"<html></html>")
    assert err.value.status_code == 415


def test_a_recording_over_thirty_seconds_is_refused(endpoint):
    with pytest.raises(HTTPException) as err:
        _voice_turn(clip=_wav(32))
    assert err.value.status_code == 413


def test_speak_refuses_text_it_did_not_sign(voice_config, engines, monkeypatch):
    async def _key(db):
        return "gem-key"

    monkeypatch.setattr(neva_api, "_gemini_key", _key)
    body = neva_api.SpeakRequest(text="Free TTS for everyone", lang="en", sig="0" * 32)
    with pytest.raises(HTTPException) as err:
        asyncio.run(neva_api.neva_speak(body, db=None, current_user=SimpleNamespace(id=USER)))
    assert err.value.status_code == 403

    good = neva_api.SpeakRequest(
        text="Hello there!", lang="en", sig=neva_voice.sign(USER, "en", "Hello there!"))
    resp = asyncio.run(neva_api.neva_speak(good, db=None, current_user=SimpleNamespace(id=USER)))
    assert resp.media_type == "audio/mpeg"
