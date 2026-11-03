"""Radical Storage: a luggage-storage row for the plan's cities (user, 2026-11-03).

What these pin:
- the link is the city's page on Radical Storage, credited to us the way
  Travelpayouts' Links API credits Radical Storage (campaign 209, promo 5867);
- a city's page is read in both of Radical Storage's page shapes, and counts
  only in the plan's own country (Boston, Lincolnshire is boston-1);
- the last city always gets a row (its check-out comes before the flight
  home), then the earliest others, at most three;
- the price is the city's lowest, in the plan's currency, per bag per day;
- shadow records and changes nothing; off asks nothing.
"""
import asyncio
import gzip
import json
import time

import pytest

from app.services import city_tours as ct
from app.services.providers import base, config, enrich, radicalstorage as rs

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)


def test_the_link_opens_the_citys_page_credited_to_us():
    assert rs.booking_link(rs.page_url("london"), marker="781739", project_id="577812") == (
        "https://tp.media/r?campaign_id=209&marker=781739&p=5867&trs=577812"
        "&u=https%3A%2F%2Fradicalstorage.com%2Fluggage-storage%2Flondon"
    )
    assert rs.booking_link(rs.page_url("kochi"), marker="781739", project_id="") == (
        "https://radicalstorage.com/luggage-storage/kochi"
    )


def test_radical_storage_links_are_recognised_and_others_are_not():
    assert rs.is_radicalstorage_link(rs.booking_link(rs.page_url("rome"), marker="1", project_id="2"))
    assert rs.is_radicalstorage_link("https://radicalstorage.com/luggage-storage/rome")
    assert not rs.is_radicalstorage_link("https://tp.media/r?campaign_id=62&p=1942&u=x")   # Go City
    assert not rs.is_radicalstorage_link("https://notradicalstorage.com/")


@pytest.mark.parametrize("url, ok", [
    ("https://radicalstorage.com/luggage-storage/boston-1", True),
    ("https://radicalstorage.com/luggage-storage/new-delhi/", True),
    ("http://radicalstorage.com/luggage-storage/paris", False),
    ("https://radicalstorage.com/my/account", False),
    ("https://radicalstorage.com/luggage-storage/london/king-s-cross", False),
    ("https://evil.example/luggage-storage/paris", False),
])
def test_only_city_pages_count(url, ok):
    assert rs.is_city_page(url) is ok


# ── The cities ───────────────────────────────────────────────────────────────

_SLUGS = frozenset({
    "london", "kochi", "new-delhi", "boston", "boston-1", "alexandria-1", "sao-paulo",
    "new-york", "ho-chi-minh", "st-ives-2", "colombo",
})


@pytest.mark.parametrize("city, slugs", [
    ("London", ["london"]),
    ("Cochin", ["kochi"]),
    ("Delhi", ["new-delhi"]),
    ("New York City", ["new-york"]),
    ("Ho Chi Minh City", ["ho-chi-minh"]),
    ("São Paulo", ["sao-paulo"]),
    ("St. Ives", ["st-ives-2"]),
    ("Boston", ["boston", "boston-1"]),
    ("Alexandria", ["alexandria-1"]),
    ("Colombo (Fort)", ["colombo"]),
    ("Kandy", []),
    ("", []),
])
def test_a_plans_city_names_its_pages(city, slugs):
    assert rs.candidates(city, _SLUGS) == slugs


def test_the_city_list_is_read_from_the_gzipped_sitemap():
    index = (
        '<sitemapindex><sitemap><loc>https://radicalstorage.com/sitemap-catalog-1--sitemap-2-en-4-city-00001.xml.gz'
        '</loc></sitemap><sitemap><loc>https://radicalstorage.com/sitemap-catalog-1--sitemap-2-de-4-city-00001.xml.gz'
        '</loc></sitemap><sitemap><loc>https://radicalstorage.com/sitemap-catalog-1--sitemap-2-en-3-cms-00001.xml.gz'
        '</loc></sitemap></sitemapindex>'
    )
    assert rs._city_sitemaps(index) == [
        "https://radicalstorage.com/sitemap-catalog-1--sitemap-2-en-4-city-00001.xml.gz",
    ]
    xml = (
        "<urlset><url><loc>https://radicalstorage.com/luggage-storage/aachen</loc></url>"
        "<url><loc>https://radicalstorage.com/luggage-storage/boston-1</loc></url>"
        "<url><loc>https://radicalstorage.com/de/gepaeckaufbewahrung/aachen</loc></url></urlset>"
    )
    assert rs._slugs(gzip.compress(xml.encode())) == ["aachen", "boston-1"]


