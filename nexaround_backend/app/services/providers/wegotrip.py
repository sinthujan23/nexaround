"""WeGoTrip: tickets and audio tours for the sights a plan visits.

WeGoTrip's catalogue API is open, with no key. On 2026-09-29 it listed 694
cities in 79 countries, mostly attraction entry tickets (Burj Khalifa Level
124/125, EUR 49.71, rated 4.0 from 78 reviews) plus audio tours. It is strong
in Europe, the US, Australia and the UAE; thin in India (Agra, Jaipur, Mumbai);
and has nothing in Sri Lanka, the Maldives or Russia. Where it has nothing, the
stop is left exactly as it was.

    api/v2/cities/?page=N                    every city, 20 a page
    api/v2/products/popular/?city=ID&page=N  a city's products, 20 a page

(The city list's `itemsCount` undercounts: Dubai shows 32 there, 79 in its
products. Plain `products/?city=` answers "Bad products id format".)

A stop is matched to a product by name, strictly, because a wrong ticket is
worse than none: "Visit the Burj Khalifa" takes "Burj Khalifa: Level 124/125
Ticket", but "Dubai Miracle Garden" does not take "Dubai Garden Glow".
"""
from __future__ import annotations

import asyncio
import re
import time
import unicodedata
import urllib.parse
from typing import Optional

from app.services.providers import base

API = "https://app.wegotrip.com/api/v2"
SITE = "https://wegotrip.com"

CITIES_TTL_S = 7 * 86400
PRODUCTS_TTL_S = 24 * 3600
STALE_TTL_S = 14 * 86400
EMPTY_TTL_S = 6 * 3600
TIMEOUT_S = 6.0
# The whole city list is 35 pages; asked a few at a time, not all at once.
PARALLEL_PAGES = 6
# More pages than any city has (Paris: about 13).
MAX_PRODUCT_PAGES = 25
_MEMO_S = 3600

# Travelpayouts credits WeGoTrip sales to campaign 150, promo 4487: what its
# Links API returned for a WeGoTrip product URL on 2026-09-29.
_AFFILIATE_REDIRECT = "https://tp.media/r"
CAMPAIGN_ID = "150"
PROMO_ID = "4487"

# Countries named differently by Google and by WeGoTrip.
_COUNTRY_ALIASES = {
    "czech republic": "czechia",
    "turkiye": "turkey",
    "taiwan": "republic of china",
    "vatican city": "vatican",
    "united states of america": "united states",
    "usa": "united states",
    "uk": "united kingdom",
    "korea": "south korea",
}

# Sights WeGoTrip files under a neighbouring "country": a Rome plan's Vatican
# Museums are sold in Vatican City.
_ALSO_SEARCH = {("italy", "rome"): [("vatican", "vatican")]}

# Words about the product or the outing, not the place, dropped from both
# names before comparing ("Louvre Museum: Skip-the-Line Entry Ticket" → louvre
# museum; "Taj Mahal at Sunrise" → taj mahal). Written as `words()` folds them.
_GENERIC = frozenset("""
a an the of and or to at in on by for from with into through around near
de del della di da la le les el los las du des der die das van von
ticket entry entrance admission acces pas skip line priority fast track timed reserved
audio guide guided self app smartphone mobile digital hosted
tour visit explore exploring exploration discover experience highlight sightseeing
walking walk stroll city combo including incl optional plu continued
level floor hour day full half private small group trip excursion
night sunset sunrise evening morning afternoon exterior interior photo view
street district quarter neighbourhood neighborhood area zone
""".split())

# What the traveller does there. A ticket for the place still fits ("Széchenyi
# Spa" for "Relax at Széchenyi Thermal Bath"), but an audio walk never stands
# in for a cruise, a show or a meal ("Danube River Cruise" is not a walk
# along the Danube).
_ACTIVITY = frozenset("""
wine tasting cruise show dinner lunch breakfast food cooking clas workshop spa
boat ferry ride climb ascent relax
""".split())

# Kinds of place. They count, but a name made only of them ("Royal Palace")
# must be the stop's whole name, and a product and a stop that each name a
# kind must share one: the Borghese *Gallery* is not Villa Borghese *Gardens*.
_PLACE = frozenset("""
museum palace cathedral basilica church chapel abbey monastery tower castle gallery
garden park villa national royal old square fort fortres temple mosque synagogue
bridge market island beach house centre center art modern history historical
historic observation deck street district quarter town village canal river lake
bay harbour harbor port marina creek hill mount gate arch fountain statue
stadium opera theatre theater library tomb mausoleum memorial monument
observatory terminal station hall
""".split())

