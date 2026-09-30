"""Go City: a sightseeing-pass row for the big cities it sells passes in.

Go City sells one digital pass for many attractions in a city: All-Inclusive
(unlimited entries for a set number of days) or Explorer (a chosen number of
attractions within 30 days), and in some cities Essentials. Which passes a
city has varies (Prague launched with All-Inclusive only), so the row never
promises one.

Only a link. gocity.com answers our server with Cloudflare's "Attention
Required" page, and Travelpayouts offers Go City as links only, so neither the
passes' prices nor the attractions they include can be read. The row names
the city's pass page (`/passes`, "Pass Prices" on Go City's site), which lists
every option with today's price.

Travelpayouts credits Go City sales to campaign 62, promo 1942: what its Links
API returned on 2026-09-30. 6% of a booking (3.4% with a coupon), 90-day
cookie, confirmed up to 120 days later; bookings in Go City's own app earn
nothing, but our links open its website.
"""
from __future__ import annotations

import re
import unicodedata
import urllib.parse

_AFFILIATE_REDIRECT = "https://tp.media/r"
CAMPAIGN_ID = "62"
PROMO_ID = "1942"
SITE = "https://gocity.com/en"

# A pass pays for itself over a few paid sights, not in one evening.
MIN_DAYS = 2
MAX_ROWS = 2

PLAN_LABEL = "BOOK CLOSER TO TRAVEL"

# Go City's cities, each seen with its own page on gocity.com/en/<slug> in
# web search on 2026-09-30: slug → (name shown, country, other names a plan
# may use). Go City says "28 destinations" on its site and 31 in a 2024 press
# release; these are the ones with a page found. Washington DC's page now
# carries New York's title, so it is left out.
DESTINATIONS: dict[str, tuple[str, str, tuple[str, ...]]] = {
    "new-york": ("New York", "US", ("new york city", "nyc", "manhattan", "brooklyn")),
    "boston": ("Boston", "US", ()),
    "chicago": ("Chicago", "US", ()),
    "philadelphia": ("Philadelphia", "US", ()),
    "san-francisco": ("San Francisco", "US", ()),
    "los-angeles": ("Los Angeles", "US", ("hollywood",)),
    "san-diego": ("San Diego", "US", ()),
    "las-vegas": ("Las Vegas", "US", ()),
    "orlando": ("Orlando", "US", ()),
    "miami": ("Miami", "US", ("miami beach",)),
    "oahu": ("Oahu", "US", ("honolulu", "waikiki")),
    "cancun": ("Cancun", "MX", ()),
    "london": ("London", "GB", ()),
    "dublin": ("Dublin", "IE", ()),
    "paris": ("Paris", "FR", ()),
    "amsterdam": ("Amsterdam", "NL", ()),
    "barcelona": ("Barcelona", "ES", ()),
    "madrid": ("Madrid", "ES", ()),
    "rome": ("Rome", "IT", ("roma",)),
    "prague": ("Prague", "CZ", ("praha",)),
    "stockholm": ("Stockholm", "SE", ()),
    "gothenburg": ("Gothenburg", "SE", ("goteborg",)),
    "dubai": ("Dubai", "AE", ()),
    "hong-kong": ("Hong Kong", "HK", ()),
    "singapore": ("Singapore", "SG", ()),
    "sydney": ("Sydney", "AU", ()),
}


def _key(name: str) -> str:
    text = unicodedata.normalize("NFKD", str(name or ""))
    text = "".join(c for c in text if not unicodedata.combining(c)).lower()
    return " ".join(re.findall(r"[a-z]+", text))


_BY_NAME = {
    _key(alias): slug
    for slug, (name, _, aliases) in DESTINATIONS.items()
    for alias in (name, *aliases)
}


def destination_for(city: str, country: str = "") -> str:
    """The Go City slug for a plan's city, or "".

    With the leg's country known it must agree, so a "Paris" in Texas or a
    "Sydney" in Nova Scotia gets no pass.
    """
    slug = _BY_NAME.get(_key(city), "")
    if slug and country and len(country) == 2 and country.upper() != DESTINATIONS[slug][1]:
        return ""
    return slug


def cities_to_link(legs: list) -> list[str]:
    """Slugs of the plan's Go City cities stayed in at least MIN_DAYS days,
    longest stay first; a city on two legs counts once, its days summed."""
    days: dict[str, int] = {}
    for leg in legs or []:
        if not isinstance(leg, dict):
            continue
        slug = destination_for(str(leg.get("city") or ""), str(leg.get("country") or ""))
        if not slug:
            continue
        try:
            span = int(leg.get("end_day") or 0) - int(leg.get("start_day") or 0) + 1
        except (TypeError, ValueError):
            span = 0
        days[slug] = days.get(slug, 0) + max(span, 0)
    ready = [slug for slug, n in days.items() if n >= MIN_DAYS]
    return sorted(ready, key=lambda s: -days[s])[:MAX_ROWS]


def pass_page(slug: str) -> str:
    return f"{SITE}/{slug}/passes"


def booking_link(slug: str, *, marker: str, project_id: str) -> str:
    """The city's pass page through Travelpayouts, so a sale earns us a share.

    Without both the partner ID and the Project ID it still opens the page.
    """
    page = pass_page(slug)
    if not (marker and project_id):
        return page
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "campaign_id": CAMPAIGN_ID, "marker": marker, "p": PROMO_ID, "trs": project_id, "u": page,
    })


def is_gocity_link(url: str) -> bool:
    parsed = urllib.parse.urlparse(str(url or ""))
    if parsed.netloc == "tp.media":
        return urllib.parse.parse_qs(parsed.query).get("p") == [PROMO_ID]
    return parsed.netloc == "gocity.com" or parsed.netloc.endswith(".gocity.com")


def plan_item(slug: str, link: str) -> dict:
    """The Booking Plan row. It names the pass kinds without promising one
    (they vary by city) and no price (it cannot be read)."""
    name = DESTINATIONS[slug][0]
    return {
        "label": PLAN_LABEL,
        "item": f"Go City pass for {name}: one pass, many top attractions",
        "reason": (
            "All-Inclusive (unlimited for set days) or Explorer (pick your attractions), "
            "depending on the city. Often cheaper than separate tickets if you visit several "
            "paid sights; compare today's prices."
        ),
        "url": link,
    }
