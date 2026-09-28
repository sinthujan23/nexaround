"""Airalo eSIM prices, from the product feed Airalo gives Travelpayouts partners.

One public file lists every plan (about 3,300 of them, 15.5 MB of XML, 330 KB
gzipped): "Sri Lanka travel eSIM | 5 GB, 50 mins of local calls, 50 SMS valid
for 30 days", 13.00 USD. It carries no change headers, so it is simply fetched
again once it is a day old — by the worker's refresh loop, or by the first plan
that needs it — and kept in Redis as a compact index of country → plans. A
plan reads the index; it never waits on a download it did not have to make.
"""
from __future__ import annotations

import asyncio
import logging
import re
import time
import unicodedata
from typing import Optional

from app.services.providers import base, config

logger = logging.getLogger(__name__)

FEED_URL = "https://www.airalo.com/products.xml"
FRESH_TTL_S = 20 * 3600
STALE_TTL_S = 7 * 86400
# How often the refresh loop looks. Cheap: while the index is under a day old
# this is a Redis read, and it notices a switch turned on within minutes.
CHECK_EVERY_S = 10 * 60
# The file is big; this only ever runs while Gemini writes the itinerary, or in
# the background loop, so a generous limit costs no traveller any time.
TIMEOUT_S = 25.0
_MEMO_S = 10 * 60

# A plan big enough for maps, messaging and the odd video call on most trips.
ROOMY_GB = 5.0

# Multi-country packs. A plan is priced for its own country.
_REGIONS = frozenset({
    "africa", "africa-safari", "asia", "caribbean-islands", "eu-plus-uk", "europe",
    "global", "latin-america", "middle-east-and-north-africa", "north-america", "oceania",
})

# ISO code → Airalo's page name, where the country's everyday name does not
# turn into it (Google says "Türkiye" and "Czechia"; Airalo does not).
_ALIASES = {
    "AE": "united-arab-emirates", "BA": "bosnia-and-herzegovina", "BS": "bahamas",
    "CD": "democratic-republic-of-the-congo", "CG": "congo", "CI": "cote-divoire",
    "CV": "cape-verde", "CZ": "czech-republic", "GB": "united-kingdom", "GM": "gambia",
    "HK": "hong-kong", "KR": "south-korea", "LA": "laos", "MF": "saint-martinfrench-part",
    "MK": "macedonia", "MO": "macao", "PR": "puerto-rico-us", "PS": "palestine-state-of",
    "SX": "sint-maartendutch-part", "SZ": "eswatini", "TL": "timor-leste", "TR": "turkey",
    "US": "united-states", "VA": "vatican-city", "VI": "virgin-islands", "VN": "vietnam",
}

_ITEM = re.compile(r"<item>(.*?)</item>", re.S)
_SLUG = re.compile(r"airalo\.com/([a-z0-9-]+)-esim/")
_GB = re.compile(r"(\d+(?:\.\d+)?|unlimited)\s*GB", re.I)
_DAYS = re.compile(r"valid for (\d+) days?", re.I)
_USD = re.compile(r"([\d.]+)\s*USD")


def _tag(item: str, tag: str) -> str:
    m = re.search(rf"<{tag}>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</{tag}>", item, re.S)
    return m.group(1).strip() if m else ""


def parse_feed(xml: str) -> dict[str, list[list]]:
    """Country page name → [[gb, days, usd], ...], cheapest first.

    `gb` is None for an unlimited plan. Regional packs, out-of-stock plans and
    anything whose title does not say its data, validity and price are left
    out: a plan the traveller cannot read the terms of is not one to show.
    """
    index: dict[str, list[list]] = {}
    for item in _ITEM.findall(xml):
        slug = _SLUG.search(_tag(item, "g:link"))
        if not slug or slug.group(1) in _REGIONS:
            continue
        if "out" in _tag(item, "g:availability").lower():
            continue
        title = _tag(item, "g:title")
        gb, days, usd = _GB.search(title), _DAYS.search(title), _USD.search(_tag(item, "g:price"))
        if not (gb and days and usd):
            continue
        size = None if gb.group(1).lower() == "unlimited" else float(gb.group(1))
        index.setdefault(slug.group(1), []).append([size, int(days.group(1)), round(float(usd.group(1)), 2)])
    for plans in index.values():
        # Cheapest first; at the same price, the one with more data and days.
        plans.sort(key=lambda p: (p[2], -(p[0] if p[0] is not None else 1e6), -p[1]))
    return index


