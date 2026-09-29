"""WeGoTrip: tickets and audio tours on the sights a plan visits (user, 2026-09-29).

What these pin:
- the matcher pairs a stop with a product only when it is a visit to that
  very place. Every case below is a real stop from an Odyssey plan and a real
  WeGoTrip product title, taken on 2026-09-29, including the wrong pairings
  the first version made;
- the catalogue is read the way WeGoTrip writes it, and the link is the one
  Travelpayouts' own Links API returned;
- live adds a line and a link to the stop and never touches its cost; a stop
  only takes a product from the city it is in that day; shadow changes nothing.
"""
import asyncio
import json
import time

import pytest

from app.services.providers import config, enrich, wegotrip

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)


def _p(title, pid=1, reviews=10, price=20.0, city="Rome", city_id=3169070, slug="x", category="", rating=4.5):
    return {"id": pid, "title": title, "slug": slug, "price": price, "currency": "EUR",
            "rating": rating, "reviews": reviews, "category": category,
            "city_id": city_id, "city_slug": city.lower().replace(" ", "-"), "city": city}


def _match(stop, titles, cities=("Rome",), country="Italy"):
    catalogue = [_p(t, pid=i, reviews=r) for i, (t, r) in enumerate(titles)]
    got = wegotrip.match(stop, catalogue, wegotrip.place_words(list(cities), country))
    return got["title"] if got else None


# ── Matching: what must pair ─────────────────────────────────────────────────

@pytest.mark.parametrize("stop", [
    "Burj Khalifa 'At The Top' (Levels 124 & 125)",
    "At The Top, Burj Khalifa",
    "Burj Khalifa 'At The Top' Experience",
])
def test_every_way_the_model_names_the_burj_khalifa(stop):
    assert _match(stop, [("Burj Khalifa: Level 124/125 Ticket", 78)],
                  cities=("Dubai",), country="United Arab Emirates") == "Burj Khalifa: Level 124/125 Ticket"


def test_a_stop_naming_two_sights_takes_the_ticket_for_both():
    titles = [
        ("Roman Forum and Palatine Hill Entry with Multimedia Video", 109),
        ("Rome: Colosseum & the Roman Forum Ticket & Audio Tour + City Walk", 397),
    ]
    assert _match("Colosseum & Roman Forum", titles) == titles[1][0]


def test_the_plain_ticket_beats_a_bundle_for_the_same_sight():
    titles = [
        ("National Palace of Pena & Park: Priority Entrance Ticket", 162),
        ("Pena Palace Entrance Ticket", 597),
    ]
    assert _match("Pena Palace", titles, cities=("Lisbon",), country="Portugal") == "Pena Palace Entrance Ticket"


def test_a_ticket_beats_an_audio_tour_of_the_same_place():
    titles = [("Paris: Eiffel Tower Audio Tour", 0), ("Eiffel Tower: 2nd Floor Access + Optional Summit", 139)]
    assert _match("Eiffel Tower Ascent", titles, cities=("Paris",), country="France") == titles[1][0]


def test_a_name_made_only_of_kinds_of_place_must_be_the_whole_stop():
    title = "Madrid: Royal Palace & Gardens Fast-Track Ticket & Audio Tour"
    assert _match("Royal Palace of Madrid", [(title, 85)], cities=("Madrid",), country="Spain") == title
    assert _match("Royal Botanical Garden", [(title, 85)], cities=("Madrid",), country="Spain") is None


def test_local_spellings_and_accents_are_the_same_place():
    assert _match("Galleria dell'Accademia (David)", [("Accademia Gallery: Priority Entrance Ticket", 210)],
                  cities=("Florence",)) == "Accademia Gallery: Priority Entrance Ticket"
    assert _match("Musée d'Orsay", [("Paris: Musee d'Orsay Ticket & Audio Tour", 103)],
                  cities=("Paris",), country="France") == "Paris: Musee d'Orsay Ticket & Audio Tour"


def test_short_names_still_match():
    assert _match("Red Fort", [("Red Fort: Entry Ticket", 12)], cities=("Delhi",), country="India") == (
        "Red Fort: Entry Ticket")
    assert _match("London Eye", [("London: London Eye Ticket & Audio Tour with a City Walk", 0)],
                  cities=("London",), country="United Kingdom") is not None


