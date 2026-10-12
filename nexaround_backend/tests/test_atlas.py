"""HelloSafe Atlas: travel insurance on trips abroad (user, 2026-10-12).

What these pin:
- requests are signed the v2 way, and only trips Atlas can price are asked;
- a trip into the Schengen area from outside it is priced both ways, and the
  plan keeps the Schengen quote only when Gemini says a visa is needed;
- the plan's button opens our signed tap URL, never an Atlas link: a tap makes
  that traveller's own session and tracked link (Atlas: one session per
  traveller), and falls back to HelloSafe's form when it cannot;
- the price is in the traveller's currency with the insurer beside it, and
  the plan claims nothing about cover;
- shadow records and changes nothing; off adds nothing.

The test container shares Redis with the live stack, so the provider cache and
breaker run on an in-memory dict here: fake quotes must never reach a plan.
"""
from __future__ import annotations

import asyncio
import json
import time
import urllib.parse

import httpx
import pytest

from app.core.config import settings
from app.services.providers import atlas, base, config, enrich

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)

QUOTES = {
    "ok": True,
    "sessionId": "qs_one_traveller",
    "offers": [
        {"id": 9002, "insurer": {"name": "Allianz Travel"}, "price": {"amount": 48.00, "currency": "USD"}},
        {"id": 9001, "insurer": {"name": "Chapka"}, "price": {"amount": 22.50, "currency": "USD"}},
        {"id": 9003, "insurer": {"name": "Unpriced"}, "price": {"amount": None, "currency": "USD"}},
    ],
}
TRACKED = "https://atlas.hellosafe.com/r/abc123?quote=q1"


@pytest.fixture(autouse=True)
def atlas_world(monkeypatch):
    """Atlas switched to live with a key, its HTTP mocked, its cache in memory."""
    store: dict[str, str] = {}

    async def _get(key):
        return store.get(key)

    async def _set(key, value, ttl=0):
        store[key] = value

    monkeypatch.setattr(base.place_cache_service, "get_raw", _get)
    monkeypatch.setattr(base.place_cache_service, "set_raw", _set)
    monkeypatch.setattr(base, "_open_until", {})

    state = {"calls": [], "quotes": QUOTES, "link_status": 201}

    def _handler(request: httpx.Request):
        body = json.loads(request.content or b"{}")
        state["calls"].append((request.url.path, body, dict(request.headers)))
        if request.url.path == atlas.QUOTES_PATH:
            return httpx.Response(200, json=state["quotes"])
        if request.url.path == atlas.LINKS_PATH:
            return httpx.Response(state["link_status"], json={"ok": True, "url": TRACKED})
        return httpx.Response(404)

    monkeypatch.setattr(base, "_new_client", lambda: httpx.AsyncClient(transport=httpx.MockTransport(_handler)))
    _switches(monkeypatch, atlas="live")

    async def _rate(code):
        return {"USD": 1.0, "INR": 80.0}.get(code)

    monkeypatch.setattr(enrich, "usd_rate", _rate)
    return state


def _switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.ATLAS_KEY_ID: "ak_test_k", config.ATLAS_SIGNING_SECRET: "sk_test_s"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


def _trip(**kw):
    args = dict(residence="LK", destination="TH", start_date="2026-11-10",
                end_date="2026-11-17", travelers=2, intent=atlas.TOURISM)
    args.update(kw)
    return atlas.trip(**args)


# ── Signing and the trip ─────────────────────────────────────────────────────

def test_requests_are_signed_the_v2_way():
    headers = atlas.sign_request("ak_test_sample", "sk_test_secret", "POST", atlas.QUOTES_PATH, '{"trip":{}}')
    assert headers["x-atlas-key-id"] == "ak_test_sample"
    assert headers["x-atlas-signature"].startswith("v2=") and len(headers["x-atlas-signature"]) == 67