def slugify(name: str) -> str:
    text = unicodedata.normalize("NFKD", name or "").encode("ascii", "ignore").decode()
    text = text.lower().replace("&", " and ").replace("'", "")
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text[4:] if text.startswith("the-") else text


def _candidates(country_name: str, country_code: str) -> list[str]:
    from app.services.geo_resolver import _COUNTRY_NAMES

    code = (country_code or "").strip().upper()
    names = [_ALIASES.get(code, ""), slugify(country_name), slugify(_COUNTRY_NAMES.get(code, ""))]
    return [n for n in dict.fromkeys(names) if n]


def choose(plans: list[list], trip_days: int) -> tuple[Optional[list], Optional[list]]:
    """The cheapest plan that lasts the whole trip, and the cheapest roomy one.

    The second is None when the cheapest is already roomy, or nothing is.
    """
    lasting = [p for p in plans if p[1] >= max(trip_days, 1)]
    if not lasting:
        return None, None
    cheapest = lasting[0]
    roomy = next((p for p in lasting if p[0] is None or p[0] >= ROOMY_GB), None)
    if roomy is cheapest:
        roomy = None
    return cheapest, roomy


# ── Loading ──────────────────────────────────────────────────────────────────

_memo: dict = {"index": None, "at": 0.0}


async def load_index() -> Optional[dict]:
    """The country → plans index, from memory, Redis, or (rarely) Airalo."""
    now = time.time()
    if _memo["index"] is not None and now - _memo["at"] < _MEMO_S:
        return _memo["index"]
    got = await base.fetch(
        "airalo", "feed",
        url=FEED_URL,
        cache_params={"feed": "products.xml"},
        fresh_ttl=FRESH_TTL_S, stale_ttl=STALE_TTL_S, empty_ttl=3600,
        timeout_s=TIMEOUT_S, parse="text", transform=parse_feed,
        is_empty=lambda index: not index,
        sku="airalo_feed",
    )
    if got.ok:
        _memo.update(index=got.data, at=now)
    return got.data


async def offer_for(country_name: str, country_code: str, trip_days: int) -> Optional[dict]:
    """What the plan can say about an eSIM here, or None.

    {"country", "slug", "cheapest": [gb, days, usd], "roomy": [...] | None}
    """
    index = await load_index()
    if not index:
        return None
    for slug in _candidates(country_name, country_code):
        plans = index.get(slug)
        if not plans:
            continue
        cheapest, roomy = choose(plans, trip_days)
        if cheapest is None:
            return None
        return {"country": country_name, "slug": slug, "cheapest": cheapest, "roomy": roomy}
    return None


def _plan_words(plan: list, rate: float, currency: str) -> str:
    from app.services.providers.money import format_amount

    gb, days, usd = plan
    data = "unlimited data" if gb is None else f"{gb:g} GB"
    return f"{data} for {days} days at {format_amount(currency, usd * rate)}"


def connectivity_line(offer: dict, rate: float, currency: str) -> str:
    """"Airalo eSIM for Sri Lanka: 1 GB for 7 days at LKR 1,480, or 5 GB for 30 days at LKR 4,100.\""""
    line = f"Airalo eSIM for {offer['country']}: {_plan_words(offer['cheapest'], rate, currency)}"
    if offer.get("roomy"):
        line += f", or {_plan_words(offer['roomy'], rate, currency)}"
    return line + "."


async def refresh_loop() -> None:
    """Keep the index warm so no plan is the one that downloads it."""
    while True:
        try:
            if await config.mode("airalo") != config.OFF:
                _memo["at"] = 0.0
                await load_index()
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("[airalo] refresh failed: %s", e)
        await asyncio.sleep(CHECK_EVERY_S)
