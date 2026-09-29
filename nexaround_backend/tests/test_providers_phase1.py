"""Phase 1 providers: real airport-transfer (GetTransfer) and eSIM (Airalo) prices.

What these pin, in the order a plan meets them:
- the feeds are read the way the live ones are written (fixtures below are
  cut from real responses taken on 2026-09-25);
- a price is only ever shown through fields every app build renders today —
  the lead asked for no app change;
- shadow mode records and changes nothing; live mode changes only what it can
  stand behind; a failing provider leaves the plan exactly as Gemini wrote it.
"""
import asyncio
import datetime as dt
import json
import time

import httpx
import pytest

from app.services import odyssey_ai_service as svc
from app.services import place_cache_service
from app.services.providers import airalo, base, config, enrich, gettransfer, money

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)


# ── Shared fixtures ──────────────────────────────────────────────────────────

@pytest.fixture
def cache(monkeypatch):
    store: dict[str, str] = {}

    async def _get(key):
        return store.get(key)

    async def _set(key, value, ttl=0):
        store[key] = value

    monkeypatch.setattr(place_cache_service, "get_raw", _get)
    monkeypatch.setattr(place_cache_service, "set_raw", _set)
    monkeypatch.setattr(base, "_open_until", {})
    monkeypatch.setattr(base, "_failures", {})
    monkeypatch.setattr(airalo, "_memo", {"index": None, "at": 0.0})
    return store


@pytest.fixture
def switches(monkeypatch):
    def _set(**modes):
        values = {config.mode_key(p): m for p, m in modes.items()}
        monkeypatch.setattr(config, "_config", values)
        monkeypatch.setattr(config, "_config_at", time.time())
    return _set


def _serve(monkeypatch, handler):
    calls = []

    async def _handle(request):
        calls.append(request)
        return handler(request)

    monkeypatch.setattr(
        base, "_new_client",
        lambda: httpx.AsyncClient(transport=httpx.MockTransport(_handle)),
    )
    return calls


# ── Airalo ───────────────────────────────────────────────────────────────────

def _item(title, link, price, availability="in stock"):
    return (
        f"<item><g:title><![CDATA[{title}]]></g:title>"
        f"<g:link><![CDATA[{link}]]></g:link><g:price>{price}</g:price>"
        f"<g:availability>{availability}</g:availability></item>"
    )


FEED = "<rss><channel>" + "".join([
    _item("Sri Lanka travel eSIM | 1 GB, 10 mins of local calls, 10 SMS valid for 7 days",
          "https://www.airalo.com/sri-lanka-esim/a-7days-1gb?currency=USD", "4.50 USD"),
    _item("Sri Lanka travel eSIM | 3 GB, 30 mins of local calls, 30 SMS valid for 30 days",
          "https://www.airalo.com/sri-lanka-esim/a-30days-3gb?currency=USD", "9.00 USD"),
    _item("Sri Lanka travel eSIM | 10 GB, 100 mins of local calls, 100 SMS valid for 30 days",
          "https://www.airalo.com/sri-lanka-esim/a-30days-10gb?currency=USD", "17.00 USD"),
    _item("5 GB Turkey travel eSIM valid for 30 days",
          "https://www.airalo.com/turkey-esim/merhaba-30days-5gb?currency=USD", "10.00 USD"),
    _item("Guam travel eSIM | Unlimited GB, unlimited mins of local calls, unlimited SMS valid for 15 days",
          "https://www.airalo.com/guam-esim/g-15days-unl?currency=USD", "30.00 USD"),
    _item("5 GB Europe travel eSIM valid for 30 days",
          "https://www.airalo.com/europe-esim/eu-30days-5gb?currency=USD", "13.00 USD"),
    _item("1 GB Czech Republic travel eSIM valid for 7 days",
          "https://www.airalo.com/czech-republic-esim/c-7days-1gb?currency=USD", "4.00 USD",
          availability="out of stock"),
    _item("20 GB Czech Republic travel eSIM valid for 30 days",
          "https://www.airalo.com/czech-republic-esim/c-30days-20gb?currency=USD", "26.00 USD"),
]) + "</channel></rss>"


def test_the_feed_is_read_in_all_three_title_styles():
    index = airalo.parse_feed(FEED)
    assert index["sri-lanka"] == [[1.0, 7, 4.5], [3.0, 30, 9.0], [10.0, 30, 17.0]]
    assert index["turkey"] == [[5.0, 30, 10.0]]
    assert index["guam"] == [[None, 15, 30.0]], "unlimited data is kept as None"


