"""GetTransfer: real, bookable prices for a car between two points.

Measured against the live API on 2026-09-25, which is what the cache key is
built from: the price is per car (one to three travellers pay the same), the
time of day does not change it, and only peak dates do — Paris CDG on 24 Dec
was 17% dearer than on 10 Nov. GetTransfer re-prices nightly, so an answer
is good for a day. A route it cannot serve comes back as HTTP 422, which is
remembered as "nothing here" rather than retried.
"""
from __future__ import annotations

import datetime as dt
import logging
import math
import re
import urllib.parse
from typing import Optional

from app.services.providers import base, config

logger = logging.getLogger(__name__)

API_URL = "https://gettransfer.com/api/route_info"
FRESH_TTL_S = 24 * 3600
STALE_TTL_S = 3 * 86400
EMPTY_TTL_S = 6 * 3600
TIMEOUT_S = 3.0

# Seats in the smaller cars GetTransfer offers. A party this size or smaller
# is quoted as three, so every such party shares one cached answer.
SEATS_PER_CAR = 3

CLASS_LABELS = {
    "economy": "Economy car", "comfort": "Comfort car", "business": "Business car",
    "premium": "Premium car", "limousine": "Limousine", "suv": "SUV", "van": "Van",
    "business_van": "Business van", "minibus": "Minibus", "bus": "Coach",
}

_MONEY = re.compile(r"[\d,]+(?:\.\d+)?")


def _usd(text) -> Optional[float]:
    m = _MONEY.search(str(text or ""))
    try:
        return float(m.group(0).replace(",", "")) if m else None
    except ValueError:
        return None


def parse_route(body) -> Optional[dict]:
    """{"prices": {class: {"now": usd|None, "min": usd|None}}, "km", "minutes"}.

    `now` (`book_now`) is a price the traveller can book at that moment; `min`
    is GetTransfer's lowest driver offer for the class, which is what a car
    usually goes for where no instant price is listed. Copenhagen airport, for
    one: only a business van was instantly bookable (USD 115–173) while an
    economy car's offer sat at USD 43 — close to a real Copenhagen taxi.
    """
    data = (body or {}).get("data") or {}
    prices = {}
    for cls, offer in (data.get("prices") or {}).items():
        if not isinstance(offer, dict):
            continue
        now, low = _usd(offer.get("book_now")), _usd(offer.get("min"))
        if now or low:
            prices[cls] = {"now": now, "min": low}
    if not prices:
        return None
    return {"prices": prices, "km": data.get("distance"), "minutes": data.get("duration")}


# Which vehicles a party of up to N is priced in. A solo traveller is never
# quoted a van or a limousine because that happened to be the one instant price.
_CLASSES_BY_SEATS = (
    (3, ("economy", "comfort", "business")),
    (6, ("van", "suv", "business_van")),
    (19, ("minibus",)),
    (50, ("bus",)),
)


def pick(prices: dict, travelers: int) -> Optional[tuple[str, float, bool]]:
    """(class, usd, bookable) for the right-sized vehicle, or None.

    An instantly bookable price wins; failing that, the class's typical offer.
    """
    for seats, classes in _CLASSES_BY_SEATS:
        if travelers > seats:
            continue
        options = {c: prices[c] for c in classes if c in prices}
        now = {c: p["now"] for c, p in options.items() if p.get("now")}
        if now:
            cls = min(now, key=now.get)
            return cls, now[cls], True
        low = {c: p["min"] for c, p in options.items() if p.get("min")}
        if low:
            cls = min(low, key=low.get)
            return cls, low[cls], False
        return None
    return None


def query_date(date: str, today: Optional[dt.date] = None) -> str:
    """The trip's date, or two weeks out when it is missing or already past.

    GetTransfer only prices pickups at least six hours ahead; a price for a
    near date is the same except on peak days, so it is still the honest one.
    """
    today = today or dt.date.today()
    try:
        day = dt.date.fromisoformat(str(date)[:10])
    except ValueError:
        day = None
    if day is None or day <= today:
        day = today + dt.timedelta(days=14)
    return day.isoformat()


