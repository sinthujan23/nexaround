"""Real prices from the travel-data providers, laid onto a finished Odyssey.

`start()` runs as soon as the plan's airports are final — just before Gemini
writes the itinerary, which takes 35–63 s — and `finish()` only after it. The
fetches take well under a second, so no plan waits for them.

Each provider follows its switch in the admin panel (`config.mode`):

    off     not called
    shadow  fetched, and what it *would* have changed is recorded in the plan's
            `provider_audit` block; the traveller sees nothing new
    live    applied, through fields every app build already shows. GetTransfer
            is information only: the airport stop keeps its own fare and gains
            a "Private car: USD 71 with GetTransfer" line on its tip. Airalo
            adds the "Connectivity & SIM" line and its partner card. Aviasales
            adds a search link to each flight option and points the Booking
            Plan's flight row at it; its fares are never used. WeGoTrip adds
            a ticket line and link to the sights it sells tickets for, and
            Klook a "Things to do in <city>" row for the cities it does not.
            Go City adds a sightseeing-pass row for its big cities,
            Kiwi.com a second flight link beside Aviasales', and EKTA a
            travel-insurance row and button on trips to another country

Nothing here may cost a plan: every failure leaves the plan as Gemini wrote it.
Prices are shown, never added to the budget, which is computed before this
runs and leaves transport out of its food/activities split anyway.
"""
from __future__ import annotations

import asyncio
import logging
import re
import time
from dataclasses import dataclass, field
from typing import Optional

from app.services import airports_service
from app.services.providers import airalo, aviasales, config, ekta, gettransfer, gocity, kiwi, klook, wegotrip
from app.services.providers.money import format_amount, format_range, usd_rate

logger = logging.getLogger(__name__)

# The longest `finish()` will wait for anything still in flight. The fetches
# started half a minute earlier; this only bounds a provider that hung.
FINISH_WAIT_S = 8.0

# Nearer than this, the airport is in town and there is no transfer to price.
MIN_TRANSFER_KM = 3.0


@dataclass
class Transfer:
    """One airport ride to price: "arrival" (airport → first city) or "departure"."""
    kind: str
    origin: tuple
    dest: tuple
    date: str
    label: str
    # For GetTransfer's booking form: the airport's full name, the city, and
    # which leg's hotel is the other end (first leg in, last leg out).
    airport: str = ""
    city: str = ""
    leg_index: int = 0


@dataclass
class Pending:
    modes: dict
    tasks: dict = field(default_factory=dict)
    transfers: dict = field(default_factory=dict)
    started: float = field(default_factory=time.perf_counter)
    esim_country: str = ""
    # The plan's city legs (the generator's own dicts: their days are
    # realigned to the itinerary before `finish()` reads them) and country.
    legs: list = field(default_factory=list)
    country: str = ""
    # Home is in another country than the trip: the travel-insurance offer.
    international: bool = False


async def start(
    *,
    transfers: list[Transfer],
    country_name: str,
    country_code: str,
    days: int,
    travelers: int,
    legs: Optional[list[dict]] = None,
    international: bool = False,
) -> Optional[Pending]:
    """Begin every fetch this plan's switches allow. None when all are off."""
    try:
        modes = {p: await config.mode(p) for p in (
            "gettransfer", "airalo", "aviasales", "wegotrip", "klook", "gocity", "kiwi", "ekta",
        )}
    except Exception as e:
        logger.warning("providers: could not read switches: %s", e)
        return None
    if all(m == config.OFF for m in modes.values()):
        return None

    pending = Pending(modes=modes, international=international)
    if modes["gettransfer"] != config.OFF:
        for t in transfers:
            pending.transfers[t.kind] = t
            pending.tasks[f"gettransfer:{t.kind}"] = asyncio.create_task(
                _timed(gettransfer.quote(t.origin, t.dest, t.date, travelers))
            )
    if modes["airalo"] != config.OFF and (country_name or country_code):
        pending.esim_country = country_name or country_code
        pending.tasks["airalo"] = asyncio.create_task(
            _timed(airalo.offer_for(country_name, country_code, days))
        )
    cities = [str(leg.get("city") or "") for leg in legs or [] if isinstance(leg, dict) and leg.get("city")]
    if cities and any(modes[p] != config.OFF for p in ("wegotrip", "klook", "gocity")):
        pending.legs, pending.country = list(legs or []), country_name
    if modes["wegotrip"] != config.OFF and cities:
        pending.tasks["wegotrip"] = asyncio.create_task(
            _timed(wegotrip.catalogue_for(cities, country_name))
        )
    return pending


async def _timed(coro):
    t0 = time.perf_counter()
    try:
        result = await coro
    except Exception as e:  # never let a provider surface into the plan
        logger.warning("providers: fetch failed: %s", e)
        result = None
    return result, int((time.perf_counter() - t0) * 1000)