_SPLIT = re.compile(r"\s*(?::|\s[-–—]\s|\||&|\+|,|\(|\)|\band\b|\bwith\b)\s*", re.I)
_WORD = re.compile(r"[a-z]+")
# "2nd Floor", "1st Class": the suffix is not a word ("st" would read as Saint).
_ORDINAL = re.compile(r"\d+(?:st|nd|rd|th)\b")
_ALIASES = {
    "st": "saint", "ste": "sainte", "mt": "mount",
    "musee": "museum", "museo": "museum", "museu": "museum",
    "palazzo": "palace", "palais": "palace", "palacio": "palace",
    "galleria": "gallery", "galerie": "gallery",
    "duomo": "cathedral", "catedral": "cathedral", "cattedrale": "cathedral",
    "chiesa": "church", "iglesia": "church", "eglise": "church",
    "castello": "castle", "chateau": "castle", "castillo": "castle",
    "torre": "tower", "jardin": "garden", "giardino": "garden", "giardini": "garden",
    "parc": "park", "parque": "park", "piazza": "square", "plaza": "square",
    "ponte": "bridge", "pont": "bridge", "puente": "bridge",
}

# Only these stop types show the button in the app (odyssey.dart _parseType →
# ActivityType.attraction / exploration).
SIGHT_TYPES = frozenset({
    "attraction", "museum", "landmark", "ticket", "exploration", "explore", "walk", "wander",
})


def _fold(text: str) -> str:
    text = unicodedata.normalize("NFKD", str(text or ""))
    return "".join(c for c in text if not unicodedata.combining(c)).lower()


def words(text: str) -> set[str]:
    """Plain lower-case words, accents dropped, simple plurals folded."""
    out = set()
    for w in _WORD.findall(_ORDINAL.sub(" ", _fold(text))):
        w = _ALIASES.get(w, w)
        if len(w) > 3 and w.endswith("s"):
            w = w[:-1]
        out.add(w)
    return out


def _country_key(name: str) -> str:
    key = " ".join(_WORD.findall(_fold(name)))
    return _COUNTRY_ALIASES.get(key, key)


def _city_key(name: str) -> str:
    return " ".join(_WORD.findall(_fold(name)))


# ── Catalogue ────────────────────────────────────────────────────────────────

def _page(body) -> Optional[dict]:
    data = (body or {}).get("data") or {}
    if not isinstance(data.get("results"), list):
        return None
    return {"pages": int(data.get("pages") or 1), "results": data["results"]}


async def _get(operation: str, path: str, params: dict, ttl: int) -> Optional[dict]:
    got = await base.fetch(
        "wegotrip", operation,
        url=f"{API}/{path}",
        params=params,
        cache_params={"path": path, **params},
        fresh_ttl=ttl, stale_ttl=STALE_TTL_S, empty_ttl=EMPTY_TTL_S,
        timeout_s=TIMEOUT_S, transform=_page,
        is_empty=lambda page: not page or not page["results"],
        sku=f"wegotrip_{operation}",
    )
    return got.data


async def _all_pages(operation: str, path: str, params: dict, ttl: int, limit: int) -> list[dict]:
    first = await _get(operation, path, {**params, "page": 1}, ttl)
    if not first:
        return []
    results = list(first["results"])
    gate = asyncio.Semaphore(PARALLEL_PAGES)

    async def one(n: int):
        async with gate:
            return await _get(operation, path, {**params, "page": n}, ttl)

    rest = await asyncio.gather(*(one(n) for n in range(2, min(first["pages"], limit) + 1)))
    for page in rest:
        results += (page or {}).get("results") or []
    return results


_memo: dict = {"cities": None, "at": 0.0}