def test_regional_packs_and_sold_out_plans_are_left_out():
    index = airalo.parse_feed(FEED)
    assert "europe" not in index
    assert index["czech-republic"] == [[20.0, 30, 26.0]]


def test_the_cheapest_plan_must_last_the_whole_trip():
    plans = airalo.parse_feed(FEED)["sri-lanka"]
    assert airalo.choose(plans, 5) == ([1.0, 7, 4.5], [10.0, 30, 17.0])
    cheapest, roomy = airalo.choose(plans, 14)
    assert cheapest == [3.0, 30, 9.0], "the 7-day plan runs out half way"
    assert roomy == [10.0, 30, 17.0]
    assert airalo.choose(plans, 45) == (None, None)


@pytest.mark.parametrize("name, code, slug", [
    ("Sri Lanka", "LK", "sri-lanka"),
    ("Türkiye", "TR", "turkey"),
    ("Czechia", "CZ", "czech-republic"),
    ("Côte d'Ivoire", "CI", "cote-divoire"),
    ("The Gambia", "GM", "gambia"),
    ("United States", "US", "united-states"),
])
def test_googles_country_names_reach_airalos_pages(name, code, slug):
    assert slug in airalo._candidates(name, code)


def test_the_tip_line_reads_in_the_travellers_currency():
    offer = {"country": "Sri Lanka", "cheapest": [1.0, 7, 4.5], "roomy": [10.0, 30, 17.0]}
    assert airalo.connectivity_line(offer, 300.0, "LKR") == (
        "Airalo eSIM for Sri Lanka: 1 GB for 7 days at LKR 1,350, or 10 GB for 30 days at LKR 5,100."
    )
    unlimited = {"country": "Guam", "cheapest": [None, 15, 30.0], "roomy": None}
    assert airalo.connectivity_line(unlimited, 1.0, "USD") == (
        "Airalo eSIM for Guam: unlimited data for 15 days at USD 30."
    )


def test_the_feed_is_downloaded_once_and_then_read_from_cache(cache, monkeypatch):
    calls = _serve(monkeypatch, lambda r: httpx.Response(200, text=FEED))

    async def run():
        first = await airalo.offer_for("Sri Lanka", "LK", 5)
        airalo._memo["at"] = 0.0  # forget the in-process copy; Redis still has it
        second = await airalo.offer_for("Türkiye", "TR", 10)
        return first, second

    first, second = asyncio.run(run())
    assert first["cheapest"] == [1.0, 7, 4.5]
    assert second["cheapest"] == [5.0, 30, 10.0]
    assert len(calls) == 1
    assert len(next(iter(cache.values()))) < 2000, "Redis keeps the index, not the XML"


def test_a_country_airalo_does_not_cover_gets_no_line(cache, monkeypatch):
    _serve(monkeypatch, lambda r: httpx.Response(200, text=FEED))
    assert asyncio.run(airalo.offer_for("Russia", "RU", 7)) is None


# ── GetTransfer ──────────────────────────────────────────────────────────────

def _route_body(prices, km=40, minutes=58):
    return {"result": "success", "data": {
        "distance": km, "duration": minutes, "routes": [{"legs": ["…"]}],
        "prices": {cls: ({"min": "US$1", "min_float": 1.0, "book_now": p} if p else {"min": "US$1"})
                   for cls, p in prices.items()},
    }}


def test_instant_prices_and_typical_offers_are_both_kept():
    got = gettransfer.parse_route(_route_body({"economy": "US$35", "comfort": None, "van": "US$4,659"}))
    assert got == {"prices": {"economy": {"now": 35.0, "min": 1.0},
                              "comfort": {"now": None, "min": 1.0},
                              "van": {"now": 4659.0, "min": 1.0}},
                   "km": 40, "minutes": 58}
    assert gettransfer.parse_route({"data": {"prices": {"economy": {}}}}) is None


# Copenhagen airport → city, as GetTransfer answered on 2026-09-25: the only
# instant price was a business van; an economy car's typical offer was USD 43.
COPENHAGEN = {"result": "success", "data": {"distance": 17, "duration": 31, "prices": {
    "economy": {"min": "US$43"}, "comfort": {"min": "US$50"}, "business": {"min": "US$62"},
    "van": {"min": "US$48"}, "business_van": {"min": "US$85", "book_now": "US$115"},
    "limousine": {"min": "US$130"},
}}}