# ── A city's page ────────────────────────────────────────────────────────────

def _ld(*items):
    return "".join(f'<script type="application/ld+json">{json.dumps(i)}</script>' for i in items)


# A big city's page: schema.org data (London, 2026-11-03).
_LONDON = "<html><head>" + _ld(
    {"@type": "Product", "name": "Luggage Storage London from £1.90 | Bag Lockers",
     "offers": {"@type": "Offer", "price": "1.9", "priceCurrency": "GBP"}},
    {"@type": "Service", "areaServed": {"@type": "Place", "address": {
        "@type": "PostalAddress", "addressLocality": "London", "addressCountry": "GB"}}},
    {"@type": "BreadcrumbList", "itemListElement": []},
) + "</head></html>"


def _next_page(name, country, iso, amount, currency="USD"):
    """A smaller city's page: Next.js page data, no country in its schema.org."""
    data = {"props": {"pageProps": {"initialState": {"cityRoot": {
        "city": {"name": name, "country": country,
                 "lowestPrice": {"amount": amount, "currency": currency, "cents": 100}},
        "storageList": [{"countryISO": iso}, {"countryISO": iso}],
    }}}}}
    return (
        _ld({"@type": "SelfStorage", "priceRange": "From $2.90/day"})
        + f'<script id="__NEXT_DATA__" type="application/json">{json.dumps(data)}</script>'
    )


def test_a_big_citys_page_is_read_from_its_schema_data():
    assert rs.read_page(_LONDON) == {"name": "London", "country": "GB", "price": 1.9, "currency": "GBP"}


def test_a_smaller_citys_page_is_read_from_its_page_data():
    page = _next_page("Kochi", "India", "IN", 290)
    assert rs.read_page(page) == {"name": "Kochi", "country": "IN", "price": 2.9, "currency": "USD"}


def test_a_page_without_storages_names_its_country_in_words():
    page = _next_page("Kochi", "India", "", 290).replace('{"countryISO": ""}, {"countryISO": ""}', "")
    assert rs.read_page(page)["country"] == "IN"


def test_a_page_with_no_country_is_not_used():
    assert rs.read_page("<html>Luggage storage</html>") is None
    assert rs.read_page(_ld({"@type": "Product", "offers": {"price": "2", "priceCurrency": "USD"}})) is None


def test_a_page_with_no_price_still_counts():
    page = _LONDON.replace('"price": "1.9", ', "")
    assert rs.read_page(page) == {"name": "London", "country": "GB", "price": None, "currency": ""}


def _pages(monkeypatch, pages: dict):
    async def _cities():
        return frozenset(pages)

    async def _page(slug):
        return pages.get(slug)

    monkeypatch.setattr(rs, "cities", _cities)
    monkeypatch.setattr(rs, "city_page", _page)


_PAGES = {
    "boston": {"name": "Boston", "country": "US", "price": 2.0, "currency": "USD"},
    "boston-1": {"name": "Boston", "country": "GB", "price": 3.2, "currency": "GBP"},
    "kochi": {"name": "Kochi", "country": "IN", "price": 2.9, "currency": "USD"},
    "new-delhi": {"name": "New Delhi", "country": "IN", "price": 2.9, "currency": "USD"},
}


@pytest.mark.parametrize("city, country, slug", [
    ("Boston", "US", "boston"),
    ("Boston", "GB", "boston-1"),
    ("Boston", "United Kingdom", "boston-1"),
    ("Kochi", "IN", "kochi"),
    ("Kochi", "JP", None),          # Kochi, Shikoku: Radical Storage's Kochi is in India
    ("Delhi", "India", "new-delhi"),
    ("Kochi", "", "kochi"),         # no country known: the plain page
    ("Kandy", "LK", None),
])
def test_a_page_counts_only_in_the_plans_own_country(monkeypatch, city, country, slug):
    _pages(monkeypatch, _PAGES)
    found = asyncio.run(rs.find(city, country))
    assert (found or {}).get("slug") == slug
    if slug:
        assert found["url"] == f"https://radicalstorage.com/luggage-storage/{slug}"


