"""One cover photo per destination, looked up once, shown everywhere.

Where the photo comes from, and why in this order:

  1. Unsplash Iconic Landmark — when an Unsplash API key is configured, searches
     for the quintessential, world-famous landmark for the destination (e.g.
     Eiffel Tower for Paris, Colosseum for Rome, Statue of Liberty for New York,
     Taj Mahal for Agra, Big Ben for London). Provides high-resolution,
     stunning, and instantly recognizable travel photography.
  2. Google Places — a photo attached to the destination's place_id as a fallback
     when Unsplash has no photo or when the key is not set.
  3. Unsplash Country Cover — broader country-level iconic photo fallback.

Cached by destination in Redis for 30 days (misses for 6 hours).
"""
import logging
import re
from typing import Optional
from urllib.parse import quote

import httpx

from app.core.config import settings
from app.services import (
    geo_resolver,
    google_places_client,
    photo_cache_service,
    place_cache_service,
    telemetry,
)

logger = logging.getLogger(__name__)

_CACHE_TTL = 30 * 24 * 3600      # a cover, once found, is stable
_NEGATIVE_TTL = 6 * 3600         # nothing found — worth retrying, not hourly
_MISS = "__none__"               # sentinel; a real value is always a URL

# Bumping from v3 to v4 invalidates old random Google/country photo cache entries
# so all existing and new destinations receive their iconic landmark photos.
_KEY_VERSION = "v4"

# Width the cover is fetched and served at.
_PLACE_PHOTO_WIDTH = 1080

_UNSPLASH_SEARCH_URL = "https://api.unsplash.com/search/photos"

