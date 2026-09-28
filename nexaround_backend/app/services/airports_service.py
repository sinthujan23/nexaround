"""Airports a traveller can fly to, from a bundled OurAirports extract.

`app/data/airports.json` holds every large or medium airport with scheduled
passenger service and an IATA code, about 3,200 of them (regenerate with
`app/scripts/refresh_airports.py`). It answers questions the live lookups
cannot answer cheaply or at all:

* does a country have any airport of its own? Andorra, Liechtenstein, Monaco,
  San Marino and the Vatican do not, and a trip there must fly into a
  neighbour (Andorra: Toulouse, Barcelona, Girona);
* which airports are nearest a point, for the planner's "Travelling from";
* where an IATA code is and which country it is in, with no Places call.

Everything here is a pure in-memory lookup: it never raises, and an unknown
code or point simply returns nothing.
"""
from __future__ import annotations

import functools
import json
import logging
import math
import pathlib
import re
from dataclasses import dataclass

logger = logging.getLogger(__name__)

_DATA = pathlib.Path(__file__).resolve().parents[1] / "data" / "airports.json"


@dataclass(frozen=True)
class Airport:
    iata: str
    name: str
    city: str
    country: str        # ISO 3166-1 alpha-2
    latitude: float
    longitude: float
    large: bool

    def as_dict(self, distance_km: float | None = None) -> dict:
        out = {
            "iata": self.iata,
            "name": self.name,
            "city": self.city,
            "country_code": self.country,
            "latitude": self.latitude,
            "longitude": self.longitude,
        }
        if distance_km is not None:
            out["distance_km"] = round(distance_km)
        return out


def _clean_city(raw: str) -> str:
    """OurAirports writes "Dubai(Jebel Ali)" and "Toulouse/Blagnac": keep "Dubai"."""
    city = re.split(r"[(/]", raw or "", maxsplit=1)[0].strip()
    return city or (raw or "").strip()


@functools.lru_cache(maxsize=1)
def _airports() -> dict[str, Airport]:
    try:
        payload = json.loads(_DATA.read_text(encoding="utf-8"))
    except Exception as e:  # a missing file must not take generation down
        logger.error("Airport data unavailable (%s): %s", _DATA, e)
        return {}
    table: dict[str, Airport] = {}
    for iata, name, city, country, lat, lng, kind in payload.get("airports") or []:
        table[iata] = Airport(
            iata=iata, name=name, city=_clean_city(city), country=country,
            latitude=float(lat), longitude=float(lng), large=(kind == "L"),
        )
    return table


@functools.lru_cache(maxsize=1)
def _countries() -> frozenset[str]:
    return frozenset(a.country for a in _airports().values())


def _km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p = math.pi / 180
    a = (
        math.sin((lat2 - lat1) * p / 2) ** 2
        + math.cos(lat1 * p) * math.cos(lat2 * p) * math.sin((lng2 - lng1) * p / 2) ** 2
    )
    return 12742 * math.asin(math.sqrt(a))


def get(iata: str | None) -> Airport | None:
    """The airport behind a 3-letter code, or None when it has no scheduled flights."""
    return _airports().get(str(iata or "").strip().upper())


def has_scheduled_airport(country_code: str | None) -> bool:
    """Whether a country has at least one airport with scheduled flights.

    An unknown or empty code answers True: only a real country we positively
    know to have none may send the traveller across a border to land.
    """
    from app.services.ride_apps_service import COUNTRY_NAMES  # ISO 3166-1 table

    code = str(country_code or "").strip().upper()
    if code not in COUNTRY_NAMES or not _airports():
        return True
    return code in _countries()


def nearest(
    latitude: float | None,
    longitude: float | None,
    *,
    limit: int = 3,
    max_km: float = 400.0,
) -> list[tuple[Airport, float]]:
    """The airports nearest a point, closest first, as (airport, km).

    Large airports only, unless there is none within `max_km` — then medium
    ones, so a remote point still gets its regional airport. Raw distance
    alone would pick Andorra's tiny La Seu d'Urgell strip over Toulouse and
    Barcelona, which is not where anyone flying in from abroad lands.
    """
    if latitude is None or longitude is None:
        return []
    try:
        lat, lng = float(latitude), float(longitude)
    except (TypeError, ValueError):
        return []
    scored = [(a, _km(lat, lng, a.latitude, a.longitude)) for a in _airports().values()]
    scored = [(a, km) for a, km in scored if km <= max_km]
    large = [(a, km) for a, km in scored if a.large]
    pool = large or scored
    pool.sort(key=lambda pair: pair[1])
    return pool[: max(int(limit), 1)]