def test_each_city_is_looked_up_once_with_its_legs_country(monkeypatch):
    _pages(monkeypatch, _PAGES)
    legs = [
        {"city": "Delhi", "country": "IN", "start_day": 1, "end_day": 2},
        {"city": "Kochi", "country": "", "start_day": 3, "end_day": 4},
        {"city": "Delhi", "country": "IN", "start_day": 5, "end_day": 5},
        {"city": "Agra", "country": "IN", "start_day": 6, "end_day": 6},
    ]
    found = asyncio.run(rs.lookup(legs, "IN"))
    assert {c: p["slug"] for c, p in found.items()} == {"Delhi": "new-delhi", "Kochi": "kochi"}


def test_a_failed_city_page_answers_nothing(monkeypatch):
    async def _fetch(*args, **kwargs):
        return base.Fetched(error="timeout")

    monkeypatch.setattr(base, "fetch", _fetch)
    rs._memo.update(cities=None, at=0.0)
    assert asyncio.run(rs.cities()) == frozenset()
    assert asyncio.run(rs.find("London", "GB")) is None


# ── Which cities get a row ───────────────────────────────────────────────────

def _found(*cities):
    return {c: {"slug": c.lower(), "url": rs.page_url(c.lower()), "price": 2.0, "currency": "USD"} for c in cities}


def test_the_last_city_always_gets_a_row_then_the_earliest_others():
    legs = [{"city": c} for c in ("Rome", "Florence", "Venice", "Milan", "Naples")]
    found = _found("Rome", "Florence", "Venice", "Milan", "Naples")
    assert rs.cities_to_link(legs, found) == ["Rome", "Florence", "Naples"]


def test_cities_without_a_page_are_skipped():
    legs = [{"city": c} for c in ("Colombo", "Kandy", "Ella", "Colombo")]
    assert rs.cities_to_link(legs, _found("Colombo")) == ["Colombo"]
    assert rs.cities_to_link(legs, {}) == []


def test_the_row_gives_the_price_per_bag_per_day():
    row = rs.plan_item("Kochi", "https://tp.media/r?x", "INR 255")
    assert row["item"] == "Radical Storage in Kochi: luggage storage for the day"
    assert "From INR 255 a bag per day, plus a per-bag cover fee." in row["reason"]
    assert row["label"] in ("BOOK NOW", "BOOK AFTER VISA", "BOOK CLOSER TO TRAVEL", "CAN WAIT")
    assert row["url"] == "https://tp.media/r?x"
    assert "From" not in rs.plan_item("Kochi", "https://tp.media/r?x")["reason"]


# ── Applied to a plan ────────────────────────────────────────────────────────

_LEGS = [
    {"city": "London", "country": "GB", "start_day": 1, "end_day": 3},
    {"city": "Bath", "country": "GB", "start_day": 4, "end_day": 5},
]
_FOUND = {"London": {"slug": "london", "url": rs.page_url("london"), "name": "London",
                     "country": "GB", "price": 1.9, "currency": "GBP"}}


def _pending():
    return enrich.Pending(modes={"radicalstorage": "live"}, legs=_LEGS, country="United Kingdom")


def _apply(meta, live=True, rate=1.0, currency="USD", found=None):
    return asyncio.run(enrich._apply_radicalstorage(
        meta, _pending(), found if found is not None else _FOUND,
        live=live, rate=rate, currency=currency, marker="781739", project_id="577812",
    ))