# Curated registry of top global and regional travel destinations mapped to their
# quintessential, iconic monument or landmark query for Unsplash.
_ICONIC_LANDMARKS: dict[str, str] = {
    # Europe
    "paris": "Paris Eiffel Tower landscape",
    "rome": "Rome Colosseum landscape",
    "london": "London Big Ben Westminster Tower Bridge",
    "barcelona": "Sagrada Familia Barcelona",
    "madrid": "Gran Via Madrid Royal Palace",
    "amsterdam": "Amsterdam canals canal houses",
    "venice": "Venice Grand Canal gondola Rialto",
    "florence": "Florence Cathedral Duomo Santa Maria del Fiore",
    "milan": "Milan Duomo Cathedral",
    "athens": "Acropolis Parthenon Athens Greece",
    "santorini": "Santorini Oia blue dome churches caldera",
    "mykonos": "Mykonos windmills Aegean",
    "prague": "Charles Bridge Prague Castle Old Town",
    "budapest": "Hungarian Parliament Budapest Danube",
    "vienna": "Schonbrunn Palace Vienna Austria",
    "berlin": "Brandenburg Gate Berlin",
    "munich": "Neuschwanstein Castle Bavaria",
    "dublin": "Trinity College Dublin Temple Bar",
    "edinburgh": "Edinburgh Castle Royal Mile Scotland",
    "lisbon": "Belem Tower Lisbon Tram 28",
    "porto": "Dom Luis Bridge Porto Ribeira",
    "seville": "Plaza de Espana Seville",
    "dubrovnik": "Dubrovnik Old Town walls Adriatic",
    "zurich": "Lake Zurich Alps Switzerland",
    "lucerne": "Chapel Bridge Lucerne Lake",
    "interlaken": "Interlaken Jungfrau Alps Switzerland",
    "zermatt": "Matterhorn Zermatt Swiss Alps",
    "geneva": "Jet d'Eau Geneva Lake",
    "brussels": "Grand Place Brussels",
    "bruges": "Bruges canals historic Belgium",
    "copenhagen": "Nyhavn Copenhagen canal",
    "stockholm": "Gamla Stan Stockholm Sweden",
    "oslo": "Oslo Opera House fjord",
    "reykjavik": "Iceland waterfall aurora landscape",

    # Asia & Middle East
    "tokyo": "Tokyo Tower Mount Fuji skyline",
    "kyoto": "Fushimi Inari Torii gate Kyoto",
    "osaka": "Osaka Castle Dotonbori",
    "dubai": "Burj Khalifa Dubai skyline",
    "abu dhabi": "Sheikh Zayed Grand Mosque Abu Dhabi",
    "doha": "Museum of Islamic Art Doha skyline",
    "singapore": "Marina Bay Sands Singapore skyline",
    "bangkok": "Wat Arun Grand Palace Bangkok",
    "phuket": "Maya Bay Phuket Thailand limestone",
    "chiang mai": "Chiang Mai ancient temple Thailand",
    "bali": "Ulun Danu Beratan Temple Bali",
    "kuala lumpur": "Petronas Twin Towers Kuala Lumpur",
    "seoul": "Gyeongbokgung Palace Seoul",
    "busan": "Haeundae Beach Busan Gamcheon",
    "beijing": "Great Wall of China Beijing",
    "shanghai": "The Bund Shanghai skyline Oriental Pearl",
    "hong kong": "Victoria Harbour Hong Kong skyline",
    "taipei": "Taipei 101 skyline",
    "istanbul": "Hagia Sophia Blue Mosque Istanbul",
    "cappadocia": "Cappadocia hot air balloons fairy chimneys",
    "delhi": "India Gate New Delhi",
    "new delhi": "India Gate New Delhi",
    "agra": "Taj Mahal Agra India",
    "jaipur": "Hawa Mahal Palace of Winds Jaipur",
    "udaipur": "City Palace Lake Pichola Udaipur",
    "mumbai": "Gateway of India Mumbai",
    "varanasi": "Varanasi Ghats Ganges river",
    "goa": "Goa beach palms",
    "amritsar": "Golden Temple Amritsar",
    "hanoi": "Ha Long Bay Vietnam limestone",
    "ho chi minh city": "Ho Chi Minh City skyline Saigon",
    "da nang": "Golden Bridge Ba Na Hills Da Nang",
    "hoi an": "Hoi An ancient town lanterns",
    "siem reap": "Angkor Wat temple Cambodia",
    "maldives": "Maldives overwater villas turquoise lagoon",

    # Sri Lanka
    "colombo": "Colombo Lotus Tower skyline",
    "kandy": "Temple of the Sacred Tooth Relic Kandy Lake",
    "sigiriya": "Sigiriya Lion Rock fortress Sri Lanka",
    "galle": "Galle Fort lighthouse Sri Lanka",
    "ella": "Nine Arch Bridge Ella Sri Lanka train",
    "nuwara eliya": "Nuwara Eliya tea plantations Sri Lanka",
    "mirissa": "Coconut Tree Hill Mirissa beach",
    "yala": "Yala National Park safari Sri Lanka",
    "bentota": "Bentota beach palm trees Sri Lanka",
    "negombo": "Negombo beach fishing lagoon Sri Lanka",
    "trincomalee": "Koneswaram Temple Swami Rock Trincomalee",
    "jaffna": "Nallur Kandaswamy Kovil Jaffna Fort",
    "dambulla": "Dambulla Royal Cave Temple Sri Lanka",
    "anuradhapura": "Ruwanwelisaya Stupa Anuradhapura",
    "polonnaruwa": "Polonnaruwa Vatadage ancient city",

    # Americas
    "new york": "Statue of Liberty Manhattan skyline New York",
    "new york city": "Statue of Liberty Manhattan skyline New York",
    "nyc": "Statue of Liberty Manhattan skyline New York",
    "san francisco": "Golden Gate Bridge San Francisco",
    "los angeles": "Hollywood sign Los Angeles skyline",
    "las vegas": "Las Vegas Strip Bellagio",
    "chicago": "Cloud Gate Millennium Park Chicago skyline",
    "washington": "United States Capitol Washington DC",
    "washington dc": "United States Capitol Washington DC",
    "miami": "South Beach Miami Ocean Drive Art Deco",
    "honolulu": "Waikiki Beach Diamond Head Honolulu Hawaii",
    "hawaii": "Na Pali Coast Kauai Hawaii landscape",
    "seattle": "Space Needle Seattle Mount Rainier",
    "boston": "Boston historic Beacon Hill",
    "new orleans": "French Quarter New Orleans Bourbon Street",
    "rio de janeiro": "Christ the Redeemer Rio de Janeiro Corcovado",
    "buenos aires": "Obelisco Buenos Aires Avenida 9 de Julio",
    "machu picchu": "Machu Picchu Inca ruins Peru",
    "cusco": "Machu Picchu Cusco Sacred Valley",
    "cancun": "Cancun Caribbean beach turquoise",
    "mexico city": "Palacio de Bellas Artes Mexico City",
    "tulum": "Tulum ruins Caribbean coast Mexico",
    "toronto": "CN Tower Toronto skyline",
    "vancouver": "Vancouver skyline mountains harbour",
    "montreal": "Notre-Dame Basilica Montreal Old Port",

    # Africa & Oceania
    "cairo": "Great Pyramids of Giza Sphinx Cairo",
    "giza": "Great Pyramids of Giza Sphinx",
    "luxor": "Karnak Temple Luxor Valley of the Kings",
    "cape town": "Table Mountain Cape Town",
    "marrakesh": "Koutoubia Mosque Marrakesh Medina",
    "zanzibar": "Zanzibar turquoise beach Stone Town",
    "nairobi": "Nairobi National Park wildlife skyline",
    "sydney": "Sydney Opera House Harbour Bridge",
    "melbourne": "Melbourne skyline Yarra River",
    "auckland": "Sky Tower Auckland harbour",
    "queenstown": "Queenstown Lake Wakatipu Remarkables",
}