async def cities() -> list[dict]:
    """Every WeGoTrip city: {"id", "name", "slug", "country"}."""
    now = time.time()
    if _memo["cities"] is not None and now - _memo["at"] < _MEMO_S:
        return _memo["cities"]
    rows = await _all_pages("cities", "cities/", {}, CITIES_TTL_S, limit=100)
    found = [
        {"id": c.get("id"), "name": c.get("name") or "", "slug": c.get("slug") or "",
         "country": c.get("country") or ""}
        for c in rows if c.get("id") and c.get("slug")
    ]
    if found:
        _memo.update(cities=found, at=now)
    return found


def find_city(index: list[dict], city: str, country: str) -> Optional[dict]:
    """The WeGoTrip city for a plan's city, in the plan's country.

    "New York" finds "New York City". With no country given, only a name
    that exists once in the whole list counts.
    """
    want, land = _city_key(city), _country_key(country)
    if not want:
        return None
    pool = [c for c in index if _country_key(c["country"]) == land] if land else index
    exact = [c for c in pool if _city_key(c["name"]) == want]
    if len(exact) == 1 or (exact and land):
        return exact[0]
    if not land:
        return None
    longer = [c for c in pool if _city_key(c["name"]).startswith(want + " ")]
    return longer[0] if len(longer) == 1 else None


def cities_for_plan(index: list[dict], city_names: list[str], country: str) -> list[dict]:
    """The WeGoTrip cities of a plan's legs, plus any listed in `_ALSO_SEARCH`."""
    out: list[dict] = []
    for name in city_names:
        for where, what in [(country, name)] + _ALSO_SEARCH.get((_country_key(country), _city_key(name)), []):
            found = find_city(index, what, where)
            if found and found not in out:
                out.append(found)
    return out


def _slim(p: dict) -> Optional[dict]:
    city = p.get("city") or {}
    try:
        price = float(p.get("price"))
    except (TypeError, ValueError):
        return None
    if not (p.get("id") and p.get("slug") and city.get("id") and city.get("slug") and price > 0):
        return None
    if (p.get("tags") or {}).get("available") is False:
        return None
    if str(p.get("locale") or "en").lower() != "en":
        return None
    return {
        "id": p["id"], "title": str(p.get("title") or ""), "slug": p["slug"],
        "price": price, "currency": str(p.get("currencyCode") or "EUR").upper(),
        "rating": p.get("rating"), "reviews": int(p.get("reviewsCount") or 0),
        "category": str(p.get("category") or ""),
        "city_id": city["id"], "city_slug": city["slug"], "city": city.get("name") or "",
    }


async def products(city_id) -> list[dict]:
    """A city's bookable products, slimmed to what matching and the link need."""
    rows = await _all_pages(
        "products", "products/popular/", {"city": str(city_id)}, PRODUCTS_TTL_S, limit=MAX_PRODUCT_PAGES,
    )
    seen, out = set(), []
    for p in rows:
        slim = _slim(p) if isinstance(p, dict) else None
        if slim and slim["id"] not in seen:
            seen.add(slim["id"])
            out.append(slim)
    return out


async def catalogue_for(city_names: list[str], country: str) -> dict[str, list[dict]]:
    """Each plan city's products, by the plan's own city name; {} where
    WeGoTrip has none. A stop is only ever matched in its own city's list."""
    index = await cities()
    wanted = {name: cities_for_plan(index, [name], country) for name in city_names if name}
    ids = {c["id"] for found in wanted.values() for c in found}
    if not ids:
        return {}
    ids = sorted(ids)
    lists = dict(zip(ids, await asyncio.gather(*(products(i) for i in ids))))
    return {
        name: [p for c in found for p in lists.get(c["id"], [])]
        for name, found in wanted.items() if found
    }


# ── Matching a stop to a product ─────────────────────────────────────────────

def _names(title: str, drop: set[str]) -> list[set[str]]:
    """The places a product title names, in order, each as a set of words.

    "Palazzo Barberini & Galleria Corsini: Entry Ticket" names two;
    "Rome: Walking City Tour" names none once "Rome" and the generic words go.
    """
    out = []
    for part in _SPLIT.split(title):
        name = words(part) - _GENERIC - drop
        if name:
            out.append(name)
    return out


def _ticket_fits(stop: set[str], name: set[str]) -> bool:
    """Is this stop a visit to the place this ticket is for?"""
    own = name - _PLACE
    kinds, stop_kinds = name & _PLACE, stop & _PLACE
    if kinds and stop_kinds and not kinds & stop_kinds:
        return False  # the Borghese Gallery is not Villa Borghese's gardens
    if not own:
        return len(name) >= 2 and name == stop
    if not any(len(w) >= 3 for w in own):
        return name == stop  # "Red Fort": a short name must be the whole stop
    return own <= stop