async def finish(
    pending: Optional[Pending],
    day_items: list[dict],
    meta: dict,
    *,
    currency: str,
    travelers: int,
) -> None:
    """Apply (live) or record (shadow) what the providers returned. Never raises."""
    if pending is None:
        return
    try:
        await _finish(pending, day_items, meta, currency=currency, travelers=travelers)
    except Exception as e:
        logger.warning("providers: could not apply results: %s", e)


async def _finish(pending: Pending, day_items, meta, *, currency: str, travelers: int) -> None:
    waited_from = time.perf_counter()
    if pending.tasks:
        await asyncio.wait(pending.tasks.values(), timeout=FINISH_WAIT_S)
    waited_ms = int((time.perf_counter() - waited_from) * 1000)

    def result(name):
        task = pending.tasks.get(name)
        if task is None or not task.done() or task.cancelled():
            if task is not None and not task.done():
                task.cancel()
            return None, None
        return task.result()

    rate = await usd_rate(currency)
    audit: dict = {"waited_ms": waited_ms, "currency": currency.upper()}

    if pending.modes["gettransfer"] != config.OFF:
        live = pending.modes["gettransfer"] == config.LIVE
        entry: dict = {"mode": pending.modes["gettransfer"]}
        marker = await config.setting(config.TRAVELPAYOUTS_MARKER)
        project_id = await config.setting(config.TRAVELPAYOUTS_PROJECT_ID)

        def link_for(car_class: str, transfer: Optional[Transfer] = None) -> str:
            """The booking page with the ride filled in: the airport one end,
            the plan's hotel for that city the other (or the city itself)."""
            if transfer is None:
                return gettransfer.booking_link(car_class, marker=marker, project_id=project_id)
            town = _hotel_for_leg(meta, transfer.leg_index, transfer.city) or transfer.city
            airport = transfer.airport or transfer.label.split(" → ")[0]
            inbound = transfer.kind == "arrival"
            return gettransfer.booking_link(
                car_class, marker=marker, project_id=project_id,
                from_name=airport if inbound else town,
                to_name=town if inbound else airport,
            )

        for kind, transfer in pending.transfers.items():
            q, ms = result(f"gettransfer:{kind}")
            entry[kind] = _apply_transfer(
                kind, transfer, q, ms, day_items,
                live=live, rate=rate, currency=currency, travelers=travelers,
                link_for=link_for,
            )
        audit["gettransfer"] = entry
        # One tappable row in the Booking Plan, which every app build opens.
        shown = [(k, e) for k, e in entry.items() if isinstance(e, dict) and e.get("applied")]
        if live and shown:
            first_kind, first = shown[0]
            transfer_link = link_for(str(first.get("car_class") or ""), pending.transfers.get(first_kind))
            _add_plan_item(meta, {
                "label": "BOOK CLOSER TO TRAVEL",
                "item": f"GetTransfer private car: {first['route']}, {first['amount']} one way",
                "reason": "Optional. Book once your flight times are fixed.",
                "url": transfer_link,
            })
            _add_partner(meta, "GetTransfer Airport Car", "transfer", transfer_link)

    if pending.modes["airalo"] != config.OFF:
        live = pending.modes["airalo"] == config.LIVE
        offer, ms = result("airalo")
        entry = {"mode": pending.modes["airalo"], "country": pending.esim_country, "ms": ms}
        if offer and rate:
            line = airalo.connectivity_line(offer, rate, currency)
            entry.update(cheapest=offer["cheapest"], roomy=offer["roomy"], line=line, applied=False)
            link = airalo.booking_link(
                offer["slug"],
                marker=await config.setting(config.TRAVELPAYOUTS_MARKER),
                project_id=await config.setting(config.TRAVELPAYOUTS_PROJECT_ID),
            )
            entry["link"] = link
            if live:
                info = meta.setdefault("practical_info", {})
                existing = str(info.get("connectivity") or "").strip()
                info["connectivity"] = f"{existing} {line}".strip() if existing else line
                # The button under that text (app ≥ the release carrying it;
                # older builds ignore both keys).
                info["connectivity_url"] = link
                info["connectivity_cta"] = airalo.button_label(offer, rate, currency)
                _add_partner(meta, airalo.PARTNER_NAME, airalo.PARTNER_TYPE, link)
                _add_plan_item(meta, airalo.plan_item(offer, rate, currency, link))
                entry["applied"] = True
        else:
            entry["none"] = "no rate" if offer else "no plan for this country or trip length"
        audit["airalo"] = entry

    if pending.modes.get("wegotrip", config.OFF) != config.OFF and "wegotrip" in pending.tasks:
        catalogue, ms = result("wegotrip")
        audit["wegotrip"] = await _apply_tickets(
            pending, catalogue or {}, day_items, meta,
            live=pending.modes["wegotrip"] == config.LIVE, rate=rate, currency=currency,
            marker=await config.setting(config.TRAVELPAYOUTS_MARKER),
            project_id=await config.setting(config.TRAVELPAYOUTS_PROJECT_ID),
        )
        audit["wegotrip"]["ms"] = ms

    if pending.modes.get("klook", config.OFF) != config.OFF and pending.legs:
        tickets = audit.get("wegotrip") or {}
        audit["klook"] = _apply_klook(
            meta, pending,
            # Cities where WeGoTrip put a ticket or tour on a stop. Selling
            # something there is not enough: in Oslo, Bergen and Mumbai it has
            # only general city audio walks, which match no stop, and those
            # cities got neither partner (user's Norway and India plans,
            # 2026-09-29/30). With WeGoTrip off or in shadow, every city
            # gets its Klook row.
            covered={
                m.get("city") for m in tickets.get("matched") or []
            } if tickets.get("mode") == config.LIVE else set(),
            live=pending.modes["klook"] == config.LIVE,
            marker=await config.setting(config.TRAVELPAYOUTS_MARKER),
            project_id=await config.setting(config.TRAVELPAYOUTS_PROJECT_ID),
        )

    if pending.modes.get("gocity", config.OFF) != config.OFF and pending.legs:
        audit["gocity"] = _apply_gocity(
            meta, pending,
            live=pending.modes["gocity"] == config.LIVE,
            marker=await config.setting(config.TRAVELPAYOUTS_MARKER),
            project_id=await config.setting(config.TRAVELPAYOUTS_PROJECT_ID),
        )

    if pending.modes.get("aviasales", config.OFF) != config.OFF:
        audit["aviasales"] = _apply_flight_links(
            meta,
            live=pending.modes["aviasales"] == config.LIVE,
            travelers=travelers,
            marker=await config.setting(config.TRAVELPAYOUTS_MARKER),
            project_id=await config.setting(config.TRAVELPAYOUTS_PROJECT_ID),
        )

    # Restrict booking_partners to only our 6 monetized partners
    if meta.get("booking_partners"):
        monetized_brands = ("airalo", "aviasales", "gettransfer", "wegotrip", "klook", "gocity", "go city")
        meta["booking_partners"] = [
            p for p in meta["booking_partners"]
            if isinstance(p, dict) and any(b in str(p.get("name") or "").lower() for b in monetized_brands)
        ]

    if pending.modes.get("ekta", config.OFF) != config.OFF and pending.international:
        audit["ekta"] = _apply_insurance(
            meta,
            live=pending.modes["ekta"] == config.LIVE,
            marker=await config.setting(config.TRAVELPAYOUTS_MARKER),
            project_id=await config.setting(config.TRAVELPAYOUTS_PROJECT_ID),
        )

    # After Aviasales, whose Booking Plan row the Kiwi row goes under.
    if pending.modes.get("kiwi", config.OFF) != config.OFF:
        audit["kiwi"] = _apply_kiwi_links(
            meta,
            live=pending.modes["kiwi"] == config.LIVE,
            travelers=travelers,
            marker=await config.setting(config.TRAVELPAYOUTS_MARKER),
            project_id=await config.setting(config.TRAVELPAYOUTS_PROJECT_ID),
        )

    meta["provider_audit"] = audit
    logger.info("providers: %s", audit)