def _key(destination: str) -> str:
    return f"cover:{_KEY_VERSION}:{destination.strip().lower()}"


def _get_iconic_query(destination: str, country: str = "") -> str:
    """Resolve destination to a targeted Unsplash query for its iconic landmark."""
    clean_dest = destination.strip()
    if not clean_dest:
        return ""

    lower_dest = clean_dest.lower()

    # 1. Direct match on full destination
    if lower_dest in _ICONIC_LANDMARKS:
        return _ICONIC_LANDMARKS[lower_dest]

    # 2. Extract city component if destination is "City, Country" or "Place, City, Country"
    parts = [p.strip() for p in clean_dest.split(",") if p.strip()]
    for part in parts:
        part_lower = part.lower()
        if part_lower in _ICONIC_LANDMARKS:
            return _ICONIC_LANDMARKS[part_lower]

    # 3. Check if any known city name is contained as a word in destination
    for city, query in _ICONIC_LANDMARKS.items():
        if re.search(rf"\b{re.escape(city)}\b", lower_dest):
            return query

    # 4. Dynamic fallback: craft a travel-focused landmark query
    city_name = parts[0] if parts else clean_dest
    country_part = f" {country.strip()}" if country and country.lower() not in city_name.lower() else ""
    return f"{city_name}{country_part} landmark iconic travel landscape"


def _pick_photo(refs: list[dict]) -> int:
    """Index of the photo to use: the largest landscape one, else the first."""
    best, best_px = None, -1
    for i, r in enumerate(refs):
        if r["width"] >= r["height"] and r["width"] * r["height"] > best_px:
            best, best_px = i, r["width"] * r["height"]
    return best if best is not None else 0


async def _google_place_cover(
    destination: str,
    pre_resolved_geo: Optional[geo_resolver.DestinationContext] = None,
) -> tuple[str, Optional[geo_resolver.DestinationContext]]:
    """Google's photo of the place. Returns (url, resolved context) so the
    caller can reuse the resolution rather than pay for it twice."""
    geo = pre_resolved_geo or await geo_resolver.resolve_destination(destination)
    if not geo.place_id:
        return "", geo
    refs = await google_places_client.fetch_place_photo_refs(geo.place_id)
    if not refs:
        return "", geo
    pick = _pick_photo(refs)
    ref = refs[pick]["name"]
    path = await photo_cache_service.get_or_fetch(ref, maxwidth=_PLACE_PHOTO_WIDTH, index=pick)
    if path is None:
        return "", geo
    base = settings.PUBLIC_BASE_URL.rstrip("/")
    url = f"{base}/api/v1/places/photo?ref={quote(ref, safe='')}&i={pick}&maxwidth={_PLACE_PHOTO_WIDTH}"
    return url, geo