def test_live_adds_the_row_and_card_and_keeps_the_rest(monkeypatch):
    async def _rate(code):
        return {"GBP": 0.8, "INR": 88.0}.get(code)

    monkeypatch.setattr(enrich, "usd_rate", _rate)
    meta = {"booking_plan": [{"label": "BOOK NOW", "item": "Hotel", "reason": "", "url": "https://h"}]}
    entry = _apply(meta, rate=88.0, currency="INR")
    assert [r["item"] for r in meta["booking_plan"]] == [
        "Hotel", "Radical Storage in London: luggage storage for the day",
    ]
    # GBP 1.90 is USD 2.375, INR 209.
    assert "From INR 209 a bag per day" in meta["booking_plan"][1]["reason"]
    assert meta["booking_plan"][1]["url"].startswith("https://tp.media/r?campaign_id=209&marker=781739&p=5867")
    assert meta["booking_partners"] == [{
        "name": "Radical Storage Luggage", "type": "luggage", "url": meta["booking_plan"][1]["url"],
    }]
    assert entry == {"mode": "live", "cities": {"London": "london"}, "rows": 1}
    # A second pass replaces its row rather than doubling it.
    _apply(meta, rate=88.0, currency="INR")
    assert len(meta["booking_plan"]) == 2 and len(meta["booking_partners"]) == 1


def test_shadow_records_the_link_and_changes_nothing():
    meta = {"booking_plan": []}
    entry = _apply(meta, live=False)
    assert meta == {"booking_plan": []}
    assert entry["links"]["London"].startswith("https://tp.media/r?campaign_id=209")


def test_no_city_with_a_page_adds_nothing():
    meta = {"booking_plan": []}
    assert _apply(meta, found={}) == {"mode": "live", "cities": {}, "rows": 0}
    assert meta == {"booking_plan": []}


# ── In City Guides ───────────────────────────────────────────────────────────

def _guide_with(url):
    stop = {"type": "stop", "name": "Big Ben", "lat": 51.5, "lng": -0.12,
            "links": [{"kind": "affiliate", "partner": "radicalstorage", "url": url}]}
    return ct.normalize({"city": "London", "country": "United Kingdom", "title": "London in a day",
                         "summary": "x", "steps": [stop]})


def test_a_guide_link_keeps_only_a_radical_storage_city_page():
    good = "https://radicalstorage.com/luggage-storage/london"
    for url, kept in ((good, True), ("https://evil.example/luggage-storage/london", False), ("", False)):
        guide = _guide_with(url)
        link = ct.all_steps(guide)[0]["links"][0]
        assert link["url"] == (url if kept else "")
        problem = "Stop 1: Radical Storage has no luggage storage in London. Remove its link."
        assert (problem in ct.problems(guide)) is not kept


def test_a_guide_tap_goes_through_travelpayouts():
    url = ct.tracked_url("radicalstorage", "https://radicalstorage.com/luggage-storage/london",
                         marker="781739", project_id="577812")
    assert url.startswith("https://tp.media/r?campaign_id=209&marker=781739&p=5867&trs=577812")


# ── End to end through generate_odyssey ──────────────────────────────────────

def _switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


def test_live_reaches_the_plan_through_the_generator(world, monkeypatch):
    # The e2e world is Delhi and Agra.
    asked = []

    async def _lookup(legs, country=""):
        asked.append(([leg["city"] for leg in legs], country))
        return {"Delhi": {"slug": "new-delhi", "url": rs.page_url("new-delhi"), "name": "New Delhi",
                          "country": "IN", "price": 2.9, "currency": "USD"}}

    monkeypatch.setattr(enrich.radicalstorage, "lookup", _lookup)
    _switches(monkeypatch, radicalstorage="live")
    _, meta, _ = e2e.run(world)

    assert asked and asked[0][0] == ["Delhi", "Agra"]
    rows = [r for r in meta["booking_plan"] if r["item"].startswith("Radical Storage")]
    assert [r["item"] for r in rows] == ["Radical Storage in Delhi: luggage storage for the day"]
    assert rows[0]["url"].startswith("https://tp.media/r?campaign_id=209&marker=781739&p=5867")
    assert meta["provider_audit"]["radicalstorage"]["cities"] == {"Delhi": "new-delhi"}
    assert any(p["name"] == "Radical Storage Luggage" for p in meta["booking_partners"])


def test_off_asks_nothing(world, monkeypatch):
    async def _lookup(legs, country=""):
        raise AssertionError("switched off")

    monkeypatch.setattr(enrich.radicalstorage, "lookup", _lookup)
    _, meta, _ = e2e.run(world)
    assert "radicalstorage" not in meta.get("provider_audit", {})
