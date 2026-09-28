"""Real prices from the travel-data providers, laid onto a finished Odyssey.

`start()` runs as soon as the plan's airports are final — just before Gemini
writes the itinerary, which takes 35–63 s — and `finish()` only after it. The
fetches take well under a second, so no plan waits for them.

Each provider follows its switch in the admin panel (`config.mode`):

    off     not called
    shadow  fetched, and what it *would* have changed is recorded in the plan's
            `provider_audit` block; the traveller sees nothing new
    live    applied, through fields every app build already shows: a stop's
            cost / price_source / price_basis, and the "Connectivity & SIM" tip

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

from app.services.providers import airalo, base, config, gettransfer
from app.services.providers.money import format_amount, usd_rate

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


@dataclass
class Pending:
    modes: dict
    tasks: dict = field(default_factory=dict)
    transfers: dict = field(default_factory=dict)
    started: float = field(default_factory=time.perf_counter)
    esim_country: str = ""


async def start(
    *,
    transfers: list[Transfer],
    country_name: str,
    country_code: str,
    days: int,
    travelers: int,
) -> Optional[Pending]:
    """Begin every fetch this plan's switches allow. None when all are off."""
    try:
        modes = {p: await config.mode(p) for p in ("gettransfer", "airalo")}
    except Exception as e:
        logger.warning("providers: could not read switches: %s", e)
        return None
    if all(m == config.OFF for m in modes.values()):
        return None

    pending = Pending(modes=modes)
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
        for kind, transfer in pending.transfers.items():
            q, ms = result(f"gettransfer:{kind}")
            entry[kind] = _apply_transfer(
                kind, transfer, q, ms, day_items,
                live=live, rate=rate, currency=currency, travelers=travelers,
            )
        audit["gettransfer"] = entry

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


def _apply_transfer(kind, transfer, q, ms, day_items, *, live, rate, currency, travelers) -> dict:
    entry: dict = {"route": transfer.label, "ms": ms}
    if not q:
        entry["none"] = "no bookable car"
        return entry
    entry.update(usd=q["usd_total"], cars=q["cars"], car_class=q["class"],
                 bookable=q.get("bookable", True), km=q.get("km"), minutes=q.get("minutes"))
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
    # A car price only replaces a car fare. A train or bus the model chose is
    # a real, usually cheaper option; overwriting it would change the advice,
    # so the car becomes the alternative printed beside it.
    entry["decision"] = "replace" if mode == "car" else "alternative"
    entry["applied"] = False
    if not live:
        return entry
    if mode == "car":
        quote = base.PriceQuote(
            amount=total, currency=currency, source="GetTransfer",
            # An instant price is fixed; a typical driver offer is typical.
            freshness=base.LIVE if q.get("bookable", True) else base.RECENT,
            basis=detail,
        )
        row.update(quote.activity_fields())
        row["cost_per_person"] = round(total / max(travelers, 1), 2)
    else:
        extra = f"Private car instead: {format_amount(currency, total)} (GetTransfer, {detail})"
        existing = str(row.get("price_basis") or "").strip()
        row["price_basis"] = f"{existing} · {extra}" if existing else extra
    entry["applied"] = True
    return entry


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
        ))
    return out