def test_the_time_of_day_does_not_stop_a_match():
    assert _match("Taj Mahal at Sunrise", [("Agra: Taj Mahal Ticket & Audio Tour", 0)],
                  cities=("Agra",), country="India") == "Agra: Taj Mahal Ticket & Audio Tour"


def test_an_audio_walk_of_exactly_that_place_is_offered():
    title = "Lisbon: Self-Guided Audio Walk Through Baixa and Chiado"
    assert _match("Explore Baixa and Chiado districts", [(title, 0)],
                  cities=("Lisbon",), country="Portugal") == title


# ── Matching: the wrong pairings the first version made ──────────────────────

@pytest.mark.parametrize("stop, title, cities, country", [
    # A place the product only mentions on the way.
    ("Central Park Stroll", "New York: Metropolitan Museum of Art Ticket & Audio Tour + Central Park Walk",
     ("New York",), "United States"),
    ("Explore St. Mark's Square (Piazza San Marco)",
     "Venice: Doge's Palace Ticket & Audio Tour with St. Mark's Square Walk", ("Venice",), "Italy"),
    # One shared word, a different place.
    ("Explore Villa Borghese Gardens", "Rome: Borghese Gallery Ticket & Highlights Audio Tour", ("Rome",), "Italy"),
    ("Ponte Vecchio", "Palazzo Vecchio & Museum: Entry Ticket + Optional Video or Audio Guide", ("Florence",), "Italy"),
    ("Palais de l'Isle", "Paris: Palais Royal & Covered Galleries Audio Tour", ("Annecy", "Paris"), "France"),
    ("Dubai Miracle Garden", "Dubai Garden Glow: Entry Ticket", ("Dubai",), "United Arab Emirates"),
    # An activity, not a place.
    ("Wine Tasting in Beaune", "Loire Valley: Day Trip with Castle Entry + Wine Tasting", ("Beaune",), "France"),
    ("The Dubai Fountain Show", "La Perle by Dragone: Show Ticket", ("Dubai",), "United Arab Emirates"),
    # A walk is not a cruise, and a district walk is not its monument.
    ("Danube River Cruise", "Budapest: Self-Guided Audio Walk Through Danube and Castle Icons", ("Budapest",), "Hungary"),
    ("Belém Tower", "Lisbon: an Audio Walk Through Belém and the Age of Discovery - self-guided", ("Lisbon",), "Portugal"),
    ("Shinjuku Gyoen National Garden", "Tokyo: Shinjuku Walk Self-Guided Audio Tour", ("Tokyo",), "Japan"),
    ("Stroll through the Innere Stadt", "Vienna: Self-Guided Audio Walk Through the Old City and Design", ("Vienna",), "Austria"),
])
def test_a_different_sight_is_never_sold_as_this_one(stop, title, cities, country):
    assert _match(stop, [(title, 100)], cities=cities, country=country) is None


def test_an_audio_tour_without_a_ticket_is_not_called_a_ticket():
    p = _p("Saint Mark's Basilica In-App Audio Tour (Without a Ticket)", category="Museum & Attraction Tickets")
    assert wegotrip.kind(p) == "Audio tour"
    assert wegotrip.kind(_p("Burj Khalifa: Level 124/125 Ticket")) == "Ticket"
    assert wegotrip.kind(_p("Budapest: Buda Castle Hill Walk Audio Tour")) == "Audio tour"


# ── The catalogue ────────────────────────────────────────────────────────────

_INDEX = [
    {"id": 5128581, "name": "New York City", "slug": "new-york-city", "country": "United States"},
    {"id": 3169070, "name": "Rome", "slug": "rome", "country": "Italy"},
    {"id": 6691831, "name": "Vatican City", "slug": "vatican-city", "country": "Vatican"},
    {"id": 3067696, "name": "Prague", "slug": "prague", "country": "Czechia"},
    {"id": 2988507, "name": "Paris", "slug": "paris", "country": "France"},
]


def test_a_city_is_found_by_the_plans_own_name():
    assert wegotrip.find_city(_INDEX, "New York", "United States")["id"] == 5128581
    assert wegotrip.find_city(_INDEX, "Prague", "Czech Republic")["id"] == 3067696
    assert wegotrip.find_city(_INDEX, "Paris", "United States") is None
    assert wegotrip.find_city(_INDEX, "Paris", "")["id"] == 2988507


def test_a_rome_plan_also_reads_the_vatican():
    found = wegotrip.cities_for_plan(_INDEX, ["Rome"], "Italy")
    assert [c["name"] for c in found] == ["Rome", "Vatican City"]