def test_a_solo_traveller_is_never_quoted_a_van(cache, monkeypatch):
    _serve(monkeypatch, lambda r: httpx.Response(200, json=COPENHAGEN))
    q = asyncio.run(gettransfer.quote((55.62, 12.65), (55.68, 12.57), "2026-10-06", 1))
    assert (q["class"], q["usd_total"], q["bookable"]) == ("economy", 43.0, False)
    assert gettransfer.basis(q, 1, 1.0, "USD") == (
        "Economy car for 1 traveller (typical price) · 17 km · about 31 min"
    )


def test_an_instant_price_beats_a_typical_one_in_the_same_size():
    prices = {"economy": {"now": None, "min": 30.0}, "comfort": {"now": 45.0, "min": 40.0}}
    assert gettransfer.pick(prices, 2) == ("comfort", 45.0, True)


def test_a_party_of_five_is_priced_in_a_van_not_a_sedan():
    prices = {"economy": {"now": 35.0, "min": 30.0}, "van": {"now": 99.0, "min": 80.0}}
    assert gettransfer.pick(prices, 5) == ("van", 99.0, True)


def test_a_small_party_is_one_car_and_one_shared_answer(cache, monkeypatch):
    calls = _serve(monkeypatch, lambda r: httpx.Response(200, json=_route_body({"economy": "US$35"})))

    async def run():
        one = await gettransfer.quote((7.18, 79.88), (6.93, 79.84), "2026-11-10", 1)
        three = await gettransfer.quote((7.18, 79.88), (6.93, 79.84), "2026-11-10", 3)
        return one, three

    one, three = asyncio.run(run())
    assert one == three == {"usd_total": 35.0, "usd_each": 35.0, "cars": 1, "class": "economy",
                            "bookable": True, "km": 40, "minutes": 58}
    assert len(calls) == 1, "one to three travellers pay the same, so they share an answer"
    params = calls[0].url.params
    assert params.get_list("points[]") == ["7.18000,79.88000", "6.93000,79.84000"]
    assert params["pax"] == "3" and params["currency"] == "USD"
    assert params["date_to"] == "2026-11-10T12:00:00"


def test_a_big_party_with_no_big_car_is_several_cars(cache, monkeypatch):
    def reply(request):
        if request.url.params["pax"] == "5":
            return httpx.Response(200, json=_route_body({"economy": None}))
        return httpx.Response(200, json=_route_body({"economy": "US$35"}))

    _serve(monkeypatch, reply)
    q = asyncio.run(gettransfer.quote((7.18, 79.88), (6.93, 79.84), "2026-11-10", 5))
    assert (q["cars"], q["usd_total"], q["usd_each"]) == (2, 70.0, 35.0)


def test_a_big_party_takes_a_van_when_there_is_one(cache, monkeypatch):
    _serve(monkeypatch, lambda r: httpx.Response(200, json=_route_body({"van": "US$99", "minibus": "US$255"})))
    q = asyncio.run(gettransfer.quote((49.0, 2.55), (48.86, 2.35), "2026-11-10", 5))
    assert (q["cars"], q["class"], q["usd_total"]) == (1, "van", 99.0)


def test_a_route_gettransfer_cannot_serve_is_not_asked_twice(cache, monkeypatch):
    calls = _serve(monkeypatch, lambda r: httpx.Response(422, json={"error": "unprocessable"}))

    async def run():
        return [await gettransfer.quote((34.56, 69.21), (34.55, 69.20), "2026-11-10", 2) for _ in range(2)]

    assert asyncio.run(run()) == [None, None]
    assert len(calls) == 1


def test_the_token_is_sent_once_there_is_one(cache, monkeypatch):
    calls = _serve(monkeypatch, lambda r: httpx.Response(200, json=_route_body({"economy": "US$35"})))
    monkeypatch.setattr(config, "_config", {config.GETTRANSFER_API_TOKEN: "tok"})
    monkeypatch.setattr(config, "_config_at", time.time())
    asyncio.run(gettransfer.quote((7.18, 79.88), (6.93, 79.84), "2026-11-10", 2))
    assert calls[0].headers["X-ACCESS-TOKEN"] == "tok"


def test_a_missing_or_past_date_is_priced_two_weeks_out():
    today = dt.date(2026, 9, 25)
    assert gettransfer.query_date("2026-11-10", today) == "2026-11-10"
    assert gettransfer.query_date("", today) == "2026-10-09"
    assert gettransfer.query_date("2026-09-01", today) == "2026-10-09"