def _add_partner(meta: dict, name: str, kind: str, url: str) -> None:
    """A tappable card under "Booking Partners & Websites" in the Itinerary tab.

    Replaces any card Gemini already wrote for the same brand, so the plan
    never shows two Airalo cards with different links.
    """
    brand = name.split()[0].lower()
    partners = [
        p for p in (meta.get("booking_partners") or [])
        if not (isinstance(p, dict) and brand in str(p.get("name") or "").lower())
    ]
    partners.append({"name": name, "type": kind, "url": url})
    meta["booking_partners"] = partners


def _add_plan_item(meta: dict, item: dict) -> None:
    """A tappable row in "Booking Plan & Timeline" on the Overview tab.

    The app opens a row's URL when it has one (odyssey_plan_view.dart
    `_bookingPlanItemRow`). Any earlier row for the same brand is replaced.
    """
    brand = str(item.get("item") or "").split()[0].lower()
    rows = [
        r for r in (meta.get("booking_plan") or [])
        if not (isinstance(r, dict) and brand and str(r.get("item") or "").lower().startswith(brand))
    ]
    rows.append(item)
    meta["booking_plan"] = rows


# ── Tickets ──────────────────────────────────────────────────────────────────

# At most this many ticket rows in the Booking Plan, the most reviewed first.
TICKET_PLAN_ROWS = 3


