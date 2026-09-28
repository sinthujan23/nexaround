"""How a traveller gets from an airport to a town on the ground.

The client's rule for the journey after landing: a train if one runs, else a
bus, else another way (ferry, then car or taxi). The itinerary prompt used to
leave that to the model's guess, and the route planner's own `arrive_by` was a
guess too. This asks Google Directions, which answers from real timetables:
Barcelona airport to Andorra la Vella is the Andbus coach, 4 h 30 min, about
EUR 33, with no train at all.

One transit request usually settles it: `transit_mode=rail` is only a
preference, so when no train exists Google still returns the bus route, and
the vehicle types in the answer say which it is. Only when transit finds
nothing is the road asked for. Answers are cached for 30 days by rounded
coordinates, and every failure returns None, which leaves the prompt exactly
as it was before this existed.
"""
from __future__ import annotations

import json
import logging
import time

import httpx

from app.services import place_cache_service, telemetry

logger = logging.getLogger(__name__)

_URL = "https://maps.googleapis.com/maps/api/directions/json"
_TIMEOUT_S = 8.0
_CACHE_TTL = 30 * 24 * 3600      # timetables change slowly; which mode runs, rarely
_MISS_TTL = 24 * 3600            # nothing found, or Google failed: retry tomorrow
_MISS = "__none__"
_KEY_VERSION = "v1"

_RAIL = {
    "RAIL", "HEAVY_RAIL", "COMMUTER_TRAIN", "HIGH_SPEED_TRAIN", "LONG_DISTANCE_TRAIN",
    "METRO_RAIL", "SUBWAY", "MONORAIL",
}
_BUS = {"BUS", "INTERCITY_BUS", "TROLLEYBUS", "SHARE_TAXI"}
_FERRY = {"FERRY"}


def _classify(vehicle: str) -> str:
    v = (vehicle or "").upper()
    if v in _RAIL:
        return "train"
    if v == "TRAM":
        return "tram"
    if v in _BUS:
        return "bus"
    if v in _FERRY:
        return "ferry"
    return ""


def _departure_time() -> int:
    """Tomorrow 09:00 UTC: a working-day timetable, never a 3 a.m. gap."""
    now = int(time.time())
    return (now // 86400 + 1) * 86400 + 9 * 3600


def parse_transit(data: dict) -> dict | None:
    """The main mode of a Directions transit answer, or None.

    The main mode is the transit step that covers the most distance, so a short
    metro hop to the coach station does not turn a bus journey into a "train".
    """
    if not isinstance(data, dict) or data.get("status") != "OK":
        return None
    routes = data.get("routes") or []
    if not routes:
        return None
    route = routes[0]
    legs = route.get("legs") or []
    if not legs:
        return None
    leg = legs[0]
    main, main_m, lines = "", -1, []
    for step in leg.get("steps") or []:
        if step.get("travel_mode") != "TRANSIT":
            continue
        line = ((step.get("transit_details") or {}).get("line") or {})
        mode = _classify((line.get("vehicle") or {}).get("type", ""))
        metres = int(((step.get("distance") or {}).get("value")) or 0)
        name = str(line.get("short_name") or line.get("name") or "").strip()
        if name and name not in lines:
            lines.append(name)
        if mode and metres > main_m:
            main, main_m = mode, metres
    if not main:
        return None
    return {
        "mode": main,
        "duration_min": round(int((leg.get("duration") or {}).get("value") or 0) / 60),
        "distance_km": round(int((leg.get("distance") or {}).get("value") or 0) / 1000),
        "fare": str((route.get("fare") or {}).get("text") or "").strip(),
        "lines": lines[:3],
        "source": "Google Maps",
    }


def parse_driving(data: dict) -> dict | None:
    if not isinstance(data, dict) or data.get("status") != "OK":
        return None
    try:
        leg = data["routes"][0]["legs"][0]
    except (KeyError, IndexError, TypeError):
        return None
    return {
        "mode": "car",
        "duration_min": round(int((leg.get("duration") or {}).get("value") or 0) / 60),
        "distance_km": round(int((leg.get("distance") or {}).get("value") or 0) / 1000),
        "fare": "",
        "lines": [],
        "source": "Google Maps",
    }


def describe(route: dict | None) -> str:
    """"bus (Andbus), about 4 h 30 min, 206 km, fare about €33.00 per person"."""
    if not route:
        return ""
    mode = {"car": "car or taxi"}.get(route["mode"], route["mode"])
    lines = f" ({', '.join(route['lines'])})" if route.get("lines") else ""
    h, m = divmod(int(route.get("duration_min") or 0), 60)
    took = f"{h} h {m:02d} min" if h else f"{m} min"
    bits = [f"{mode}{lines}", f"about {took}"]
    if route.get("distance_km"):
        bits.append(f"{route['distance_km']} km")
    if route.get("fare"):
        bits.append(f"fare about {route['fare']} per person")
    return ", ".join(bits)


def _key(origin: tuple[float, float], dest: tuple[float, float]) -> str:
    return (
        f"ground:{_KEY_VERSION}:{origin[0]:.2f},{origin[1]:.2f}>"
        f"{dest[0]:.2f},{dest[1]:.2f}"
    )


async def _directions(client: httpx.AsyncClient, api_key: str, params: dict, op: str) -> dict:
    query = {**params, "key": api_key}
    async with telemetry.track("google_maps", f"directions:{op}", sku="directions") as t:
        resp = await client.get(_URL, params=query)
        t.upstream(resp)
    resp.raise_for_status()
    return resp.json()


async def best_route(
    origin: tuple[float, float] | None,
    dest: tuple[float, float] | None,
    api_key: str,
) -> dict | None:
    """Train, else bus, else ferry, else car — or None when nothing is known."""
    if not origin or not dest or not api_key:
        return None
    key = _key(origin, dest)
    try:
        cached = await place_cache_service.get_raw(key)
        if cached is not None:
            return None if cached == _MISS else json.loads(cached)
    except Exception:
        pass

    points = {
        "origin": f"{origin[0]:.5f},{origin[1]:.5f}",
        "destination": f"{dest[0]:.5f},{dest[1]:.5f}",
    }
    route = None
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT_S) as client:
            route = parse_transit(await _directions(
                client, api_key,
                {**points, "mode": "transit", "transit_mode": "rail",
                 "departure_time": _departure_time()},
                "odyssey_transfer_transit",
            ))
            if route is None:
                route = parse_driving(await _directions(
                    client, api_key, {**points, "mode": "driving"}, "odyssey_transfer_drive",
                ))
    except Exception as e:
        # A network or quota failure says nothing about the route: not cached.
        logger.warning("Ground route %s -> %s failed: %s", points["origin"], points["destination"], e)
        return None
    try:
        await place_cache_service.set_raw(
            key, json.dumps(route) if route else _MISS,
            ttl=_CACHE_TTL if route else _MISS_TTL,
        )
    except Exception:
        pass
    return route
