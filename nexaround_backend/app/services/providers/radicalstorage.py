"""Radical Storage: somewhere to leave the bags in the plan's cities.

Radical Storage keeps bags in shops and hotels in about 2,100 cities, from
around USD 2 a bag per day plus a per-bag cover fee at checkout ("from
£1.90/day, depending on bag size. A £1.99 fee per bag is added at checkout",
its London page). A traveller needs it on the day they check out with hours
left: before an evening flight, or a train to the next city.

Only a link and a "from" price. Each city has a page,
radicalstorage.com/luggage-storage/<slug>, and a city without one answers 404,
so the cities are read from Radical Storage's English city sitemap (2,095 on
2026-11-03; one gzipped file, kept a week). The page gives the city's country
and lowest price, in one of two shapes: big cities' pages carry schema.org
data (Service.areaServed's addressCountry, Product.offers' price), the rest
Next.js page data (cityRoot.city.lowestPrice, the storages' countryISO). A
name used twice gets a number on its second page (boston-1 is Boston,
Lincolnshire), so a page counts only in the plan's own country.

Travelpayouts credits Radical Storage sales to campaign 209, promo 5867: what
its Links API returned on 2026-11-03. The tracked link lands on the city page
with track_id=<click>-781739, as the dashboard's short link
radicalstorage.tp.st/BvPKQyc6 does. 8% of a booking, 30-day cookie, mobile web
and app tracked.
"""
from __future__ import annotations

import asyncio
import gzip
import json
import re
import time
import unicodedata
import urllib.parse
from typing import Optional

from app.services.providers import base

_AFFILIATE_REDIRECT = "https://tp.media/r"
CAMPAIGN_ID = "209"
PROMO_ID = "5867"

SITE = "https://radicalstorage.com"
SITEMAP = f"{SITE}/sitemap.xml"
_PAGE_PATH = re.compile(r"^/luggage-storage/([a-z0-9]+(?:-[a-z0-9]+)*)/?$")

CITIES_TTL_S = 7 * 86400
PAGE_TTL_S = 7 * 86400
STALE_TTL_S = 30 * 86400
EMPTY_TTL_S = 3 * 86400
TIMEOUT_S = 8.0
_MEMO_S = 3600

# Booking Plan rows, at most. The last city is always one of them: its
# check-out comes before the flight home.
MAX_ROWS = 3
# Cities looked up per plan, at most (one page each, cached a week).
MAX_LOOKUPS = 8
# Numbered pages tried after the plain one (boston-1, reno-2, sacramentous-3).
_MAX_NUMBER = 3

PLAN_LABEL = "BOOK CLOSER TO TRAVEL"
PARTNER_NAME = "Radical Storage Luggage"
PARTNER_TYPE = "luggage"

# A plan's name for a city → Radical Storage's slug, where they differ. Each
# target is in the sitemap.
_ALIASES = {
    "delhi": "new-delhi",
    "cochin": "kochi",
    "bangalore": "bengaluru",
    "bombay": "mumbai",
    "new-york-city": "new-york",
    "nyc": "new-york",
    "washington": "washington-dc",
    "washington-d-c": "washington-dc",
    "ho-chi-minh-city": "ho-chi-minh",
    "saigon": "ho-chi-minh",
    "marrakesh": "marrakech",
    "roma": "rome",
    "praha": "prague",
    "lisboa": "lisbon",
    "munchen": "munich",
    "wien": "vienna",
    "firenze": "florence",
    "venezia": "venice",
    "milano": "milan",
    "napoli": "naples",
}


def slugify(name: str) -> str:
    """"São Paulo" → sao-paulo, "St. Ives" → st-ives; brackets dropped."""
    text = unicodedata.normalize("NFKD", re.sub(r"\(.*?\)", " ", str(name or "")))
    text = "".join(c for c in text if not unicodedata.combining(c)).lower().replace("'", "").replace(".", "")
    return "-".join(re.findall(r"[a-z0-9]+", text))


def iso(country: str) -> str:
    """A country as ISO alpha-2 ("India" → IN), or "" when unsure."""
    text = str(country or "").strip()
    if len(text) == 2 and text.isalpha():
        return text.upper()
    if not text:
        return ""
    from app.services.geo_resolver import _COUNTRY_NAMES
    from app.services.trip_cost_floor import country_for

    code = next((c for c, n in _COUNTRY_NAMES.items() if n.casefold() == text.casefold()), "")
    return code or country_for(text) or ""


# ── The cities ───────────────────────────────────────────────────────────────

