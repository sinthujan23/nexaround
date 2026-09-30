"""Kiwi.com: a second flight link beside Aviasales (user, 2026-09-30: "both options").

What these pin:
- the links are Kiwi's "deep" searches, the only kind Travelpayouts counts
  ("Kiwi.com affiliate links"), for every trip shape a plan flies, credited
  the way Travelpayouts credits Kiwi (campaign 111, promo 4136);
- they search the same trip as the Aviasales link, with the same checks;
- live adds `kiwi_url` to every option and one row right under the Booking
  Plan's flight row, keeping Google's link and the Aviasales row as they are;
  shadow and off change nothing.
"""
import datetime as dt
import time
import urllib.parse

import pytest

from app.services.providers import aviasales, config, kiwi

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)


@pytest.fixture(autouse=True)
def _before_the_trips(monkeypatch):
    monkeypatch.setattr(aviasales, "_today", lambda: dt.date(2026, 9, 30))


@pytest.mark.parametrize("legs, adults, url", [
    ([("DXB", "BCN", "2026-11-15"), ("BCN", "DXB", "2026-11-24")], 2,
     "https://www.kiwi.com/deep?from=DXB&to=BCN&departure=2026-11-15&return=2026-11-24&adults=2"),
    ([("DXB", "BCN", "2026-11-15")], 1,
     "https://www.kiwi.com/deep?from=DXB&to=BCN&departure=2026-11-15"),
    ([("CMB", "MAD", "2026-10-11"), ("BCN", "CMB", "2026-10-17")], 1,
     "https://www.kiwi.com/deep?multicity=CMB~MAD~2026-10-11/BCN~CMB~2026-10-17"),
    ([("DWC,DXB", "BCN", "2026-11-15")], 12,
     "https://www.kiwi.com/deep?from=DWC&to=BCN&departure=2026-11-15&adults=9"),
])
def test_every_trip_shape_is_a_deep_search(legs, adults, url):
    assert kiwi.deep_url(legs, adults=adults) == url


@pytest.mark.parametrize("legs", [
    [],
    [("DXB", "BCN", "2026-09-01")],                                  # already flown
    [("DXB", "BCN", "2026-11-15"), ("BCN", "DXB", "2026-11-10")],    # home before leaving
    [("Dubai", "BCN", "2026-11-15")],
])
def test_what_aviasales_cannot_search_kiwi_does_not_either(legs):
    assert kiwi.deep_url(legs) == ""
    assert aviasales.search_path(legs) == ""


def test_the_link_is_credited_to_us_through_travelpayouts():
    url = kiwi.deep_url([("DXB", "BCN", "2026-11-15"), ("BCN", "DXB", "2026-11-24")], adults=2)
    assert kiwi.booking_link(url, marker="781739", project_id="577812") == (
        "https://tp.media/r?campaign_id=111&marker=781739&p=4136&trs=577812&u="
        + urllib.parse.quote(url, safe="")
    )
    assert kiwi.booking_link(url, marker="781739", project_id="") == url


def test_kiwi_links_are_recognised_and_others_are_not():
    assert kiwi.is_kiwi_link(kiwi.booking_link("https://www.kiwi.com/deep?from=A", marker="1", project_id="2"))
    assert kiwi.is_kiwi_link("https://www.kiwi.com/deep?from=DXB&to=BCN")
    assert not kiwi.is_kiwi_link("https://tp.media/r?marker=1&trs=2&p=4114&u=x")    # Aviasales
    assert not kiwi.is_kiwi_link("https://notkiwi.com/")


# ── End to end through generate_odyssey ──────────────────────────────────────

def _switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


def _deep(link: str) -> str:
    return urllib.parse.parse_qs(urllib.parse.urlparse(link).query)["u"][0]


def test_live_adds_kiwi_beside_aviasales_and_keeps_googles(world, monkeypatch):
    _, before, _ = e2e.run(world)
    _switches(monkeypatch, aviasales="live", kiwi="live")
    _, meta, _ = e2e.run(world)

    options = meta["flight_strategies"]["strategies"]
    # The world's trip: Colombo → Delhi 2 Nov, home 7 Nov, two travellers.
    assert {_deep(o["kiwi_url"]) for o in options} == {
        "https://www.kiwi.com/deep?from=CMB&to=DEL&departure=2026-11-02&return=2026-11-07&adults=2",
    }
    was = {o["title"]: (o["booking_url"], o["provider_name"]) for o in before["flight_strategies"]["strategies"]}
    assert {o["title"]: (o["booking_url"], o["provider_name"]) for o in options} == was

    items = [r["item"] for r in meta["booking_plan"]]
    at = items.index("Flights on Aviasales: CMB → DEL and back")
    assert items[at + 1] == "Compare on Kiwi.com: CMB → DEL and back"
    assert meta["booking_plan"][at + 1]["label"] == meta["booking_plan"][at]["label"]
    assert meta["provider_audit"]["kiwi"]["plan_row"] is True


def test_with_aviasales_off_the_row_sits_under_the_google_flight_row(world, monkeypatch):
    _switches(monkeypatch, kiwi="live")
    _, meta, _ = e2e.run(world)
    rows = meta["booking_plan"]
    at = next(i for i, r in enumerate(rows) if "google.com/travel/flights" in r["url"])
    assert rows[at + 1]["item"] == "Compare on Kiwi.com: CMB → DEL and back"


def test_a_second_pass_replaces_the_row(world, monkeypatch):
    from app.services.providers import enrich
    _switches(monkeypatch, kiwi="live")
    _, meta, _ = e2e.run(world)
    enrich._apply_kiwi_links(meta, live=True, travelers=2, marker="781739", project_id="577812")
    assert len([r for r in meta["booking_plan"] if r["item"].startswith("Compare on Kiwi.com")]) == 1


def test_shadow_records_and_changes_nothing(world, monkeypatch):
    _, before, _ = e2e.run(world)
    _switches(monkeypatch, kiwi="shadow")
    _, meta, _ = e2e.run(world)
    assert not [o for o in meta["flight_strategies"]["strategies"] if "kiwi_url" in o]
    assert meta["booking_plan"] == before["booking_plan"]
    assert meta["provider_audit"]["kiwi"]["url"].startswith("https://www.kiwi.com/deep?from=CMB&to=DEL")


def test_off_adds_nothing(world):
    _, meta, _ = e2e.run(world)
    assert not [o for o in meta["flight_strategies"]["strategies"] if "kiwi_url" in o]
    assert "kiwi" not in meta.get("provider_audit", {})