def test_the_details_line_says_what_was_priced():
    one = {"usd_total": 35.0, "usd_each": 35.0, "cars": 1, "class": "economy", "km": 40, "minutes": 58}
    assert gettransfer.basis(one, 2, 300.0, "LKR") == "Economy car for 2 travellers · 40 km · about 58 min"
    two = {"usd_total": 70.0, "usd_each": 35.0, "cars": 2, "class": "economy", "km": 40, "minutes": 75}
    assert gettransfer.basis(two, 5, 1.0, "USD") == (
        "2 economy cars (USD 35 each) for 5 travellers · 40 km · about 1 h 15 min"
    )


# ── Finding the transfer stops ───────────────────────────────────────────────

def _days(*acts_per_day):
    return [{"kind": "day", "day": n, "activities": list(acts)}
            for n, acts in enumerate(acts_per_day, start=1)]


def test_the_arrival_and_departure_stops_are_found():
    arrive = {"name": "Transfer: DEL airport → Delhi", "type": "transport"}
    leave = {"name": "Transfer: Agra → DEL airport", "type": "transport"}
    plan = _days([arrive, {"name": "Red Fort"}], [{"name": "Taj Mahal"}], [leave])
    assert enrich.find_transfer_row(plan, "arrival") is arrive
    assert enrich.find_transfer_row(plan, "departure") is leave


def test_an_early_flight_home_moves_the_transfer_to_the_day_before():
    leave = {"name": "Transfer to Bandaranaike Airport", "type": "transport"}
    plan = _days([{"name": "Arrive"}], [{"name": "Kandy"}, leave], [{"name": "Fly home"}])
    assert enrich.find_transfer_row(plan, "departure") is leave


def test_the_models_own_wording_is_recognised():
    arrive = {"name": "Arrival at Cochin International Airport (COK) & Transfer to Aluva",
              "type": "transport"}
    assert enrich.find_transfer_row(_days([arrive]), "arrival") is arrive


def test_the_denmark_plans_own_stops_are_found():
    """As generated on 2026-09-25 — neither stop uses the prompt's wording."""
    landing = {"name": "Arrival at Copenhagen Airport (CPH)", "type": "transport", "cost": "Free"}
    train_in = {"name": "Train to Copenhagen City Center", "type": "transport", "cost": "USD 6"}
    train_back = {"name": "Train to Copenhagen Central Station", "type": "transport", "cost": "USD 34"}
    to_airport = {"name": "Copenhagen Airport Transfer", "type": "transport", "cost": "USD 6"}
    plan = _days(
        [landing, train_in, {"name": "Hotel Check-in", "type": "accommodation"},
         {"name": "Rosenborg Castle", "type": "attraction"}],
        [{"name": "Roskilde Cathedral", "type": "attraction"}],
        [train_back, {"name": "Hotel Check-out", "type": "accommodation"},
         {"name": "Den Blå Planet", "type": "attraction"}, to_airport],
    )
    assert enrich.find_transfer_row(plan, "arrival") is train_in
    assert enrich.find_transfer_row(plan, "departure") is to_airport


def test_the_landing_itself_is_never_the_transfer():
    landing = {"name": "Arrival at Copenhagen Airport (CPH)", "type": "transport"}
    lunch = {"name": "Lunch at Torvehallerne", "type": "dining"}
    assert enrich.find_transfer_row(_days([landing, lunch]), "arrival") is None


def test_the_ride_before_the_flight_home_is_the_departure_transfer():
    ride = {"name": "Taxi to Bandaranaike International", "type": "transport"}
    flight = {"name": "Flight home to Dubai", "type": "transport"}
    assert enrich.find_transfer_row(_days([{"name": "x"}], [ride, flight]), "departure") is ride


def test_a_sight_with_airport_in_its_name_is_not_a_transfer():
    museum = {"name": "Old Airport Aviation Museum", "type": "attraction"}
    assert enrich.find_transfer_row(_days([museum]), "arrival") is None


@pytest.mark.parametrize("text, mode", [
    ("Take a PickMe or Uber taxi, about 45 min", "car"),
    ("Pre-booked private transfer with a driver", "car"),
    ("Airport Express metro line to New Delhi station", "public"),
    ("Take the airport bus or a taxi", "public"),
    ("Head into town", "unclear"),
])
def test_what_the_stop_travels_by(text, mode):
    assert enrich.transfer_mode({"name": "Transfer: X airport → Y", "tip": text}) == mode


# ── Shadow and live, end to end through generate_odyssey ─────────────────────