def _walk_fits(stop: set[str], names: list[set[str]]) -> bool:
    """Is this audio walk about exactly what the stop is?

    Its main place must be in the stop, and everything the stop names — the
    cruise, the tower — must be in the walk: "Audio Walk Through Belém" is
    not a visit to Belém Tower, and a Shinjuku walk not Shinjuku Gyoen.
    """
    main, everything = names[0], set().union(*names)
    own = main - _PLACE
    if not own or not own <= stop or not any(len(w) >= 3 for w in own):
        return False
    if not (stop - _PLACE) <= everything:
        return False
    stop_kinds = stop & _PLACE
    return not stop_kinds or bool(stop_kinds & everything)


def match(stop_name: str, catalogue: list[dict], place_words: set[str]) -> Optional[dict]:
    """The product this stop is a visit to, or None.

    Only the place a product is named for counts, never one it mentions on
    the way ("Metropolitan Museum Ticket + Central Park Walk" is not a
    Central Park stroll). A ticket's place must appear whole in the stop's
    name and carry a word of its own ("Burj Khalifa", "Sagrada Familia"); a
    name made only of kinds of place ("Royal Palace") must be the stop's
    whole name. Of several products, the one covering most of the stop wins
    ("Colosseum & Roman Forum" takes the ticket for both), then a ticket over
    an audio walk, then the one with least else in its title, then the most
    reviewed. `place_words` are the plan's city and country names, which say
    nothing about which sight is meant.
    """
    stop_all = words(stop_name) - _GENERIC - place_words
    stop = stop_all - _ACTIVITY
    if not stop:
        return None
    best, best_key = None, None
    for product in catalogue:
        names = _names(product["title"], place_words | _ACTIVITY)
        if not names:
            continue
        ticket = kind(product) == "Ticket"
        if not (_ticket_fits(stop, names[0]) if ticket else _walk_fits(stop_all, names)):
            continue
        everything = set().union(*names)
        extra = everything - stop - _PLACE
        key = (len(stop & everything), ticket, -len(extra), product["reviews"], product.get("rating") or 0)
        if best_key is None or key > best_key:
            best, best_key = product, key
    return best


def place_words(city_names: list[str], country: str) -> set[str]:
    out = words(country)
    for name in city_names:
        out |= words(name)
    return out


# ── What the traveller sees ──────────────────────────────────────────────────

def product_url(p: dict) -> str:
    """The product's page, e.g. wegotrip.com/dubai-d292223/burj-khalifa-level-124125-ticket-p17326/."""
    return f"{SITE}/{p['city_slug']}-d{p['city_id']}/{p['slug']}-p{p['id']}/"


def booking_link(p: dict, *, marker: str, project_id: str) -> str:
    """The product page through Travelpayouts, so a sale earns us a share.

    Without both the partner ID and the Project ID it still opens the page.
    """
    page = product_url(p)
    if not (marker and project_id):
        return page
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "campaign_id": CAMPAIGN_ID, "marker": marker, "p": PROMO_ID, "trs": project_id, "u": page,
    })


def kind(p: dict) -> str:
    """"Ticket", "Audio tour" or "Tour": the title says, then the category.

    "Saint Mark's Basilica In-App Audio Tour (Without a Ticket)" is an audio
    tour, though its category is "Museum & Attraction Tickets".
    """
    title = p["title"].lower()
    if "without a ticket" in title or "without ticket" in title:
        return "Audio tour"
    if any(w in title for w in ("ticket", "entry", "entrance", "admission", "access")):
        return "Ticket"
    if "audio" in title:
        return "Audio tour"
    category = p["category"].lower()
    if "ticket" in category:
        return "Ticket"
    return "Audio tour" if "audio" in category else "Tour"


def rating_words(p: dict) -> str:
    """"rated 4.0 from 78 reviews", or "" with too few reviews to say."""
    try:
        rating = float(p.get("rating") or 0)
    except (TypeError, ValueError):
        return ""
    if rating <= 0 or p["reviews"] < 5:
        return ""
    return f"rated {rating:.1f} from {p['reviews']} reviews"