def _cities_on(legs: list, day) -> list[str]:
    """The city (or, on a travel day, both cities) a day's stops are in."""
    try:
        d = int(day)
    except (TypeError, ValueError):
        d = None
    named = [leg for leg in legs if isinstance(leg, dict) and leg.get("city")]
    if d is not None:
        on = [
            str(leg["city"]) for leg in named
            if int(leg.get("start_day") or 0) <= d <= int(leg.get("end_day") or 0)
        ]
        if on:
            return on
    return [str(leg["city"]) for leg in named]


async def _apply_tickets(
    pending: Pending, catalogue: dict, day_items: list[dict], meta: dict, *,
    live: bool, rate, currency: str, marker: str, project_id: str,
) -> dict:
    """A WeGoTrip line and link on each sight it sells a ticket or audio tour
    for, and the tickets in the Booking Plan.

    Information only, like GetTransfer: the stop's own cost and advice stay,
    and "On WeGoTrip: Burj Khalifa: Level 124/125 Ticket, from INR 5,076
    (rated 4.0 from 78 reviews)." is added to its tip, naming the product so
    a combined or partial ticket reads as what it is. The link goes in the
    stop's `booking_url`, which app builds before the "Book on WeGoTrip"
    button ignore on sights. A stop only ever takes a product from the city
    it is in that day, and never loses a link it already had.
    """
    entry: dict = {
        "mode": config.LIVE if live else config.SHADOW,
        "products": sum(len(v) for v in catalogue.values()),
        "cities": sorted(catalogue), "matched": [],
    }
    if not catalogue or not rate:
        if not rate:
            entry["none"] = "no rate"
        return entry
    names = [str(leg.get("city")) for leg in pending.legs if isinstance(leg, dict) and leg.get("city")]
    place = wegotrip.place_words(names, pending.country)
    rates: dict = {}
    booked: dict = {}
    for day in day_items:
        if not isinstance(day, dict):
            continue
        where: dict = {}
        pool = []
        for city in _cities_on(pending.legs, day.get("day")):
            for p in catalogue.get(city, []):
                where.setdefault(p["id"], city)
                pool.append(p)
        if not pool:
            continue
        for act in day.get("activities") or []:
            if not isinstance(act, dict) or str(act.get("type") or "").lower() not in wegotrip.SIGHT_TYPES:
                continue
            if act.get("booking_url"):
                continue
            product = wegotrip.match(str(act.get("name") or ""), pool, place)
            if not product:
                continue
            code = product["currency"]
            if code not in rates:
                rates[code] = await usd_rate(code)
            if not rates[code]:
                continue
            amount = format_amount(currency, product["price"] / rates[code] * rate)
            said = wegotrip.rating_words(product)
            line = f"On WeGoTrip: {product['title']}, from {amount}" + (f" ({said})" if said else "") + "."
            link = wegotrip.booking_link(product, marker=marker, project_id=project_id)
            entry["matched"].append({
                "stop": act.get("name"), "city": where.get(product["id"], ""),
                "product": product["title"], "id": product["id"],
                "kind": wegotrip.kind(product), "amount": amount,
            })
            if not live:
                continue
            tip = str(act.get("tip") or "").strip()
            act["tip"] = f"{tip} {line}".strip()
            act["booking_url"] = link
            if wegotrip.kind(product) == "Ticket":
                booked.setdefault(product["id"], (product, amount, link))
    if live and booked:
        entry["plan_rows"] = _add_ticket_rows(meta, list(booked.values()))
        first_ticket = list(booked.values())[0]
        _add_partner(meta, "WeGoTrip Sight Tickets", "tickets", first_ticket[2])
    elif live and entry.get("matched"):
        first_match = entry["matched"][0]
        match_link = wegotrip.booking_link({"id": first_match["id"], "title": first_match["product"]}, marker=marker, project_id=project_id)
        _add_partner(meta, "WeGoTrip Sight Tickets", "tickets", match_link)
    return entry


def _add_ticket_rows(meta: dict, tickets: list) -> int:
    """The most reviewed tickets as Booking Plan rows, which every app build
    opens. Rows from an earlier pass are replaced, not doubled."""
    tickets = sorted(tickets, key=lambda t: -t[0]["reviews"])[:TICKET_PLAN_ROWS]
    rows = [
        r for r in (meta.get("booking_plan") or [])
        if not (isinstance(r, dict) and str(r.get("item") or "").startswith("WeGoTrip"))
    ]
    for product, amount, link in tickets:
        rows.append({
            "label": "BOOK CLOSER TO TRAVEL",
            "item": f"WeGoTrip: {product['title']}, from {amount}",
            "reason": "Popular sights sell out their time slots; book once your dates are fixed.",
            "url": link,
        })
    meta["booking_plan"] = rows
    return len(tickets)


# ── Things to do where WeGoTrip has nothing ──────────────────────────────────