def _with_transfer_stops(world, monkeypatch):
    """The e2e world, with a model that writes both airport transfers."""
    inner = svc._call_gemini

    async def _gemini(prompt, api_key, **kw):
        text, chunks = await inner(prompt, api_key, **kw)
        try:
            plan = json.loads(text)
        except ValueError:
            return text, chunks
        if isinstance(plan, dict) and plan.get("day_plans"):
            days = plan["day_plans"]
            days[0]["activities"].insert(0, {
                "time": "07:00", "name": "Transfer: DEL airport → Delhi", "type": "transport",
                "tip": "Take a pre-paid taxi from the arrivals hall.",
                "cost_per_person": "400", "price_source": "Rome2Rio", "price_basis": "taxi fare",
            })
            days[-1]["activities"].append({
                "time": "18:00", "name": "Transfer: Agra → DEL airport", "type": "transport",
                "tip": "Gatimaan Express train to Delhi, then the Airport Express metro.",
                "cost_per_person": "900", "price_source": "IRCTC", "price_basis": "train + metro",
            })
            text = json.dumps(plan)
        return text, chunks

    monkeypatch.setattr(svc, "_call_gemini", _gemini)


@pytest.fixture
def providers(monkeypatch):
    """Fake provider answers, and a fixed rate of 90 INR to the dollar."""
    asked = []

    async def _quote(origin, dest, date, travelers):
        asked.append(("transfer", origin, dest, date, travelers))
        return {"usd_total": 20.0, "usd_each": 20.0, "cars": 1, "class": "economy",
                "bookable": True, "km": 12, "minutes": 35}

    async def _offer(country_name, country_code, days):
        asked.append(("esim", country_name, country_code, days))
        return {"country": country_name, "slug": "india",
                "cheapest": [1.0, 7, 4.0], "roomy": [10.0, 30, 16.0]}

    async def _rate(currency):
        return 90.0

    monkeypatch.setattr(enrich.gettransfer, "quote", _quote)
    monkeypatch.setattr(enrich.airalo, "offer_for", _offer)
    monkeypatch.setattr(enrich, "usd_rate", _rate)
    return asked


def _stop(days, name):
    return next(a for d in days for a in d["activities"] if a.get("name") == name)


def test_everything_off_asks_nobody_and_changes_nothing(world, monkeypatch, providers):
    _with_transfer_stops(world, monkeypatch)
    _, meta, days = e2e.run(world)
    assert providers == []
    assert "provider_audit" not in meta
    assert _stop(days, "Transfer: DEL airport → Delhi")["price_source"] == "Rome2Rio"


def test_shadow_records_what_it_would_do_and_changes_nothing(world, monkeypatch, providers, switches):
    switches(gettransfer="shadow", airalo="shadow")
    _with_transfer_stops(world, monkeypatch)
    _, meta, days = e2e.run(world)

    arrive = _stop(days, "Transfer: DEL airport → Delhi")
    assert arrive["price_source"] == "Rome2Rio", "shadow must not touch the plan"
    assert "Airalo" not in str(meta.get("practical_info", {}).get("connectivity", ""))

    audit = meta["provider_audit"]
    assert audit["gettransfer"]["arrival"]["decision"] == "info"
    assert audit["gettransfer"]["arrival"]["mode"] == "car"
    assert audit["gettransfer"]["departure"]["mode"] == "public"
    assert audit["gettransfer"]["arrival"]["applied"] is False
    assert audit["airalo"]["line"].startswith("Airalo eSIM for India")
    assert audit["airalo"]["applied"] is False
    # Priced where the plan really starts and ends: airport → first city, last city → airport.
    kinds = {(p[1], p[2]) for p in providers if p[0] == "transfer"}
    assert ((28.56, 77.10), (28.61, 77.21)) in kinds
    assert ((27.18, 78.01), (28.56, 77.10)) in kinds


