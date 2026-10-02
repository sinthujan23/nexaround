"""Neva answers "where is…" questions with real places, which the app maps.

Client request, 2026-10-01: "Can we make it respond with map integrated when
asking help for location?" The reported reply to "is there a money exchange
near me?" (Al Danah, Abu Dhabi) named two chains from memory with no address
or distance. Google's nearest were LuLu Exchange at 337 m and Al Ansari
Exchange (Electra Branch) at 357 m.
"""
import asyncio
from datetime import datetime, timezone

import pytest

from app.api.v1.neva import NevaChatResponse
from app.schemas.place import PlaceResponse, PlacesNearbyResponse
from app.services import neva_service

AL_DANAH = (24.4870, 54.3660)


def _place(name, metres, rating=4.0):
    return PlaceResponse(
        id=name.lower().replace(" ", "-"), name=name, latitude=AL_DANAH[0] + metres / 111_000,
        longitude=AL_DANAH[1], rating=rating, review_count=100, distance_m=metres,
        address=f"{name}, Al Danah, Abu Dhabi", created_at=datetime.now(timezone.utc),
    )


EXCHANGES = [
    _place("Al Ansari Exchange, Electra Branch", 357, 4.1),
    _place("LuLu Exchange", 337),
    _place("AL JAZIRA EXCHANGE MADINAT ZAYED", 512, 4.9),
    _place("Al Dahab Exchange", 544, 4.6),
    _place("LuLu Exchange, Hamdan Al Yousuf Centre", 554),
    _place("Index Exchange LLC", 556, 3.8),
    _place("Far Away Exchange", 7400),
]


def _reply(text=None, call=None):
    parts = []
    if call:
        parts.append({"functionCall": {"name": "find_places", "args": {"query": call}}})
    if text:
        parts.append({"text": text})
    return {"candidates": [{"content": {"role": "model", "parts": parts}}]}


@pytest.fixture
def scripted(monkeypatch):
    """Gemini answers from a script; Places from a table; every call recorded."""
    calls = {"gemini": [], "search": []}
    script: list[dict] = []
    results: dict[int, list] = {}

    async def _generate(body, api_key, operation):
        calls["gemini"].append({"body": body, "operation": operation})
        return script.pop(0)

    async def _search(*, query, latitude, longitude, radius_m=None, near_me=False):
        calls["search"].append({"query": query, "radius_m": radius_m, "near_me": near_me})
        return PlacesNearbyResponse(places=list(results.get(int(radius_m), [])))

    async def _allowed(user_id=None):
        return True, None

    monkeypatch.setattr(neva_service, "_generate", _generate)
    monkeypatch.setattr(neva_service.places_service, "search", _search)
    monkeypatch.setattr(neva_service.spend_guard, "allowed", _allowed)
    return calls, script, results


def _chat(message="is there an money exchange near me?", **kw):
    args = dict(api_key="k", latitude=AL_DANAH[0], longitude=AL_DANAH[1], area="Al Danah")
    args.update(kw)
    return asyncio.run(neva_service.chat(message, **args))


def test_an_ordinary_question_is_one_call_and_no_map(scripted):
    calls, script, _ = scripted
    script.append(_reply(text="Since you're around Al Danah, try the Corniche at sunset ✨"))
    reply = _chat("what should I do this evening?")
    assert reply == {
        "text": "Since you're around Al Danah, try the Corniche at sunset ✨",
        "places": [], "query": "", "radius_m": 0,
    }
    assert len(calls["gemini"]) == 1 and calls["search"] == []
    body = calls["gemini"][0]["body"]
    assert body["tool_config"]["function_calling_config"]["mode"] == "AUTO"
    assert "Al Danah" in body["contents"][0]["parts"][0]["text"]


def test_the_reported_question_comes_back_with_the_nearest_real_places(scripted):
    calls, script, results = scripted
    results[3000] = EXCHANGES
    script.append(_reply(call="money exchange"))
    script.append(_reply(text="The closest is **LuLu Exchange**, just 337 m away. I've pinned them below 🗺️"))
    reply = _chat()

    assert calls["search"] == [{"query": "money exchange", "radius_m": 3000, "near_me": True}]
    assert [p.name for p in reply["places"]] == [
        "LuLu Exchange", "Al Ansari Exchange, Electra Branch", "AL JAZIRA EXCHANGE MADINAT ZAYED",
        "Al Dahab Exchange", "LuLu Exchange, Hamdan Al Yousuf Centre",
    ], "nearest first, five at most, the 7.4 km one dropped"
    assert reply["query"] == "money exchange" and reply["radius_m"] == 3000
    assert reply["text"].startswith("The closest is **LuLu Exchange**")

    second = calls["gemini"][1]["body"]
    assert second["tool_config"]["function_calling_config"]["mode"] == "NONE"
    model_turn, result_turn = second["contents"][1], second["contents"][2]
    assert model_turn["parts"][0]["functionCall"]["args"] == {"query": "money exchange"}
    found = result_turn["parts"][0]["functionResponse"]["response"]["places"]
    assert found[0] == {
        "pin": 1, "name": "LuLu Exchange", "distance": "337 m", "rating": 4.0,
        "reviews": 100, "address": "LuLu Exchange, Al Danah, Abu Dhabi",
    }