async def _route(origin: tuple, dest: tuple, date: str, pax: int) -> Optional[dict]:
    token = await config.setting(config.GETTRANSFER_API_TOKEN)
    got = await base.fetch(
        "gettransfer", "route_info",
        url=API_URL,
        params=[
            ("points[]", f"{origin[0]:.5f},{origin[1]:.5f}"),
            ("points[]", f"{dest[0]:.5f},{dest[1]:.5f}"),
            ("with_prices", "true"), ("pax", str(pax)),
            ("date_to", f"{date}T12:00:00"),
            ("currency", "USD"), ("distance_unit", "km"),
        ],
        headers={"X-ACCESS-TOKEN": token} if token else None,
        # ~1 km cells: 300 m moved a Colombo fare by one dollar, a Paris one not at all.
        cache_params={
            "from": [round(origin[0], 2), round(origin[1], 2)],
            "to": [round(dest[0], 2), round(dest[1], 2)],
            "date": date, "pax": pax, "v": 2,
        },
        fresh_ttl=FRESH_TTL_S, stale_ttl=STALE_TTL_S, empty_ttl=EMPTY_TTL_S,
        timeout_s=TIMEOUT_S, transform=parse_route,
        sku="gettransfer_route_info",
    )
    return got.data


async def quote(origin: tuple, dest: tuple, date: str, travelers: int) -> Optional[dict]:
    """The cheapest right-sized way to move the whole party by car, in USD, or None.

    {"usd_total", "usd_each", "cars", "class", "bookable", "km", "minutes"}.
    A party bigger than one car is first asked for as itself (a van or SUV);
    where nothing that size is offered, as several economy-size cars.
    """
    travelers = max(1, int(travelers or 1))
    day = query_date(date)
    got = await _route(origin, dest, day, max(travelers, SEATS_PER_CAR))
    choice = pick(got["prices"], travelers) if got else None
    cars = 1
    if choice is None and travelers > SEATS_PER_CAR:
        got = await _route(origin, dest, day, SEATS_PER_CAR)
        choice = pick(got["prices"], SEATS_PER_CAR) if got else None
        cars = math.ceil(travelers / SEATS_PER_CAR)
    if choice is None:
        return None
    cls, usd, bookable = choice
    return {
        "usd_total": round(usd * cars, 2), "usd_each": usd, "cars": cars, "class": cls,
        "bookable": bookable, "km": got.get("km"), "minutes": got.get("minutes"),
    }


# Booking links. GetTransfer's program in Travelpayouts is promo 4439 (the
# example link on Travelpayouts' own GetTransfer offer page). Verified
# 2026-09-29: tp.media/r?marker=781739&trs=577812&p=4439&u=<page> lands on
# gettransfer.com with sub_id=<click>-781739 and the travelpayouts utm tags,
# the same as the dashboard's short link, and it keeps a deep page. No API key
# is involved: this is the Airalo pattern.
PROMO_ID = "4439"
_AFFILIATE_REDIRECT = "https://tp.media/r"
BOOKING_PAGE = "https://gettransfer.com/en/transfers/new"


def booking_link(car_class: str, *, marker: str, project_id: str) -> str:
    """GetTransfer's booking page with the quoted car class, credited to us.

    Pickup and drop-off are typed on GetTransfer's page: its website link has
    no documented way to pre-fill them (only its API does). Without both the
    partner ID and the Project ID the link still opens the page; it just
    earns nothing.
    """
    page = BOOKING_PAGE + "?" + urllib.parse.urlencode({
        "transfer_type": "route",
        "transport_type_ids[]": car_class if car_class in CLASS_LABELS else "economy",
    })
    if not (marker and project_id):
        return page
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "marker": marker, "trs": project_id, "p": PROMO_ID, "u": page,
    })


def duration_text(minutes) -> str:
    """"about 37 min", "about 2 h 40 min", or "" when unknown."""
    return _duration(minutes)


def _duration(minutes) -> str:
    try:
        m = int(minutes)
    except (TypeError, ValueError):
        return ""
    if m < 60:
        return f"about {m} min"
    h, rest = divmod(m, 60)
    return f"about {h} h" + (f" {rest} min" if rest >= 10 else "")


def basis(q: dict, travelers: int, rate: float, currency: str) -> str:
    """"Economy car for 2 travellers · 40 km, about 1 h" and the like."""
    from app.services.providers.money import format_amount

    label = CLASS_LABELS.get(q["class"], q["class"].replace("_", " ").title())
    who = f"{travelers} traveller{'s' if travelers != 1 else ''}"
    if q["cars"] > 1:
        each = format_amount(currency, q["usd_each"] * rate)
        what = f"{q['cars']} {label.lower()}s ({each} each) for {who}"
    else:
        what = f"{label} for {who}"
    if not q.get("bookable", True):
        what += " (typical price)"
    trip = " · ".join(x for x in (
        f"{q['km']:g} km" if isinstance(q.get("km"), (int, float)) else "",
        _duration(q.get("minutes")),
    ) if x)
    return f"{what} · {trip}" if trip else what