def test_live_shows_the_private_car_as_information_and_changes_no_price(
    world, monkeypatch, providers, switches,
):
    """User, 2026-09-29: "for airport taxi, just show it as information"."""
    switches(gettransfer="live", airalo="live")
    _with_transfer_stops(world, monkeypatch)
    _, meta, days = e2e.run(world)

    arrive = _stop(days, "Transfer: DEL airport → Delhi")
    # The taxi fare the plan wrote stays; the private car is added beside it.
    assert arrive["price_source"] == "Rome2Rio"
    assert arrive["tip"] == (
        "Take a pre-paid taxi from the arrivals hall. "
        "Private car: INR 1,800 with GetTransfer, about 35 min."
    )
    assert "Private car option: INR 1,800 (GetTransfer, Economy car for 2 travellers" in arrive["price_basis"]

    leave = _stop(days, "Transfer: Agra → DEL airport")
    assert leave["price_source"] == "IRCTC", "the train the model chose stays the advice"
    assert leave["tip"].endswith("Private car: INR 1,800 with GetTransfer, about 35 min.")
    assert meta["provider_audit"]["gettransfer"]["arrival"]["applied"] is True

    assert meta["practical_info"]["connectivity"].endswith(
        "Airalo eSIM for India: 1 GB for 7 days at INR 360, or 10 GB for 30 days at INR 1,440."
    )


def test_live_leaves_the_budget_alone(world, monkeypatch, providers, switches):
    _with_transfer_stops(world, monkeypatch)
    _, before, _ = e2e.run(world)
    switches(gettransfer="live", airalo="live")
    _, after, _ = e2e.run(world)
    for key in ("budget_breakdown", "budget_scenarios", "verdict"):
        assert before.get(key) == after.get(key), key


def test_a_provider_that_fails_leaves_the_plan_as_written(world, monkeypatch, switches):
    switches(gettransfer="live", airalo="live")
    _with_transfer_stops(world, monkeypatch)

    async def _boom(*a, **kw):
        raise RuntimeError("provider down")

    monkeypatch.setattr(enrich.gettransfer, "quote", _boom)
    monkeypatch.setattr(enrich.airalo, "offer_for", _boom)
    _, meta, days = e2e.run(world)
    assert _stop(days, "Transfer: DEL airport → Delhi")["price_source"] == "Rome2Rio"
    assert meta["provider_audit"]["gettransfer"]["arrival"]["none"] == "no bookable car"


def test_a_domestic_trip_with_no_flight_prices_no_transfer(world, monkeypatch, providers, switches):
    switches(gettransfer="live", airalo="off")
    _with_transfer_stops(world, monkeypatch)
    e2e.run(world, include_flights=False, departure_city="Nagpur", departure_country="India")
    assert not [p for p in providers if p[0] == "transfer"]


def test_a_trip_abroad_with_no_fare_still_prices_its_airport_transfer(world, monkeypatch, providers, switches):
    """Colombo -> India with flights off opens at the airport (see
    abroad_rules), so its transfer is priced like a booked flight's."""
    switches(gettransfer="live", airalo="off")
    _with_transfer_stops(world, monkeypatch)
    e2e.run(world, include_flights=False)
    assert [p for p in providers if p[0] == "transfer"]


def test_an_airport_in_town_is_not_a_transfer():
    class Route:
        arrival = {"iata": "XXX", "latitude": 10.0, "longitude": 10.0}
        departure = {"iata": "XXX", "latitude": 10.0, "longitude": 10.0}

    legs = [{"city": "Town", "latitude": 10.001, "longitude": 10.001}]
    got = enrich.transfers_for(Route(), legs, "2026-11-10", "2026-11-17",
                               km=lambda a, b: 0.2)
    assert got == []


# ── Money ────────────────────────────────────────────────────────────────────

def test_amounts_read_like_the_rest_of_the_plan():
    assert money.format_amount("lkr", 10500) == "LKR 10,500"
    assert money.format_amount("USD", 35.0) == "USD 35"
    assert money.format_amount("USD", 4.5) == "USD 4.50"


def test_a_typical_offer_says_about():
    row = {"name": "Taxi from CPH airport to the city", "type": "transport",
           "cost": "USD 60", "price_source": "Estimate", "tip": "Cabs wait outside"}
    transfer = enrich.Transfer("arrival", (55.62, 12.65), (55.68, 12.57), "2026-10-06", "CPH → Copenhagen")
    q = {"usd_total": 43.0, "usd_each": 43.0, "cars": 1, "class": "economy",
         "bookable": False, "km": 17, "minutes": 31}
    entry = enrich._apply_transfer("arrival", transfer, q, 400, _days([row]),
                                   live=True, rate=1.0, currency="USD", travelers=1)
    assert entry["decision"] == "info" and entry["bookable"] is False
    assert row["cost"] == "USD 60", "the plan's own fare is never replaced"
    assert row["tip"] == "Cabs wait outside. Private car: about USD 43 with GetTransfer, about 31 min."
    assert "(typical price)" in row["price_basis"]