def _apply_klook(meta: dict, pending: Pending, *, covered: set, live: bool, marker: str, project_id: str) -> dict:
    """A "Things to do in Colombo on Klook" row in the Booking Plan for each
    city WeGoTrip put nothing on (at most five, longest stay first).

    A Booking Plan row, not a button on a stop: Klook's catalogue cannot be
    read (see klook.py), so no stop can be matched to what it sells. Every
    app build opens the row. Rows from an earlier pass are replaced.
    """
    cities = klook.cities_to_link(pending.legs, covered)
    links = {city: klook.booking_link(city, marker=marker, project_id=project_id) for city in cities}
    entry: dict = {"mode": config.LIVE if live else config.SHADOW, "cities": cities}
    if not live:
        entry["links"] = links
        return entry
    rows = [
        r for r in (meta.get("booking_plan") or [])
        if not (isinstance(r, dict) and klook.is_klook_link(str(r.get("url") or "")))
    ]
    rows += [klook.plan_item(city, links[city]) for city in cities]
    meta["booking_plan"] = rows
    entry["rows"] = len(cities)
    if cities:
        first_city = cities[0]
        _add_partner(meta, "Klook Experiences", "tours", links[first_city])
    return entry


# ── Sightseeing passes in big cities ─────────────────────────────────────────

def _apply_gocity(meta: dict, pending: Pending, *, live: bool, marker: str, project_id: str) -> dict:
    """A "Go City pass for New York" row in the Booking Plan for each Go City
    city the plan spends at least two days in (at most two).

    Shown beside WeGoTrip's single tickets, not instead: a pass is the better
    buy only for someone visiting several paid sights, which the traveller
    judges on Go City's own price page. Rows from an earlier pass are replaced.
    """
    slugs = gocity.cities_to_link(pending.legs)
    links = {slug: gocity.booking_link(slug, marker=marker, project_id=project_id) for slug in slugs}
    entry: dict = {"mode": config.LIVE if live else config.SHADOW, "cities": slugs}
    if not live:
        entry["links"] = links
        return entry
    rows = [
        r for r in (meta.get("booking_plan") or [])
        if not (isinstance(r, dict) and gocity.is_gocity_link(str(r.get("url") or "")))
    ]
    rows += [gocity.plan_item(slug, links[slug]) for slug in slugs]
    meta["booking_plan"] = rows
    entry["rows"] = len(slugs)
    if slugs:
        first_slug = slugs[0]
        _add_partner(meta, "Go City Pass", "passes", links[first_slug])
    return entry


# ── Flights ──────────────────────────────────────────────────────────────────

def _apply_flight_links(meta: dict, *, live: bool, travelers: int, marker: str, project_id: str) -> dict:
    """An Aviasales search on each flight option, as `aviasales_url`, and the
    Booking Plan's flight row pointed at its option's search.

    The option's `booking_url` and `provider_name` stay Google's. The fare on
    the card is Google's, and installed app builds rebuild any flight link
    whose provider is "Aviasales" into a bare search with no dates and no
    marker (BookingUrlHelper.buildFlightUrl). So the button reads the new field,
    in the builds that carry it. The Booking Plan row is opened unchanged by
    every build, which is why it moves now.
    """
    flights = meta.get("flight_strategies") if isinstance(meta.get("flight_strategies"), dict) else {}
    options = [s for s in (flights.get("strategies") or []) if isinstance(s, dict)]
    entry: dict = {"mode": config.LIVE if live else config.SHADOW, "options": len(options), "linked": 0}
    linked = []
    for option in options:
        legs = aviasales.legs_for(option, flights)
        path = aviasales.search_path(legs, adults=travelers, travel_class=option.get("travel_class"))
        if not path:
            continue
        entry["linked"] += 1
        entry.setdefault("path", path)
        link = aviasales.booking_link(path, marker=marker, project_id=project_id)
        linked.append((option, legs, link))
        if live:
            option["aviasales_url"] = link
    if live and linked:
        entry["plan_row"] = _point_flight_row(meta, linked)
        _add_partner(meta, "Aviasales Flights", "flights", linked[0][2])
    return entry


def _point_flight_row(meta: dict, linked: list[tuple[dict, list, str]]) -> bool:
    """Send the Booking Plan's flight row to Aviasales, naming it there (the
    label says where the tap goes). A visa reason on the row is kept.

    The row is found by the option it was written from — the same title and
    Google link. Which option that is varies (the Recommended tier on a live
    fare; the first option on older, estimated ones), so none is assumed.
    """
    for row in meta.get("booking_plan") or []:
        if not isinstance(row, dict):
            continue
        for option, legs, link in linked:
            title = str(option.get("title") or option.get("name") or "")
            if not (row.get("item") == title and str(row.get("url") or "") == str(option.get("booking_url") or "")):
                continue
            row["item"] = f"Flights on Aviasales: {aviasales.trip_text(legs)}"
            row["url"] = link
            if str(row.get("reason") or "").startswith("Confirmed live fare"):
                row["reason"] = (
                    "Fares move, so book early. Aviasales shows its live price for these flights."
                    if option.get("is_live_price")
                    else "The fare in this plan is an estimate. Aviasales shows the live price."
                )
            return True
    return False


