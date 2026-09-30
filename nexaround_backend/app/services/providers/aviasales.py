"""Aviasales: a "Book on Aviasales" link for each flight option, credited to us.

Only a link, never a price. Aviasales' data API (the Travelpayouts token) holds
fares other people found in the last few days, not live ones. Replaying 31
real Odyssey trips on 2026-09-29, it had the exact dates for 4 and anything
within three days for 11, often far below Google's fare (two stops, small
ticket sites). So the fare on the card stays Google's, and this opens
Aviasales' own live search for the same flights.

Search paths, verified 2026-09-29 in a headless browser (its search header
showed each one; the results themselves sit behind a captcha there):

    DXB1511BCN1               one way, 15 Nov, 1 adult
    DXB1511BCN24112           round trip, back 24 Nov, 2 adults
    CMB1110MAD-BCN1710CMB1    into Madrid, home from Barcelona
    DXB1511BCN2411c2          business; "w" premium economy, "f" first

The class letter goes before the passenger count. Dates carry no year:
Aviasales takes the next such day, which is the trip's for any plan made
within a year of flying.
"""
from __future__ import annotations

import datetime as dt
import re
import urllib.parse
from typing import Optional

# Aviasales' program in Travelpayouts. Verified 2026-09-29:
# tp.media/r?marker=781739&trs=577812&p=4114&u=<search> lands on that search
# with marker=781739.<click id>, the same as the dashboard's short link
# (aviasales.tp.st/…); an unknown promo number gets a 404.
PROMO_ID = "4114"
_AFFILIATE_REDIRECT = "https://tp.media/r"
SEARCH_PAGE = "https://www.aviasales.com/search/"

# Aviasales' own limit on one booking.
MAX_PASSENGERS = 9

_IATA = re.compile(r"^[A-Z]{3}$")
_ARROW = re.compile(r"\s*(?:→|->)\s*")
_CLASS_LETTERS = (("premium", "w"), ("business", "c"), ("first", "f"))


def _code(value) -> str:
    """The first airport of "DWC,DXB", or "" for anything not an IATA code."""
    first = str(value or "").split(",")[0].strip().upper()
    return first if _IATA.match(first) else ""


def _today() -> dt.date:
    return dt.date.today()


def _day(value) -> Optional[dt.date]:
    try:
        return dt.date.fromisoformat(str(value or "")[:10])
    except ValueError:
        return None


def _ends(route) -> tuple[str, str]:
    """("CMB", "MAD") from "CMB → MAD"; ("", "") when it names no airports."""
    parts = [p for p in _ARROW.split(str(route or "")) if p.strip()]
    if len(parts) < 2:
        return "", ""
    return _code(parts[0]), _code(parts[-1])


def class_letter(travel_class) -> str:
    """"" for economy (Aviasales' default), else its one-letter cabin code."""
    cabin = str(travel_class or "").lower()
    for word, letter in _CLASS_LETTERS:
        if word in cabin:
            return letter
    return ""


def legs_for(option: dict, flights: dict) -> list[tuple[str, str, str]]:
    """[(origin, destination, "YYYY-MM-DD"), ...] this option flies: one leg or two.

    Read from the option's own legs first (the airports on the ticket), then
    its route text, then the plan's gateways. A fare covering the way home
    with no date for it gives [] rather than a one-way search.
    """
    out = option.get("outbound") if isinstance(option.get("outbound"), dict) else {}
    back = option.get("return") if isinstance(option.get("return"), dict) else {}
    arrival = flights.get("arrival_airport") if isinstance(flights.get("arrival_airport"), dict) else {}
    departure = flights.get("departure_airport") if isinstance(flights.get("departure_airport"), dict) else {}

    route_from, route_to = _ends(option.get("route"))
    origin = _code(out.get("origin")) or route_from or _code(flights.get("origin_airport"))
    dest = _code(out.get("destination")) or route_to or _code(arrival.get("iata"))
    legs = [(origin, dest, str(out.get("date") or option.get("outbound_date") or ""))]

    trip = option.get("trip_type") or flights.get("trip_type")
    if trip == "one_way":
        return legs
    home_from, home_to = _ends(option.get("return_route"))
    back_date = str(back.get("date") or option.get("return_date") or "")
    if not back_date:
        return []
    legs.append((
        _code(back.get("origin")) or home_from or _code(departure.get("iata")) or dest,
        _code(back.get("destination")) or home_to or origin,
        back_date,
    ))
    return legs


def searchable(legs, today: Optional[dt.date] = None) -> list[tuple[str, str, dt.date]]:
    """The legs as (origin, destination, date) a flight search can take, or [].

    One leg or two. A leg without both airports, to itself, or dated before
    today gives [], and so does a way home dated before the way out. Shared by
    every flight partner's link (Kiwi.com's too), so they agree on what can
    be searched.
    """
    if not legs or len(legs) > 2:
        return []
    today = today or _today()
    parts = []
    for origin, dest, date in legs:
        origin, dest, day = _code(origin), _code(dest), _day(date)
        if not (origin and dest and day) or origin == dest or day < today:
            return []
        parts.append((origin, dest, day))
    if len(parts) == 2 and parts[1][2] < parts[0][2]:
        return []
    return parts


def passengers(adults) -> int:
    try:
        return min(max(int(adults or 1), 1), MAX_PASSENGERS)
    except (TypeError, ValueError):
        return 1


def search_path(legs, *, adults=1, travel_class="", today: Optional[dt.date] = None) -> str:
    """Aviasales' search path for these legs, or "" when they can't be searched.

    Two legs that retrace each other are a round trip; any other pair is
    searched as the two flights they are ("into Madrid, home from Barcelona").
    """
    parts = searchable(legs, today)
    if not parts:
        return ""
    origin, dest, out = parts[0]
    path = f"{origin}{out:%d%m}{dest}"
    if len(parts) == 2:
        home_from, home_to, back = parts[1]
        if home_from == dest and home_to == origin:
            path += f"{back:%d%m}"
        else:
            path += f"-{home_from}{back:%d%m}{home_to}"
    return f"{path}{class_letter(travel_class)}{passengers(adults)}"


def trip_text(legs) -> str:
    """"CMB → BUD", "CMB → BUD and back", or "CMB → MAD, BCN → CMB"."""
    if not legs:
        return ""
    (origin, dest, _), rest = legs[0], legs[1:]
    first = f"{_code(origin)} → {_code(dest)}"
    if not rest:
        return first
    home_from, home_to = _code(rest[0][0]), _code(rest[0][1])
    if home_from == _code(dest) and home_to == _code(origin):
        return f"{first} and back"
    return f"{first}, {home_from} → {home_to}"


def booking_link(path: str, *, marker: str, project_id: str) -> str:
    """The search, through Travelpayouts so a ticket bought there earns us a share.

    Without both the partner ID and the Project ID the link still opens the
    search; it just earns nothing.
    """
    page = SEARCH_PAGE + path
    if not (marker and project_id):
        return page
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "marker": marker, "trs": project_id, "p": PROMO_ID, "u": page,
    })