def test_only_trips_atlas_can_price_are_asked():
    trip = _trip()
    assert trip["countryResidence"] == "LK" and trip["arrivalCountries"] == ["TH"]
    assert trip["currency"] == "USD" and len(trip["travellers"]) == 2
    assert _trip(destination="LK") is None                 # home is not abroad
    assert _trip(residence="Sri Lanka") is None            # codes only
    assert _trip(end_date="2026-11-01") is None            # home before leaving
    assert _trip(intent="annual") is None
    assert len(_trip(travelers=40)["travellers"]) == 10


@pytest.mark.parametrize("home, dest, intents", [
    ("LK", "FR", [atlas.TOURISM, atlas.SCHENGEN]),
    ("IN", "AD", [atlas.TOURISM, atlas.SCHENGEN]),   # entered through Schengen
    ("FR", "IT", [atlas.TOURISM]),                   # already inside it
    ("LK", "TH", [atlas.TOURISM]),
    ("LK", "GB", [atlas.TOURISM]),                   # not Schengen
])
def test_schengen_trips_are_priced_both_ways(home, dest, intents):
    assert atlas.intents_for(home, dest) == intents


@pytest.mark.parametrize("home, code", [
    ("Sri Lanka", "LK"), ("SRI LANKA", "LK"), ("lk", "LK"), ("United Arab Emirates", "AE"),
    ("", ""), ("Atlantis", ""),
])
def test_an_unknown_home_country_is_never_guessed(home, code):
    assert enrich._residence_code(home) == code


# ── The tap URL ──────────────────────────────────────────────────────────────

def test_the_tap_url_is_ours_and_signed():
    trip = _trip(intent=atlas.SCHENGEN, destination="FR")
    url = atlas.tap_url(trip)
    assert url.startswith(settings.PUBLIC_BASE_URL.rstrip("/") + atlas.TAP_PATH + "?t=")
    assert atlas.is_atlas_link(url)
    token = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["t"][0]
    assert atlas.trip_from_token(token) == trip

    payload, sig = token.split(".")
    other = atlas.tap_url(_trip(travelers=9)).split("t=")[1].split(".")[0]
    assert atlas.trip_from_token(f"{other}.{sig}") is None      # someone else's trip
    assert atlas.trip_from_token(f"{payload}.{'0' * 32}") is None
    assert atlas.trip_from_token("") is None


def test_links_are_recognised_and_others_are_not():
    assert atlas.is_atlas_link(TRACKED)
    assert atlas.is_atlas_link("https://hellosafe.com/travel-insurance/app?x=1")
    assert not atlas.is_atlas_link("https://tp.media/r?p=8310")
    assert not atlas.is_atlas_link("https://google.com")


# ── Atlas calls ──────────────────────────────────────────────────────────────

def test_the_quote_is_the_cheapest_priced_offer_and_kept_25_minutes(atlas_world):
    trip = _trip()
    first = asyncio.run(atlas.quote(trip))
    assert first == {"session_id": "qs_one_traveller", "offer_id": 9001, "price": 22.5,
                     "currency": "USD", "insurer": "Chapka", "offers": 2}
    assert asyncio.run(atlas.quote(trip)) == first
    assert len(atlas_world["calls"]) == 1
    asyncio.run(atlas.quote(trip, traveller="someone-else"))
    assert len(atlas_world["calls"]) == 2                       # a tap's session is its own
    assert atlas.QUOTE_TTL_S <= 30 * 60


def test_no_priced_offer_means_no_quote(atlas_world):
    atlas_world["quotes"] = {"ok": True, "sessionId": "qs_x", "offers": []}
    assert asyncio.run(atlas.quote(_trip())) is None


def test_without_a_key_atlas_is_never_called(atlas_world, monkeypatch):
    monkeypatch.setattr(config, "_config", {config.mode_key("atlas"): "live"})
    assert asyncio.run(atlas.quote(_trip())) is None
    assert atlas_world["calls"] == []