_CITY_SITEMAP = re.compile(r"<loc>\s*(https://[^<\s]*-en-\d+-city-\d+\.xml\.gz)\s*</loc>")
_CITY_LOC = re.compile(r"<loc>\s*https://radicalstorage\.com/luggage-storage/([a-z0-9-]+)/?\s*</loc>")


def _city_sitemaps(index_xml: str) -> list[str]:
    return _CITY_SITEMAP.findall(index_xml or "")


def _slugs(gz: bytes) -> list[str]:
    try:
        xml = gzip.decompress(gz).decode("utf-8", "replace")
    except (OSError, EOFError):
        xml = gz.decode("utf-8", "replace") if isinstance(gz, bytes) else str(gz or "")
    return sorted(set(_CITY_LOC.findall(xml)))


_memo: dict = {"cities": None, "at": 0.0}


async def cities() -> frozenset[str]:
    """Every city slug with a page. Empty when the sitemap cannot be read."""
    now = time.time()
    if _memo["cities"] is not None and now - _memo["at"] < _MEMO_S:
        return _memo["cities"]
    index = await base.fetch(
        "radicalstorage", "sitemap", url=SITEMAP, cache_params={"v": 1},
        fresh_ttl=CITIES_TTL_S, stale_ttl=STALE_TTL_S, timeout_s=TIMEOUT_S,
        parse="text", transform=_city_sitemaps, is_empty=lambda urls: not urls,
    )
    found: set[str] = set()
    for url in index.data or []:
        part = await base.fetch(
            "radicalstorage", "city_sitemap", url=url, cache_params={"url": url},
            fresh_ttl=CITIES_TTL_S, stale_ttl=STALE_TTL_S, timeout_s=TIMEOUT_S,
            parse="bytes", transform=_slugs, is_empty=lambda slugs: not slugs,
        )
        found.update(part.data or [])
    slugs = frozenset(found)
    if slugs:
        _memo.update(cities=slugs, at=now)
    return slugs


def candidates(city: str, slugs) -> list[str]:
    """The slugs a plan's city may be, the plain one first."""
    slug = slugify(city)
    slug = _ALIASES.get(slug, slug)
    if not slug:
        return []
    return [s for s in (slug, *(f"{slug}-{n}" for n in range(1, _MAX_NUMBER + 1))) if s in slugs]


# ── A city's page ────────────────────────────────────────────────────────────