async def _unsplash_search(query: str, api_key: str, cache_tag: str = "") -> str:
    """Top relevant landscape photo from Unsplash for a query. "" if none or on error."""
    if not api_key or not query:
        return ""
    params = {
        "query": query,
        "orientation": "landscape",
        "per_page": 3,
        "order_by": "relevant",
        "content_filter": "high",
        "client_id": api_key,
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            async with telemetry.track(
                "unsplash", "cover_photo_search",
                sku="unsplash_photo", cache_key=_key(cache_tag or query),
            ) as t:
                response = await client.get(_UNSPLASH_SEARCH_URL, params=params)
                t.upstream(response)
        if response.status_code != 200:
            logger.error("Unsplash search %r returned %s: %s",
                         query, response.status_code, response.text[:200])
            return ""
        data = response.json()
        results = data.get("results") if isinstance(data, dict) else None
        if not results:
            return ""
        # Pick the top result with a valid regular or full URL
        for item in results:
            if isinstance(item, dict):
                urls = item.get("urls") or {}
                url = urls.get("regular") or urls.get("full")
                if url:
                    return str(url)
        return ""
    except Exception as e:
        logger.error("Unsplash search failed for %r: %s", query, e)
        return ""


async def _unsplash_country_cover(country: str, api_key: str) -> str:
    """Top relevant Unsplash photo for a country name. Kept for backwards compatibility."""
    return await _unsplash_search(f"{country} travel landmark landscape", api_key, cache_tag=country)


async def fetch_cover_photo(destination: str, unsplash_api_key: str = "") -> str:
    """Uncached lookup. Returns an absolute image URL, or "" if there is none."""
    destination = (destination or "").strip()
    if not destination:
        return ""

    geo = None
    try:
        geo = await geo_resolver.resolve_destination(destination)
    except Exception as e:
        logger.warning("Geo resolve failed for %r: %s", destination, e)

    country = geo.country if geo is not None else ""

    # 1. Primary: Unsplash Iconic Landmark Photo (Eiffel Tower for Paris, etc.)
    if unsplash_api_key:
        iconic_query = _get_iconic_query(destination, country)
        try:
            url = await _unsplash_search(iconic_query, unsplash_api_key, cache_tag=destination)
            if url:
                return url
        except Exception as e:
            logger.warning("Unsplash iconic landmark search failed for %r (%r): %s",
                           destination, iconic_query, e)

    # 2. Secondary fallback: Google Places photo attached to destination
    try:
        url, _ = await _google_place_cover(destination, pre_resolved_geo=geo)
        if url:
            return url
    except Exception as e:
        logger.warning("Google place cover failed for %r: %s", destination, e)

    # 3. Tertiary fallback: Unsplash country-level search
    if unsplash_api_key and country:
        try:
            country_query = f"{country} travel landmark landscape"
            url = await _unsplash_search(country_query, unsplash_api_key, cache_tag=country)
            if url:
                return url
        except Exception as e:
            logger.warning("Unsplash country cover failed for %r: %s", country, e)

    return ""


async def cover_for_destination(destination: str, unsplash_api_key: str = "") -> str:
    """Resolve a destination to a cover URL through the shared cache.

    Caching the miss is the important half: an itinerary whose destination has
    no photo would otherwise be re-looked-up on every list poll, forever.
    Destinations repeat heavily across users, so the cache is shared, not
    per-user — two people's Dubai trips get the same skyline, which is the
    intent.
    """
    destination = (destination or "").strip()
    if not destination:
        return ""
    key = _key(destination)
    cached = await place_cache_service.get_raw(key)
    if cached is not None:
        return "" if cached == _MISS else cached

    url = await fetch_cover_photo(destination, unsplash_api_key)
    await place_cache_service.set_raw(
        key, url or _MISS, ttl=_CACHE_TTL if url else _NEGATIVE_TTL,
    )
    return url


# Alias for callers/tests that reference get_cover_url
get_cover_url = cover_for_destination