def test_a_minted_link_is_taken_on_201_and_names_no_offer(atlas_world):
    assert asyncio.run(atlas.mint_link(_trip(), "qs_one_traveller")) == TRACKED
    path, body, _ = atlas_world["calls"][-1]
    assert path == atlas.LINKS_PATH
    assert body["sessionId"] == "qs_one_traveller"
    assert "offerId" not in body and "linkCode" not in body


# ── A tap ────────────────────────────────────────────────────────────────────

def test_a_tap_gets_its_own_tracked_link(atlas_world):
    assert asyncio.run(atlas.tap_target(_trip(), traveller="t1")) == TRACKED
    assert [c[0] for c in atlas_world["calls"]] == [atlas.QUOTES_PATH, atlas.LINKS_PATH]


@pytest.mark.parametrize("why", ["shadow", "past", "no_offers", "link_refused"])
def test_a_tap_that_cannot_be_tracked_still_reaches_hellosafe(atlas_world, monkeypatch, why):
    trip = _trip()
    if why == "shadow":
        _switches(monkeypatch, atlas="shadow")
    if why == "past":
        trip = _trip(start_date="2026-01-01", end_date="2026-01-05")
    if why == "no_offers":
        atlas_world["quotes"] = {"ok": True, "sessionId": "qs_x", "offers": []}
    if why == "link_refused":
        atlas_world["link_status"] = 400
    url = asyncio.run(atlas.tap_target(trip, traveller="t1"))
    assert url.startswith(atlas.FUNNEL_URL + "?")
    query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
    assert query["countryResidence"] == ["LK"] and query["arrivalCountries"] == [trip["arrivalCountries"][0]]
    if why in ("shadow", "past"):
        assert atlas_world["calls"] == []


# ── The plan's row and button ────────────────────────────────────────────────

def test_the_row_names_the_insurer_beside_the_price_and_claims_no_cover():
    visa = atlas.plan_item("u", visa_needed=True, amount="INR 1,800", insurer="Chapka", travelers=2)
    assert visa["label"] == "BOOK NOW"
    assert "From INR 1,800 for 2 travellers with Chapka." in visa["reason"]
    assert "embassies" in visa["reason"]
    plain = atlas.plan_item("u", visa_needed=False, amount="USD 22", insurer="Chapka")
    assert plain["label"] == "BOOK CLOSER TO TRAVEL"
    assert "From USD 22 with Chapka." in plain["reason"]
    for row in (visa, plain):
        assert "meets" not in row["reason"].lower() and "covers" not in row["reason"].lower()
    assert atlas.button_label("INR 1,800", "Chapka") == "Insurance from INR 1,800 · Chapka"


def _finish(meta: dict, quotes: dict, mode: str = "live", currency: str = "USD") -> dict:
    """Run the provider step on a plan whose Atlas quotes are already in."""
    async def go():
        pending = enrich.Pending(modes={p: config.OFF for p in config.PROVIDERS}, international=True)
        pending.modes["atlas"] = mode
        for intent, priced in quotes.items():
            pending.insurance[intent] = _trip(destination="FR", intent=intent)

            async def done(priced=priced):
                return priced, 5
            pending.tasks[f"atlas:{intent}"] = asyncio.ensure_future(done())
        await enrich._finish(pending, [], meta, currency=currency, travelers=2)
        return meta
    return asyncio.run(go())


TOURIST = {"session_id": "s1", "offer_id": 1, "price": 22.5, "currency": "USD", "insurer": "Chapka", "offers": 3}
SCHENGEN = {"session_id": "s2", "offer_id": 2, "price": 31.0, "currency": "USD", "insurer": "Europ Assistance", "offers": 2}


def _intent(meta):
    token = urllib.parse.parse_qs(urllib.parse.urlparse(meta["practical_info"]["safety_url"]).query)["t"][0]
    return atlas.trip_from_token(token)["intent"]