def test_products_are_read_the_way_wegotrip_writes_them():
    raw = {  # cut from api/v2/products/popular/?city=292223, 2026-09-29
        "id": 17326, "title": "Burj Khalifa: Level 124/125 Ticket", "slug": "burj-khalifa-level-124125-ticket",
        "price": 49.71, "currencyCode": "EUR", "rating": 4.0, "reviewsCount": 78,
        "category": "Museum & Attraction Tickets", "city": {"id": 292223, "name": "Dubai", "slug": "dubai"},
        "tags": {"available": True}, "locale": "en",
    }
    p = wegotrip._slim(raw)
    assert p["price"] == 49.71 and p["reviews"] == 78 and p["city_slug"] == "dubai"
    assert wegotrip.product_url(p) == "https://wegotrip.com/dubai-d292223/burj-khalifa-level-124125-ticket-p17326/"
    assert wegotrip._slim({**raw, "locale": "es"}) is None, "a Spanish title named 'Lisboa' matched Lisbon stops"
    assert wegotrip._slim({**raw, "tags": {"available": False}}) is None
    assert wegotrip._slim({**raw, "price": 0}) is None


def test_the_link_is_exactly_what_travelpayouts_generates():
    p = _p("Burj Khalifa: Level 124/125 Ticket", pid=17326, city="Dubai", city_id=292223,
           slug="burj-khalifa-level-124125-ticket")
    assert wegotrip.booking_link(p, marker="781739", project_id="577812") == (
        "https://tp.media/r?campaign_id=150&marker=781739&p=4487&trs=577812"
        "&u=https%3A%2F%2Fwegotrip.com%2Fdubai-d292223%2Fburj-khalifa-level-124125-ticket-p17326%2F"
    )
    assert wegotrip.booking_link(p, marker="781739", project_id="").startswith("https://wegotrip.com/dubai-d292223/")


# ── Applied to a plan ────────────────────────────────────────────────────────

_LEGS = [{"city": "Delhi", "start_day": 1, "end_day": 3}, {"city": "Agra", "start_day": 4, "end_day": 6}]
_TAJ = _p("Agra: Taj Mahal Ticket & Audio Tour", pid=9, reviews=40, price=21.0, city="Agra", city_id=1279259,
          slug="agra-taj-mahal-ticket-audio-tour")
_FORT = _p("Red Fort: Entry Ticket", pid=8, reviews=12, price=5.0, city="Delhi", city_id=1273294, slug="red-fort")


def _days():
    return [
        {"day": 1, "activities": [
            {"type": "attraction", "name": "Red Fort", "tip": "Closed Mondays.", "cost": "INR 500"},
            {"type": "attraction", "name": "Taj Mahal replica talk", "tip": "", "cost": "Free"},
            {"type": "dining", "name": "Red Fort food walk", "tip": ""},
        ]},
        {"day": 4, "activities": [
            {"type": "attraction", "name": "Taj Mahal at Sunrise", "tip": "Gates open at 6.", "cost": "INR 1,100"},
            {"type": "exploration", "name": "Mehtab Bagh", "tip": "", "booking_url": "https://example.org"},
        ]},
    ]


def _apply(days, meta, live=True):
    return asyncio.run(enrich._apply_tickets(
        enrich.Pending(modes={"wegotrip": "live"}, legs=_LEGS, country="India"),
        {"Delhi": [_FORT], "Agra": [_TAJ]}, days, meta,
        live=live, rate=90.0, currency="INR", marker="781739", project_id="577812",
    ))


@pytest.fixture
def eur(monkeypatch):
    """0.9 euros to the dollar, 90 rupees to the dollar: EUR 1 = INR 100."""
    async def _rate(code):
        return {"EUR": 0.9}.get(code, 1.0)
    monkeypatch.setattr(enrich, "usd_rate", _rate)


def test_live_adds_a_line_and_a_link_and_keeps_the_cost(eur):
    days = _days()
    entry = _apply(days, {"booking_plan": []})

    taj = days[1]["activities"][0]
    assert taj["tip"] == ("Gates open at 6. On WeGoTrip: Agra: Taj Mahal Ticket & Audio Tour, "
                          "from INR 2,100 (rated 4.5 from 40 reviews).")
    assert taj["cost"] == "INR 1,100", "information only: the stop's own price stays"
    assert taj["booking_url"] == (
        "https://tp.media/r?campaign_id=150&marker=781739&p=4487&trs=577812"
        "&u=https%3A%2F%2Fwegotrip.com%2Fagra-d1279259%2Fagra-taj-mahal-ticket-audio-tour-p9%2F"
    )
    assert [m["stop"] for m in entry["matched"]] == ["Red Fort", "Taj Mahal at Sunrise"]