# ── The Airalo card: a link travellers can tap, with no app update ───────────

def test_the_link_is_exactly_what_travelpayouts_generates():
    """Returned by the partner-links API for Project 577812 on 2026-09-28."""
    assert airalo.booking_link("denmark", marker="781739", project_id="577812") == (
        "https://tp.media/r?campaign_id=541&marker=781739&p=8310&trs=577812"
        "&u=https%3A%2F%2Fwww.airalo.com%2Fdenmark-esim"
    )


def test_without_both_ids_the_link_still_reaches_the_right_page():
    assert airalo.booking_link("sri-lanka", marker="781739", project_id="") == (
        "https://www.airalo.com/sri-lanka-esim"
    )


def test_the_app_opens_the_card_link_untouched():
    """odyssey_plan_view.dart `_buildBookingSection` rewrites a card's URL when
    its name or type reads as hotels, flights or tours (these keyword lists),
    and opens it as sent otherwise. The card must fall in the second group."""
    name, kind = airalo.PARTNER_NAME.lower(), airalo.PARTNER_TYPE.lower()
    type_words = ("hotel", "stay", "accommodation", "transit", "flight", "transport",
                  "tour", "activity", "experience")
    name_words = ("booking", "agoda", "expedia", "ostrovok", "skyscanner", "aviasales",
                  "kayak", "viator", "getyourguide", "klook")
    assert not any(w in kind for w in type_words)
    assert not any(w in name for w in name_words)


def _ids_and_switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


def test_live_adds_one_airalo_card_to_the_plan(world, monkeypatch, providers):
    _ids_and_switches(monkeypatch, airalo="live")
    _, meta, _ = e2e.run(world)
    cards = [p for p in meta["booking_partners"] if "airalo" in p["name"].lower()]
    assert cards == [{
        "name": "Airalo eSIM", "type": "esim",
        "url": "https://tp.media/r?campaign_id=541&marker=781739&p=8310&trs=577812"
               "&u=https%3A%2F%2Fwww.airalo.com%2Findia-esim",
    }]
    assert meta["provider_audit"]["airalo"]["link"] == cards[0]["url"]


def test_shadow_adds_no_card(world, monkeypatch, providers):
    _ids_and_switches(monkeypatch, airalo="shadow")
    _, meta, _ = e2e.run(world)
    assert not [p for p in meta.get("booking_partners") or [] if "airalo" in p["name"].lower()]
    assert meta["provider_audit"]["airalo"]["link"].startswith("https://tp.media/r?")


def test_a_card_the_model_wrote_is_replaced_not_doubled():
    meta = {"booking_partners": [
        {"name": "Booking.com", "type": "hotels", "url": "https://www.booking.com"},
        {"name": "Airalo", "type": "other", "url": "https://www.airalo.com"},
    ]}
    enrich._add_partner(meta, "Airalo eSIM", "esim", "https://tp.media/r?x")
    assert [p["name"] for p in meta["booking_partners"]] == ["Booking.com", "Airalo eSIM"]


# ── The Airalo row in Booking Plan & Timeline (Overview tab) ─────────────────

def test_the_plan_row_names_the_plan_and_links_to_it():
    offer = {"country": "Japan", "slug": "japan", "cheapest": [5.0, 15, 10.5], "roomy": None}
    assert airalo.plan_item(offer, 1.0, "USD", "https://tp.media/r?x") == {
        "label": "BOOK CLOSER TO TRAVEL",
        "item": "Airalo eSIM for Japan: 5 GB for 15 days at USD 10.50",
        "reason": "Install it before you fly so you're online when you land.",
        "url": "https://tp.media/r?x",
    }


def test_the_row_sits_in_a_group_the_app_already_orders():
    """odyssey_plan_view.dart `_buildBookingPlanSection` labelOrder."""
    assert airalo.PLAN_LABEL in ("BOOK NOW", "BOOK AFTER VISA", "BOOK CLOSER TO TRAVEL", "CAN WAIT")


def test_live_adds_one_tappable_row_and_shadow_adds_none(world, monkeypatch, providers):
    _ids_and_switches(monkeypatch, airalo="live")
    _, meta, _ = e2e.run(world)
    rows = [r for r in meta["booking_plan"] if r["item"].startswith("Airalo")]
    assert len(rows) == 1
    assert rows[0]["item"] == "Airalo eSIM for India: 1 GB for 7 days at INR 360"
    assert rows[0]["url"].endswith("u=https%3A%2F%2Fwww.airalo.com%2Findia-esim")

    _ids_and_switches(monkeypatch, airalo="shadow")
    _, meta, _ = e2e.run(world)
    assert not [r for r in meta.get("booking_plan") or [] if r["item"].startswith("Airalo")]