def test_a_schengen_visa_keeps_the_schengen_quote():
    meta = _finish({"visa": {"status": "needed"}}, {atlas.TOURISM: TOURIST, atlas.SCHENGEN: SCHENGEN})
    assert _intent(meta) == atlas.SCHENGEN
    assert meta["practical_info"]["safety_cta"] == "Insurance from USD 31 · Europ Assistance"
    assert meta["provider_audit"]["atlas"]["intent"] == atlas.SCHENGEN


def test_no_visa_keeps_the_tourism_quote():
    meta = _finish({"visa": {"status": "not_needed"}}, {atlas.TOURISM: TOURIST, atlas.SCHENGEN: SCHENGEN})
    assert _intent(meta) == atlas.TOURISM
    assert meta["booking_plan"][-1]["label"] == "BOOK CLOSER TO TRAVEL"


def test_a_visa_trip_whose_schengen_quote_failed_falls_back_to_tourism():
    meta = _finish({"visa": {"status": "needed"}}, {atlas.TOURISM: TOURIST, atlas.SCHENGEN: None})
    assert _intent(meta) == atlas.TOURISM
    assert meta["booking_plan"][-1]["label"] == "BOOK NOW"


def test_no_quote_means_no_row():
    meta = _finish({"visa": {"status": "needed"}, "booking_plan": []}, {atlas.TOURISM: None})
    assert meta["booking_plan"] == []
    assert "safety_url" not in meta.get("practical_info", {})
    assert meta["provider_audit"]["atlas"]["skipped"] == "no_quote"


def test_a_second_pass_replaces_the_row():
    meta = _finish({"visa": {"status": "needed"}}, {atlas.TOURISM: TOURIST})
    meta = _finish(meta, {atlas.TOURISM: TOURIST})
    assert len([r for r in meta["booking_plan"] if atlas.is_atlas_link(r["url"])]) == 1


# ── End to end through generate_odyssey ──────────────────────────────────────

def test_live_adds_the_row_and_button_in_the_travellers_currency(world, atlas_world):
    _, meta, _ = e2e.run(world)          # Colombo → India, 2 travellers, INR, visa needed
    row = [r for r in meta["booking_plan"] if atlas.is_atlas_link(r["url"])]
    assert len(row) == 1
    assert row[0]["url"] == meta["practical_info"]["safety_url"]
    assert row[0]["url"].startswith(settings.PUBLIC_BASE_URL.rstrip("/") + atlas.TAP_PATH)
    assert "From INR 1,800 for 2 travellers with Chapka." in row[0]["reason"]
    assert meta["practical_info"]["safety_cta"] == "Insurance from INR 1,800 · Chapka"

    quoted = [c for c in atlas_world["calls"] if c[0] == atlas.QUOTES_PATH]
    assert len(quoted) == 1 and not [c for c in atlas_world["calls"] if c[0] == atlas.LINKS_PATH]
    sent = quoted[0][1]["trip"]
    assert (sent["countryResidence"], sent["arrivalCountries"], sent["startDate"], sent["endDate"]) == (
        "LK", ["IN"], "2026-11-02", "2026-11-07")
    assert meta["provider_audit"]["atlas"]["applied"] is True


def test_shadow_records_and_changes_nothing(world, atlas_world, monkeypatch):
    _switches(monkeypatch)
    _, before, _ = e2e.run(world)
    _switches(monkeypatch, atlas="shadow")
    _, meta, _ = e2e.run(world)
    assert meta["booking_plan"] == before["booking_plan"]
    assert "safety_url" not in (meta.get("practical_info") or {})
    assert meta["provider_audit"]["atlas"]["insurer"] == "Chapka"


def test_off_adds_nothing(world, atlas_world, monkeypatch):
    _switches(monkeypatch)
    _, meta, _ = e2e.run(world)
    assert "atlas" not in meta.get("provider_audit", {})
    assert atlas_world["calls"] == []


def test_an_unknown_home_country_asks_atlas_nothing(world, atlas_world):
    _, meta, _ = e2e.run(world, departure_country="", departure_city="")
    assert [c for c in atlas_world["calls"] if c[0] == atlas.QUOTES_PATH] == []