def _apply_kiwi_links(meta: dict, *, live: bool, travelers: int, marker: str, project_id: str) -> dict:
    """A Kiwi.com deep search on each flight option, as `kiwi_url`, and one
    "Compare on Kiwi.com" row under the Booking Plan's flight row.

    Beside Aviasales, not instead (user, 2026-09-30: "both options"). The fare
    on the card stays Google's; each button opens its site's own live fares for
    the same trip, built from the same legs as the Aviasales link. Like
    `aviasales_url`, the field is read only by app builds that carry the
    button. The row is opened by every build.
    """
    flights = meta.get("flight_strategies") if isinstance(meta.get("flight_strategies"), dict) else {}
    options = [s for s in (flights.get("strategies") or []) if isinstance(s, dict)]
    entry: dict = {"mode": config.LIVE if live else config.SHADOW, "options": len(options), "linked": 0}
    main = None
    for option in options:
        legs = aviasales.legs_for(option, flights)
        url = kiwi.deep_url(legs, adults=travelers)
        if not url:
            continue
        entry["linked"] += 1
        entry.setdefault("url", url)
        link = kiwi.booking_link(url, marker=marker, project_id=project_id)
        if main is None or (option.get("tier") == "recommended" and main[0].get("tier") != "recommended"):
            main = (option, legs, link)
        if live:
            option["kiwi_url"] = link
    if live and main:
        entry["plan_row"] = _add_kiwi_row(meta, options, *main)
    return entry


def _add_kiwi_row(meta: dict, options: list[dict], option: dict, legs: list, link: str) -> bool:
    """Put the Kiwi row right under the flight row, with its label ("BOOK NOW",
    or "BOOK AFTER VISA"), replacing any earlier Kiwi row. With no flight row
    to sit under, it goes last under "BOOK NOW"."""
    rows = [
        r for r in (meta.get("booking_plan") or [])
        if not (isinstance(r, dict) and kiwi.is_kiwi_link(str(r.get("url") or "")))
    ]
    # The flight row: pointed at an option's Aviasales search, or still at the
    # option's own title and Google link.
    marks = {str(o.get("aviasales_url") or "") for o in options} - {""}
    marks |= {(str(o.get("title") or ""), str(o.get("booking_url") or "")) for o in options}
    at = next((
        i for i, r in enumerate(rows)
        if isinstance(r, dict) and (
            str(r.get("url") or "") in marks
            or (str(r.get("item") or ""), str(r.get("url") or "")) in marks
        )
    ), None)
    label = str(rows[at].get("label") or "BOOK NOW") if at is not None else "BOOK NOW"
    row = kiwi.plan_item(label, legs, link)
    if at is None:
        rows.append(row)
    else:
        rows.insert(at + 1, row)
    meta["booking_plan"] = rows
    return at is not None


# ── Travel insurance ─────────────────────────────────────────────────────────

def _apply_insurance(meta: dict, *, live: bool, marker: str, project_id: str) -> dict:
    """An EKTA travel-insurance row in the Booking Plan, and the "Get travel
    insurance" button under Practical Info's Safety row, on a trip to another
    country.

    With a visa to get, the row is "BOOK NOW": many embassies ask for
    insurance with the application. No price and no cover are named; EKTA
    quotes both for the traveller's age and trip (see ekta.py). The button
    reads `practical_info.safety_url` / `safety_cta`, in app builds that carry
    it; every build opens the row.
    """
    visa_needed = str((meta.get("visa") or {}).get("status") or "") == "needed"
    link = ekta.booking_link(marker=marker, project_id=project_id)
    entry: dict = {"mode": config.LIVE if live else config.SHADOW, "visa_needed": visa_needed}
    if not live:
        entry["link"] = link
        return entry
    rows = [
        r for r in (meta.get("booking_plan") or [])
        if not (isinstance(r, dict) and ekta.is_ekta_link(str(r.get("url") or "")))
    ]
    rows.append(ekta.plan_item(link, visa_needed=visa_needed))
    meta["booking_plan"] = rows
    info = meta.setdefault("practical_info", {})
    info["safety_url"] = link
    info["safety_cta"] = ekta.BUTTON_LABEL
    entry["applied"] = True
    return entry


# ── Transfers ────────────────────────────────────────────────────────────────

