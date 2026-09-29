"""Klook: a "Things to do in <city>" link where WeGoTrip sells nothing.

WeGoTrip has no tickets in Sri Lanka, the Maldives or most of India, which are
our biggest markets. Klook does: Colombo, Sigiriya and Kandy tours, the Kandy
to Ella train, Yala safaris, Alleppey houseboats, Malé island hopping. It
sells mostly tours and day trips, not entry tickets.

Only a link, never a product or a price. klook.com answers our server with a
Cloudflare challenge or a 403 page ("your IP address might be the same as an
Internet bot"), so its catalogue cannot be read to match a stop, or even to
look up its internal city pages (/destination/c202-colombo/). The link is
Klook's own search for the city, which needs neither.

Travelpayouts credits Klook sales to campaign 137, promo 4110: what its Links
API returned on 2026-09-29. The link passes through
affiliate.klook.com/redirect (aid=api|13694|<click>-781739) and keeps the
page, the same as the dashboard's short link klook.tp.st/Exi8JD1b.
"""
from __future__ import annotations

import urllib.parse

_AFFILIATE_REDIRECT = "https://tp.media/r"
CAMPAIGN_ID = "137"
PROMO_ID = "4110"

# No language in the path: Klook serves each traveller's own language and
# currency, as it does for the dashboard link's bare klook.com.
SEARCH_PAGE = "https://www.klook.com/search/result/"

# Booking Plan rows, at most; the longest stays first.
MAX_ROWS = 3

PLAN_LABEL = "BOOK CLOSER TO TRAVEL"


def search_url(query: str) -> str:
    return SEARCH_PAGE + "?" + urllib.parse.urlencode({"query": query.strip()})


def booking_link(query: str, *, marker: str, project_id: str) -> str:
    """Klook's search for `query`, through Travelpayouts so a sale earns us a share.

    Without both the partner ID and the Project ID it still opens the search.
    """
    page = search_url(query)
    if not (marker and project_id):
        return page
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "campaign_id": CAMPAIGN_ID, "marker": marker, "p": PROMO_ID, "trs": project_id, "u": page,
    })


def is_klook_link(url: str) -> bool:
    parsed = urllib.parse.urlparse(str(url or ""))
    if parsed.netloc == "tp.media":
        return urllib.parse.parse_qs(parsed.query).get("p") == [PROMO_ID]
    return parsed.netloc.endswith("klook.com")


def cities_to_link(legs: list, covered: set[str]) -> list[str]:
    """The plan's cities WeGoTrip has nothing in, longest stay first.

    `covered` holds the cities WeGoTrip sells something in. A city visited on
    two legs is linked once.
    """
    stays: dict[str, int] = {}
    order: list[str] = []
    for leg in legs or []:
        if not isinstance(leg, dict):
            continue
        city = str(leg.get("city") or "").strip()
        if not city or city in covered:
            continue
        try:
            nights = int(leg.get("end_day") or 0) - int(leg.get("start_day") or 0) + 1
        except (TypeError, ValueError):
            nights = 0
        if city not in stays:
            order.append(city)
            stays[city] = 0
        stays[city] += max(nights, 0)
    return sorted(order, key=lambda c: -stays[c])[:MAX_ROWS]


def plan_item(city: str, link: str) -> dict:
    """The Booking Plan row. Its first word is not a brand another provider
    replaces rows by ("WeGoTrip", "Airalo", "GetTransfer")."""
    return {
        "label": PLAN_LABEL,
        "item": f"Things to do in {city} on Klook",
        "reason": "Tours, day trips and tickets. Book the popular ones a few days ahead.",
        "url": link,
    }