def test_nothing_close_widens_the_search_once(scripted):
    calls, script, results = scripted
    results[10000] = [_place("Airport Exchange", 8200)]
    script.extend([_reply(call="money exchange"), _reply(text="The nearest is 8.2 km away.")])
    reply = _chat()
    assert [c["radius_m"] for c in calls["search"]] == [3000, 10000]
    assert [p.name for p in reply["places"]] == ["Airport Exchange"]
    response = calls["gemini"][1]["body"]["contents"][2]["parts"][0]["functionResponse"]["response"]
    assert response["places"][0]["distance"] == "8.2 km"
    assert response["searched_within"] == "10.0 km"


def test_nothing_anywhere_is_said_honestly(scripted):
    calls, script, _ = scripted
    script.extend([_reply(call="camel milk shop"), _reply(text="I couldn't find one nearby.")])
    reply = _chat("camel milk shop near me?")
    assert reply["places"] == []
    response = calls["gemini"][1]["body"]["contents"][2]["parts"][0]["functionResponse"]["response"]
    assert response["note"] == "Nothing of this kind was found near the user."


def test_without_a_location_nothing_is_searched(scripted):
    calls, script, _ = scripted
    script.extend([_reply(call="pharmacy"), _reply(text="Turn on location and I'll find one 🌸")])
    reply = _chat("nearest pharmacy?", latitude=None, longitude=None)
    assert calls["search"] == [] and reply["places"] == []
    response = calls["gemini"][1]["body"]["contents"][2]["parts"][0]["functionResponse"]["response"]
    assert response == {"error": "The user's location is unknown."}


def test_a_spent_budget_skips_the_paid_search(scripted, monkeypatch):
    calls, script, results = scripted
    results[3000] = EXCHANGES

    async def _blocked(user_id=None):
        return False, "daily cap"

    monkeypatch.setattr(neva_service.spend_guard, "allowed", _blocked)
    script.extend([_reply(call="money exchange"), _reply(text="I can't search right now.")])
    assert _chat()["places"] == [] and calls["search"] == []


def test_the_reply_fits_the_endpoint_s_response_model(scripted):
    _, script, results = scripted
    results[3000] = EXCHANGES[:2]
    script.extend([_reply(call="money exchange"), _reply(text="Two close by!")])
    out = NevaChatResponse(**_chat()).model_dump()
    assert [p["name"] for p in out["places"]] == ["LuLu Exchange", "Al Ansari Exchange, Electra Branch"]
    assert out["places"][0]["distance_m"] == 337


def test_the_prompt_forbids_answering_place_questions_from_memory():
    prompt = neva_service.NEVA_SYSTEM_PROMPT
    assert "ALWAYS call the find_places tool" in prompt
    assert "Never invent a place" in prompt


def test_conversation_history_is_passed_to_gemini(scripted):
    calls, script, _ = scripted
    script.append(_reply(text="The second one is open until 10 PM! ✨"))
    history = [
        {"role": "user", "text": "What are some good coffee spots near me?"},
        {"role": "model", "text": "Try **Café Arabica** or **Brew Bar**! ☕"},
    ]
    reply = _chat("Are they open late?", history=history)
    assert reply["text"] == "The second one is open until 10 PM! ✨"
    assert len(calls["gemini"]) == 1
    contents = calls["gemini"][0]["body"]["contents"]
    assert len(contents) == 3
    assert contents[0] == {"role": "user", "parts": [{"text": "What are some good coffee spots near me?"}]}
    assert contents[1] == {"role": "model", "parts": [{"text": "Try **Café Arabica** or **Brew Bar**! ☕"}]}
    assert "Are they open late?" in contents[2]["parts"][0]["text"]


def test_system_prompt_includes_app_features_and_actions():
    prompt = neva_service.NEVA_SYSTEM_PROMPT
    assert "AR Camera & Scanner" in prompt
    assert "Odyssey AI Trip Planner" in prompt
    assert "Interactive Food Radar" in prompt
    assert "Interactive Living Map" in prompt
    assert "Travel Budget Tracker" in prompt
    assert "[action:ar|Open AR Scanner]" in prompt