_PUBLIC = re.compile(
    r"\b(train|rail|railway|metro|subway|underground|tube|bus|coach|tram|ferry|boat|"
    r"shuttle|mrt|lrt|bts|monorail|u-bahn|s-bahn|airport link|public transport|tuk[- ]?tuk)\b",
    re.I,
)
_CAR = re.compile(
    r"\b(taxi|cab|car|uber|pickme|grab|bolt|careem|lyft|ola|gojek|chauffeur|driver|"
    r"private transfer|ride[- ]?hail\w*)\b",
    re.I,
)
_ARROW = re.compile(r"\s*(?:→|->|\bto\b)\s*", re.I)
# Words that make a stop a ride, and the ones that make it the flight itself.
_MOVE = re.compile(
    r"\b(transfer|taxi|cab|car|train|rail|metro|subway|bus|coach|tram|shuttle|"
    r"drive|ride|uber|ferry|express)\b",
    re.I,
)
_FLIGHT = re.compile(
    r"^\s*(arrival|arrive|arriving|land|landing|touch ?down|flight|fly|departure|depart|board)\b",
    re.I,
)


def _name(act: dict) -> str:
    return str(act.get("name") or "").lower()


def _is_ride(act: dict) -> bool:
    typed = str(act.get("type") or "").lower() in ("transport", "transit", "transfer")
    return typed or bool(_MOVE.search(_name(act)))


def _is_flight(act: dict) -> bool:
    """"Arrival at Copenhagen Airport (CPH)", "Flight home" — not a ride into town.

    "Arrival at COK & Transfer to Aluva" is both, and counts as the ride.
    """
    return bool(_FLIGHT.search(_name(act))) and not _MOVE.search(_name(act))


def _airport_ride(act: dict, airport_side: int) -> bool:
    """A ride naming the airport — on the given side of its arrow, if it has one."""
    if "airport" not in _name(act) or not _is_ride(act) or _is_flight(act):
        return False
    parts = _ARROW.split(_name(act), maxsplit=1)
    return len(parts) == 1 or "airport" in parts[airport_side]


def _next_to_flight(acts: list[dict], *, homeward: bool) -> Optional[dict]:
    """The ride right after landing, or (homeward) right before the flight home."""
    step = -1 if homeward else 1
    order = range(len(acts) - 1, -1, -1) if homeward else range(len(acts))
    for i in order:
        if not _is_flight(acts[i]):
            continue
        j = i + step
        while 0 <= j < len(acts) and _is_flight(acts[j]):
            j += step
        return acts[j] if 0 <= j < len(acts) and _is_ride(acts[j]) else None
    return None


def find_transfer_row(day_items: list[dict], kind: str) -> Optional[dict]:
    """The stop that moves the traveller between airport and town, or None.

    The prompt asks for "Transfer: X airport → City" (day 1) and
    "Transfer: City → X airport" (the last day, or the day before for an early
    flight), but the model writes what it likes: a Denmark plan had "Train to
    Copenhagen City Center" straight after "Arrival at Copenhagen Airport
    (CPH)", and "Copenhagen Airport Transfer" on the way home. So: a ride that
    names the airport on the right side; failing that, the ride next to the
    flight itself.
    """
    days = [d for d in day_items if isinstance(d, dict) and d.get("kind") == "day"]
    if not days:
        return None
    candidates = days[:1] if kind == "arrival" else list(reversed(days[-2:]))
    for day in candidates:
        acts = [a for a in day.get("activities") or [] if isinstance(a, dict)]
        if not acts:
            continue
        if kind == "arrival":
            found = next((a for a in acts if _airport_ride(a, 0)), None)
            found = found or _next_to_flight(acts, homeward=False)
        else:
            found = next((a for a in reversed(acts) if _airport_ride(a, 1)), None)
            found = found or _next_to_flight(acts, homeward=True)
        if found is not None:
            return found
    return None


def transfer_mode(act: dict) -> str:
    """"car", "public" or "unclear", from what the stop itself says."""
    text = " ".join(str(act.get(k) or "") for k in ("name", "tip", "price_basis"))
    public, car = bool(_PUBLIC.search(text)), bool(_CAR.search(text))
    if car and not public:
        return "car"
    return "public" if public else "unclear"