def test_a_stop_only_takes_a_product_from_the_city_it_is_in_that_day(eur):
    days = _days()
    _apply(days, {"booking_plan": []})
    # Day 1 is in Delhi: the Agra ticket is not offered there, whatever the stop's name.
    assert "booking_url" not in days[0]["activities"][1]


def test_meals_and_existing_links_are_left_alone(eur):
    days = _days()
    _apply(days, {"booking_plan": []})
    assert "booking_url" not in days[0]["activities"][2]
    assert days[1]["activities"][1]["booking_url"] == "https://example.org"


def test_tickets_go_in_the_booking_plan_most_reviewed_first(eur):
    meta = {"booking_plan": [{"label": "BOOK NOW", "item": "Hotel", "reason": "", "url": ""}]}
    _apply(_days(), meta)
    rows = [r for r in meta["booking_plan"] if r["item"].startswith("WeGoTrip")]
    assert [r["item"] for r in rows] == [
        "WeGoTrip: Agra: Taj Mahal Ticket & Audio Tour, from INR 2,100",
        "WeGoTrip: Red Fort: Entry Ticket, from INR 500",
    ]
    assert {r["label"] for r in rows} == {"BOOK CLOSER TO TRAVEL"}
    assert meta["booking_plan"][0]["item"] == "Hotel"
    # A second pass replaces its rows rather than doubling them.
    _apply(_days(), meta)
    assert len([r for r in meta["booking_plan"] if r["item"].startswith("WeGoTrip")]) == 2


def test_shadow_records_and_changes_nothing(eur):
    days, meta = _days(), {"booking_plan": []}
    entry = _apply(days, meta, live=False)
    assert days == _days() and meta == {"booking_plan": []}
    assert entry["mode"] == "shadow" and len(entry["matched"]) == 2


# ── End to end through generate_odyssey ──────────────────────────────────────

def _with_sights(monkeypatch):
    """The e2e world's model, writing the Taj Mahal into the Agra days."""
    from app.services import odyssey_ai_service as svc
    inner = svc._call_gemini

    async def _gemini(prompt, api_key, **kw):
        text, chunks = await inner(prompt, api_key, **kw)
        try:
            plan = json.loads(text)
        except ValueError:
            return text, chunks
        if isinstance(plan, dict) and plan.get("day_plans"):
            for day in plan["day_plans"]:
                if day.get("day") == 4:
                    day["activities"].insert(0, {
                        "time": "06:00", "name": "Taj Mahal at Sunrise", "type": "attraction",
                        "tip": "Gates open at 6.", "cost_per_person": "1100",
                    })
            text = json.dumps(plan)
        return text, chunks

    monkeypatch.setattr(svc, "_call_gemini", _gemini)


def test_live_reaches_the_plan_through_the_generator(world, monkeypatch, eur):
    asked = []

    async def _catalogue(cities, country):
        asked.append((cities, country))
        return {"Agra": [_TAJ]}

    monkeypatch.setattr(enrich.wegotrip, "catalogue_for", _catalogue)
    values = {config.mode_key("wegotrip"): "live",
              config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"}
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())
    _with_sights(monkeypatch)
    _, meta, days = e2e.run(world)

    assert asked == [(["Delhi", "Agra"], "India")]
    taj = next(a for d in days for a in d["activities"] if a.get("name") == "Taj Mahal at Sunrise")
    assert "On WeGoTrip: Agra: Taj Mahal Ticket & Audio Tour" in taj["tip"]
    assert taj["booking_url"].startswith("https://tp.media/r?campaign_id=150&marker=781739&p=4487")
    assert meta["provider_audit"]["wegotrip"]["matched"][0]["stop"] == "Taj Mahal at Sunrise"


def test_off_asks_wegotrip_nothing(world, monkeypatch):
    async def _catalogue(cities, country):
        raise AssertionError("switched off")

    monkeypatch.setattr(enrich.wegotrip, "catalogue_for", _catalogue)
    _, meta, _ = e2e.run(world)
    assert "wegotrip" not in meta.get("provider_audit", {})
