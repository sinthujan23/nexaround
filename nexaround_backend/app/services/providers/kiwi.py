"""Kiwi.com: a second flight-booking link, beside Aviasales, to compare.

Kiwi.com sells its own tickets, often combining airlines for a lower fare.
Through Travelpayouts it pays 3% of a booking; Aviasales pays about 1.1–1.3% of
the ticket. Only a link: Kiwi's data API needs 50k+ monthly users, and
kiwi.com answers our server with a "Client Challenge" page, so the fare on the
card stays Google's and Kiwi shows its own on its site.

Only "deep" search links count toward our statistics (Travelpayouts' help
article "Kiwi.com affiliate links"):

    kiwi.com/deep?from=DXB&to=BCN&departure=2026-11-15&return=2026-11-24
    kiwi.com/deep?from=DXB&to=BCN&departure=2026-11-15                one way
    kiwi.com/deep?multicity=CMB~MAD~2026-11-11/BCN~CMB~2026-11-17     into one
                                                                      city, home
                                                                      from another

The help article builds multi-city paths from Kiwi's place slugs
("riga-latvia"). Airport codes, as used here, are the same codes the
one-way/return form takes. Travelpayouts credits Kiwi to campaign 111, promo
4136: tp.media turns the link into kiwi.com/deep?…&affilid=travelpayoutsdeeplink__<click>-781739
and keeps every parameter (checked 2026-09-30). Bookings count on the mobile
website, not in Kiwi's app; our links open the browser.
"""
from __future__ import annotations

import urllib.parse

from app.services.providers import aviasales

_AFFILIATE_REDIRECT = "https://tp.media/r"
CAMPAIGN_ID = "111"
PROMO_ID = "4136"
DEEP_PAGE = "https://www.kiwi.com/deep"

# Multi-city links ("into Sydney, home from Melbourne") are held back until
# one is seen opening right on a phone: Travelpayouts' article writes them
# with place slugs, and ours use airport codes. Round-trip and one-way links
# follow the article exactly and are on; Kiwi went live on that
# basis (2026-09-30); set True once the multi-city link is checked.
MULTICITY_READY = False


def deep_url(legs, *, adults=1, today=None) -> str:
    """Kiwi's deep search for these legs, or "" when they can't be searched.

    The same legs and the same checks as the Aviasales link
    (`aviasales.searchable`), so the two buttons always search the same trip.
    """
    parts = aviasales.searchable(legs, today)
    if not parts:
        return ""
    pax = aviasales.passengers(adults)
    (origin, dest, out), rest = parts[0], parts[1:]
    if rest and not (rest[0][0] == dest and rest[0][1] == origin):
        if not MULTICITY_READY:
            return ""
        home_from, home_to, back = rest[0]
        query = {"multicity": f"{origin}~{dest}~{out:%Y-%m-%d}/{home_from}~{home_to}~{back:%Y-%m-%d}"}
    else:
        query = {"from": origin, "to": dest, "departure": f"{out:%Y-%m-%d}"}
        if rest:
            query["return"] = f"{rest[0][2]:%Y-%m-%d}"
    if pax > 1:
        query["adults"] = str(pax)
    # "~" and "/" stay readable in the multi-city path, as Kiwi writes them.
    return DEEP_PAGE + "?" + urllib.parse.urlencode(query, safe="~/")


def booking_link(url: str, *, marker: str, project_id: str) -> str:
    """The deep search through Travelpayouts, so a booking earns us a share.

    Without both the partner ID and the Project ID it still opens the search.
    """
    if not (marker and project_id):
        return url
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "campaign_id": CAMPAIGN_ID, "marker": marker, "p": PROMO_ID, "trs": project_id, "u": url,
    })


def is_kiwi_link(url: str) -> bool:
    parsed = urllib.parse.urlparse(str(url or ""))
    if parsed.netloc == "tp.media":
        return urllib.parse.parse_qs(parsed.query).get("p") == [PROMO_ID]
    return parsed.netloc == "kiwi.com" or parsed.netloc.endswith(".kiwi.com")


def plan_item(label: str, legs, link: str) -> dict:
    """The Booking Plan row, next to the Aviasales one and under its label."""
    return {
        "label": label,
        "item": f"Compare on Kiwi.com: {aviasales.trip_text(legs)}",
        "reason": "Kiwi.com sells its own fares, often combining airlines for a lower price.",
        "url": link,
    }