def test_an_earlier_airalo_row_is_replaced_and_others_kept():
    meta = {"booking_plan": [
        {"label": "BOOK NOW", "item": "Flight to Tokyo", "reason": "", "url": "https://x"},
        {"label": "BOOK CLOSER TO TRAVEL", "item": "Airalo eSIM for Japan: old", "reason": "", "url": "u"},
    ]}
    enrich._add_plan_item(meta, {"label": "BOOK CLOSER TO TRAVEL", "item": "Airalo eSIM for Japan: new",
                                 "reason": "r", "url": "v"})
    assert [r["item"] for r in meta["booking_plan"]] == ["Flight to Tokyo", "Airalo eSIM for Japan: new"]


# ── The "Get eSIM" button under Connectivity & SIM ───────────────────────────

def test_the_button_names_the_cheapest_price_in_the_travellers_currency():
    offer = {"country": "Japan", "slug": "japan", "cheapest": [3.0, 7, 8.0], "roomy": [5.0, 7, 10.0]}
    assert airalo.button_label(offer, 1.0, "USD") == "Get eSIM · from USD 8"
    assert airalo.button_label(offer, 300.0, "LKR") == "Get eSIM · from LKR 2,400"


def test_live_gives_the_sim_tip_a_button_and_shadow_does_not(world, monkeypatch, providers):
    _ids_and_switches(monkeypatch, airalo="live")
    _, meta, _ = e2e.run(world)
    info = meta["practical_info"]
    assert info["connectivity_url"].endswith("u=https%3A%2F%2Fwww.airalo.com%2Findia-esim")
    assert info["connectivity_cta"] == "Get eSIM · from INR 360"

    _ids_and_switches(monkeypatch, airalo="shadow")
    _, meta, _ = e2e.run(world)
    assert "connectivity_url" not in meta["practical_info"]
    assert "connectivity_cta" not in meta["practical_info"]


# ── GetTransfer booking link (Airalo pattern, no API key) ───────────────────

def test_the_gettransfer_link_is_credited_to_us():
    """Verified 2026-09-29 against tp.media: lands on the booking page with
    sub_id=<click>-781739 and the travelpayouts utm tags."""
    assert gettransfer.booking_link("comfort", marker="781739", project_id="577812") == (
        "https://tp.media/r?marker=781739&trs=577812&p=4439"
        "&u=https%3A%2F%2Fgettransfer.com%2Fen%2Ftransfers%2Fnew%3Ftransfer_type%3Droute"
        "%26transport_type_ids%255B%255D%3Dcomfort"
    )
    # An unknown class books economy; no IDs still opens the page.
    assert gettransfer.booking_link("rocket", marker="", project_id="") == (
        "https://gettransfer.com/en/transfers/new?transfer_type=route&transport_type_ids%5B%5D=economy"
    )


def test_live_puts_the_link_on_the_stop_and_one_booking_plan_row(world, monkeypatch, providers):
    _ids_and_switches(monkeypatch, gettransfer="live")
    _with_transfer_stops(world, monkeypatch)
    _, meta, days = e2e.run(world)

    arrive = _stop(days, "Transfer: DEL airport → Delhi")
    assert arrive["booking_url"].startswith("https://tp.media/r?marker=781739&trs=577812&p=4439&u=")
    assert arrive["price_source"] == "Rome2Rio", "still information only"
    leave = _stop(days, "Transfer: Agra → DEL airport")
    assert leave["booking_url"].startswith("https://tp.media/r?marker=781739")

    rows = [r for r in meta["booking_plan"] if r["item"].startswith("GetTransfer")]
    assert len(rows) == 1
    assert rows[0]["item"] == "GetTransfer private car: DEL → Delhi, INR 1,800 one way"
    assert rows[0]["url"].startswith("https://tp.media/r?marker=781739")


def test_shadow_adds_no_link_and_no_row(world, monkeypatch, providers):
    _ids_and_switches(monkeypatch, gettransfer="shadow")
    _with_transfer_stops(world, monkeypatch)
    _, meta, days = e2e.run(world)
    assert not _stop(days, "Transfer: DEL airport → Delhi").get("booking_url")
    assert not [r for r in meta.get("booking_plan") or [] if r["item"].startswith("GetTransfer")]