_LD = re.compile(r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', re.S)
_NEXT = re.compile(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', re.S)


def _number(value) -> Optional[float]:
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    return n if n > 0 else None


def read_page(html: str) -> Optional[dict]:
    """A city page's name, country (ISO alpha-2) and lowest price per bag per
    day, or None when its country cannot be read."""
    name = country = currency = ""
    price: Optional[float] = None
    for block in _LD.findall(html or ""):
        try:
            data = json.loads(block)
        except ValueError:
            continue
        for item in data if isinstance(data, list) else [data]:
            if not isinstance(item, dict):
                continue
            if item.get("@type") == "Service":
                served = item.get("areaServed") if isinstance(item.get("areaServed"), dict) else {}
                address = served.get("address") if isinstance(served.get("address"), dict) else {}
                name = name or str(address.get("addressLocality") or "")
                country = country or iso(str(address.get("addressCountry") or ""))
            elif item.get("@type") == "Product" and isinstance(item.get("offers"), dict):
                price = price or _number(item["offers"].get("price"))
                currency = currency or str(item["offers"].get("priceCurrency") or "")

    found = _NEXT.search(html or "") if not country else None
    if found:
        try:
            root = json.loads(found.group(1))["props"]["pageProps"]["initialState"]["cityRoot"]
        except (ValueError, KeyError, TypeError):
            root = {}
        city = root.get("city") if isinstance(root.get("city"), dict) else {}
        codes = {
            s.get("countryISO") for s in root.get("storageList") or []
            if isinstance(s, dict) and s.get("countryISO")
        }
        name = name or str(city.get("name") or "")
        country = iso(next(iter(codes))) if len(codes) == 1 else iso(str(city.get("country") or ""))
        low = city.get("lowestPrice") if isinstance(city.get("lowestPrice"), dict) else {}
        cents = _number(low.get("cents")) or 100
        if price is None and _number(low.get("amount")):
            price = _number(low.get("amount")) / cents
            currency = str(low.get("currency") or "")

    if not country:
        return None
    currency = currency.upper() if re.fullmatch(r"[A-Za-z]{3}", currency or "") else ""
    return {
        "name": name,
        "country": country,
        "price": round(price, 2) if price and currency else None,
        "currency": currency if price else "",
    }


def page_url(slug: str) -> str:
    return f"{SITE}/luggage-storage/{slug}"


async def city_page(slug: str) -> Optional[dict]:
    got = await base.fetch(
        "radicalstorage", "city_page", url=page_url(slug), cache_params={"slug": slug},
        fresh_ttl=PAGE_TTL_S, stale_ttl=STALE_TTL_S, empty_ttl=EMPTY_TTL_S,
        timeout_s=TIMEOUT_S, parse="text", transform=read_page,
    )
    return got.data if isinstance(got.data, dict) else None


async def find(city: str, country: str = "") -> Optional[dict]:
    """Radical Storage's page for a city in its own country, or None.

    With no country known, the plain page is taken.
    """
    slugs = await cities()
    want = iso(country)
    for slug in candidates(city, slugs):
        page = await city_page(slug)
        if page and (not want or page["country"] == want):
            return {**page, "slug": slug, "url": page_url(slug)}
    return None


# ── A plan's cities ──────────────────────────────────────────────────────────

def _legs(legs: list, country: str = "") -> list[tuple[str, str]]:
    """(city, country) of each leg in trip order, each city once."""
    seen, out = set(), []
    for leg in legs or []:
        if not isinstance(leg, dict) or not str(leg.get("city") or "").strip():
            continue
        city = str(leg["city"]).strip()
        if slugify(city) in seen:
            continue
        seen.add(slugify(city))
        out.append((city, str(leg.get("country") or country or "")))
    return out


async def lookup(legs: list, country: str = "") -> dict[str, dict]:
    """The plan's cities Radical Storage has a page for: city name → page."""
    wanted = _legs(legs, country)[:MAX_LOOKUPS]
    pages = await asyncio.gather(*(find(c, k) for c, k in wanted), return_exceptions=True)
    return {c: p for (c, _), p in zip(wanted, pages) if isinstance(p, dict)}


def cities_to_link(legs: list, found: dict) -> list[str]:
    """The cities to give a row, in trip order: the last one always (its
    check-out comes before the flight home), then the earliest others, at
    most MAX_ROWS."""
    order = [c for c, _ in _legs(legs) if c in found]
    last = next(
        (str(leg.get("city")).strip() for leg in reversed(legs or [])
         if isinstance(leg, dict) and str(leg.get("city") or "").strip()), "",
    )
    keep = [c for c in order if slugify(c) == slugify(last)][:1]
    for c in order:
        if len(keep) >= MAX_ROWS:
            break
        if c not in keep:
            keep.append(c)
    return [c for c in order if c in keep]


# ── Links and rows ───────────────────────────────────────────────────────────

def booking_link(url: str, *, marker: str, project_id: str) -> str:
    """The city's page through Travelpayouts, so a booking earns us a share.

    Without both the partner ID and the Project ID it still opens the page.
    """
    if not (marker and project_id):
        return url
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "campaign_id": CAMPAIGN_ID, "marker": marker, "p": PROMO_ID, "trs": project_id, "u": url,
    })


def is_city_page(url: str) -> bool:
    """True for an https city page on radicalstorage.com."""
    try:
        parsed = urllib.parse.urlparse(str(url or ""))
    except ValueError:
        return False
    return (
        parsed.scheme == "https" and (parsed.hostname or "").lower() in ("radicalstorage.com", "www.radicalstorage.com")
        and bool(_PAGE_PATH.match(parsed.path or ""))
    )


def is_radicalstorage_link(url: str) -> bool:
    parsed = urllib.parse.urlparse(str(url or ""))
    if parsed.netloc == "tp.media":
        return urllib.parse.parse_qs(parsed.query).get("p") == [PROMO_ID]
    return parsed.netloc == "radicalstorage.com" or parsed.netloc.endswith(".radicalstorage.com")


def plan_item(city: str, link: str, price: str = "") -> dict:
    """The Booking Plan row. `price` is the city's lowest, already in the
    plan's currency ("" when the page showed none)."""
    reason = (
        "On check-out day, before a late train or flight: leave your bags at a "
        "nearby shop or hotel and keep exploring."
    )
    if price:
        reason += f" From {price} a bag per day, plus a per-bag cover fee."
    return {
        "label": PLAN_LABEL,
        "item": f"Radical Storage in {city}: luggage storage for the day",
        "reason": reason,
        "url": link,
    }