def _apply_transfer(kind, transfer, q, ms, day_items, *, live, rate, currency, travelers, link_for=None) -> dict:
    entry: dict = {"route": transfer.label, "ms": ms}
    if not q:
        entry["none"] = "no bookable car"
        return entry
    entry.update(usd=q["usd_total"], usd_low=q.get("usd_low_total"), cars=q["cars"],
                 car_class=q["class"], bookable=q.get("bookable", True),
                 km=q.get("km"), minutes=q.get("minutes"))
    row = find_transfer_row(day_items, kind)
    if row is None:
        entry["decision"] = "no_row"
        return entry
    entry["row"] = {k: row.get(k, "") for k in ("name", "cost", "price_source")}
    if not rate:
        entry["decision"] = "no_rate"
        return entry

    total = round(q["usd_total"] * rate, 2)
    detail = gettransfer.basis(q, travelers, rate, currency)
    mode = transfer_mode(row)
    # Information only (user, 2026-09-29: "for airport taxi, just show it as
    # information for now"). The stop keeps the fare and the mode the plan
    # chose: a bus or train is usually the cheaper advice, and a changed
    # price would move the plan's numbers. The private car is shown beside it.
    entry["mode"] = mode
    entry["decision"] = "info"
    entry["applied"] = False
    if not live:
        return entry
    # The lowest driver offer to the instant price ("USD 17–24"); "from" when
    # there is only an offer; one figure when there is only an instant price.
    low_usd = q.get("usd_low_total")
    if not q.get("bookable", True):
        amount = f"from {format_amount(currency, total)}"
    elif low_usd:
        amount = format_range(currency, round(low_usd * rate, 2), total)
    else:
        amount = format_amount(currency, total)
    took = gettransfer.duration_text(q.get("minutes"))
    # On the tip, which every app build shows under the stop.
    line = f"Private car: {amount} with GetTransfer" + (f", {took}" if took else "") + "."
    tip = str(row.get("tip") or "").strip()
    if tip and tip[-1] not in ".!?":
        tip += "."
    row["tip"] = f"{tip} {line}" if tip else line
    # And the full detail in the price sheet the stop's price pill opens.
    extra = f"Private car option: {amount} (GetTransfer, {detail})"
    existing = str(row.get("price_basis") or "").strip()
    row["price_basis"] = f"{existing} · {extra}" if existing else extra
    # The tracked booking page, for the stop's "Book private car" button
    # (app builds from 2026-09-29 show it; older ones ignore the field).
    link = link_for(q.get("class", ""), transfer) if link_for else ""
    if link:
        row["booking_url"] = link
        entry["link"] = True
    entry["applied"] = True
    entry["amount"] = amount
    return entry


def _airport_full_name(airport: Optional[dict]) -> str:
    """"Adolfo Suárez Madrid-Barajas Airport": what GetTransfer's form can find.

    The route's own name first, then the airport table's; a bare code is
    widened to "MAD airport", which the form also resolves.
    """
    airport = airport or {}
    name = str(airport.get("name") or "").strip()
    if name:
        return name
    code = str(airport.get("iata") or "").strip().upper()
    known = airports_service.get(code)
    if known is not None:
        return known.name
    return f"{code} airport" if code else ""


_NUMBER = re.compile(r"[\d,]+(?:\.\d+)?")


def _hotel_for_leg(meta: dict, leg_index: int, city: str) -> str:
    """"Hotel Villa Real, Madrid": the plan's cheapest hotel for that leg.

    The cheapest is the Stays tab's default pick (Minimum tier). The
    traveller can change the drop-off on GetTransfer's page; a named hotel
    beats a city, which GetTransfer will not take as an exact point. Plans
    made without hotels return "".
    """
    strategies = ((meta or {}).get("hotel_strategies") or {}).get("strategies") or []
    rows = [h for h in strategies if isinstance(h, dict) and str(h.get("name") or "").strip()]
    if any("leg_index" in h for h in rows):
        rows = [h for h in rows if h.get("leg_index") == leg_index]

    def nightly(h: dict) -> float:
        m = _NUMBER.search(str(h.get("price_per_night") or ""))
        try:
            return float(m.group().replace(",", "")) if m else float("inf")
        except ValueError:
            return float("inf")

    if not rows:
        return ""
    best = min(rows, key=nightly)
    town = str(best.get("city") or city or "").strip()
    name = str(best["name"]).strip()
    return f"{name}, {town}" if town and town.lower() not in name.lower() else name


def transfers_for(route, legs: list[dict], arrival_date: str, departure_date: str, km) -> list[Transfer]:
    """The airport rides worth pricing for this route.

    `km(a, b)` measures airport-to-leg distance (odyssey_ai_service passes its
    own helper, so both sides agree on what "in town" means).
    """
    out: list[Transfer] = []
    if route is None or not legs:
        return out

    def point(d):
        try:
            return (float(d["latitude"]), float(d["longitude"]))
        except (KeyError, TypeError, ValueError):
            return None

    pairs = (
        ("arrival", route.arrival, legs[0], arrival_date, True),
        ("departure", route.departure, legs[-1], departure_date, False),
    )
    for kind, airport, leg, date, inbound in pairs:
        a, c = point(airport or {}), point(leg or {})
        if a is None or c is None:
            continue
        dist = km(airport, leg)
        if dist is not None and dist < MIN_TRANSFER_KM:
            continue
        airport_name = f"{(airport or {}).get('iata') or 'Airport'}"
        city = str((leg or {}).get("city") or "")
        label = f"{airport_name} → {city}" if inbound else f"{city} → {airport_name}"
        out.append(Transfer(
            kind=kind,
            origin=a if inbound else c,
            dest=c if inbound else a,
            date=date,
            label=label,
            airport=_airport_full_name(airport),
            city=city,
            leg_index=0 if inbound else len(legs) - 1,
        ))
    return out
