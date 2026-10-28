"""City Tours: the guide document, its checks, the review rules and partner links.

A guide is one JSON document, the same shape in the editor, in the database
(`city_tours.content` / `live_content`) and, with its links resolved, in the
app:

    {
      "city": "Paris", "country": "France",
      "title": "Paris in a day by metro", "summary": "…", "cover_url": "/static/…",
      "duration": "6–7 hours", "budget": "€40–60 per person",
      "intro_md": "## Before you start\\n…",           light Markdown, as the
      "days": [                                         description editor writes
        {"id": "…", "title": "Eiffel Tower, Champ de Mars and Invalides",
         "starts_at": "09:00", "steps": [
          {"id": "…", "type": "stop", "name": "Eiffel Tower", "lat": 48.8584,
           "lng": 2.2945, "photo_url": "…", "time_here": "2 hr 45 min", "price": "€29",
           "access_note": "Open daily", "body_md": "…", "links": [link, …]},
          {"id": "…", "type": "move", "mode": "walk", "title": "Across the Champ de Mars",
           "duration": "15 min", "cost": "", "access_note": "", "body_md": "…", "links": […]},
          {"id": "…", "type": "break", "title": "Lunch / Rest", "duration": "45 min",
           "access_note": "", "body_md": "…", "links": […]},
          …
        ]},
        …
      ]
    }

A guide is one or more days, each a group of places in order: stops, the
rides between them and breaks (lunch, a rest). A traveller with fewer days
than the guide has takes the first ones, or picks the days whose places they
want. A day's clock times come from its start time and each step's planned
minutes (city_tour_trips.step_minutes), so nobody types "11:45 AM". Guides
saved before days existed have a single "steps" list: `days_of` reads them as
one day, and saving one turns it into `days`.

    link = {"id": "…", "kind": "affiliate", "partner": "klook", "words": "Seine cruise",
            "label": "Seine river cruise", "url": "<made here>"}
         | {"id": "…", "kind": "affiliate", "partner": "wegotrip", "product_title": "…",
            "url": "<a product page from WeGoTrip's catalogue>", "label": "…"}
         | {"id": "…", "kind": "experience", "package_id": "…", "label": "…"}

Creators never type a web address: an affiliate link's page is made here from
the guide (its city and country, the stop's name, the stops either side of a
ride), or, for WeGoTrip, picked from the city's catalogue in the editor
(partner_options). Stops are numbered within their day and pinned on that
day's map. Step and link ids are unique across the whole guide and stay put
across edits: trips mark steps done by id, and taps are counted per link
(city_tour_taps.link_id).

Everything here is free of the database, so it can be tested on its own.
"""
from __future__ import annotations

import math
import re
import urllib.parse
import uuid
from dataclasses import dataclass
from typing import Callable, Optional

from app.services.providers import airalo, gettransfer, gocity, klook, wegotrip


class ContentError(ValueError):
    """A guide that cannot be saved, said the way the editor shows it."""


# ── Partners ─────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Affiliate:
    key: str
    name: str
    what: str
    domains: tuple[str, ...]
    # Travelpayouts' program numbers, as each provider module builds its own
    # links. GetTransfer links carry no campaign_id.
    campaign_id: str
    promo_id: str


# The Travelpayouts programs Odyssey already links to, minus the flight ones:
# a flight search needs the traveller's home airport and dates, which a guide
# does not know. The tap goes through tp.media with our partner ID, so a sale
# on the partner's page is credited to us. HelloSafe insurance is not here
# either: its links are made per traveller from trip dates.
AFFILIATES: dict[str, Affiliate] = {a.key: a for a in (
    Affiliate("klook", "Klook", "Tours, day trips and tickets", ("klook.com",),
              klook.CAMPAIGN_ID, klook.PROMO_ID),
    Affiliate("wegotrip", "WeGoTrip", "Entry tickets and audio tours", ("wegotrip.com",),
              wegotrip.CAMPAIGN_ID, wegotrip.PROMO_ID),
    Affiliate("gocity", "Go City", "Sightseeing passes for many attractions", ("gocity.com",),
              gocity.CAMPAIGN_ID, gocity.PROMO_ID),
    Affiliate("gettransfer", "GetTransfer", "A car with a driver, booked ahead", ("gettransfer.com",),
              "", gettransfer.PROMO_ID),
    Affiliate("airalo", "Airalo", "eSIM data for the trip", ("airalo.com",),
              airalo._CAMPAIGN_ID, airalo._PROMO_ID),
)}

EXPERIENCE = "experience"
AFFILIATE = "affiliate"

_TRAVELPAYOUTS = "https://tp.media/r"


def host_matches(url: str, domains: tuple[str, ...]) -> bool:
    """True for https pages on one of the partner's own domains."""
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return False
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or not host:
        return False
    return any(host == d or host.endswith("." + d) for d in domains)


def tracked_url(partner: str, url: str, *, marker: str, project_id: str) -> str:
    """The creator's page through Travelpayouts, so a sale earns us a share.

    Without both the partner ID and the Project ID it still opens the page.
    """
    affiliate = AFFILIATES.get(partner)
    if affiliate is None or not (marker and project_id):
        return url
    query = {"campaign_id": affiliate.campaign_id} if affiliate.campaign_id else {}
    query.update({"marker": marker, "p": affiliate.promo_id, "trs": project_id, "u": url})
    return _TRAVELPAYOUTS + "?" + urllib.parse.urlencode(query)


# ── The document ─────────────────────────────────────────────────────────────

# How a traveller gets from one stop to the next. The app draws each with its
# own icon (city_tour_widgets.dart) and the panel's preview copies them.
TRANSPORT_MODES: dict[str, str] = {
    "walk": "Walk",
    "metro": "Metro",
    "bus": "Bus",
    "tram": "Tram",
    "train": "Train",
    "taxi": "Taxi or ride app",
    "tuk_tuk": "Tuk-tuk",
    "boat": "Boat or ferry",
    "bike": "Bike",
    "car": "Car or transfer",
}

STOP, MOVE, BREAK = "stop", "move", "break"
STEP_KINDS = (STOP, MOVE, BREAK)
MAX_DAYS = 14
MAX_STEPS = 60  # in one day
MAX_LINKS_PER_STEP = 6
# The one day of a guide saved before days existed. A fixed id, so its trips
# and the day the editor saves it as are the same day.
LEGACY_DAY_ID = "00000000-0000-4000-8000-000000000001"

# Field → (longest, what the editor calls it).
_TOUR_TEXT = {
    "city": (80, "City"),
    "country": (80, "Country"),
    "title": (120, "Title"),
    "summary": (300, "Short intro"),
    "duration": (40, "How long it takes"),
    "budget": (60, "Budget"),
}
_INTRO_MAX = 20000
_STOP_TEXT = {
    "name": (120, "name"),
    "time_here": (40, "time to spend"),
    "price": (80, "entry price"),
}
_MOVE_TEXT = {
    "title": (160, "directions"),
    "duration": (40, "travel time"),
    "cost": (60, "fare"),
}
_BREAK_TEXT = {
    "title": (80, "name"),
    "duration": (40, "time it takes"),
}
_STEP_TEXT = {STOP: _STOP_TEXT, MOVE: _MOVE_TEXT, BREAK: _BREAK_TEXT}
_ACCESS_MAX = 300
_DAY_TITLE_MAX = 160
_STEP_BODY_MAX = 8000
_LABEL_MAX = 80
_URL_MAX = 1000
_MEDIA_MAX = 500


def _str(value) -> str:
    return value.strip() if isinstance(value, str) else ""


def _text(raw: dict, key: str, longest: int, name: str) -> str:
    value = _str(raw.get(key))
    if len(value) > longest:
        raise ContentError(f"{name} is too long ({len(value)} characters, {longest} at most).")
    return value


def _markdown(raw: dict, key: str, longest: int, name: str) -> str:
    value = raw.get(key) if isinstance(raw.get(key), str) else ""
    value = value.replace("\r\n", "\n").strip()
    if len(value) > longest:
        raise ContentError(f"{name} is too long ({len(value):,} characters, {longest:,} at most).")
    return value


def _media(value, name: str) -> str:
    """An uploaded photo (/static/uploads/…) or an https address; "" for none."""
    url = _str(value)
    if not url:
        return ""
    if len(url) > _MEDIA_MAX or not (url.startswith("/static/uploads/") or url.startswith("https://")):
        raise ContentError(f"{name}: that photo address can't be used. Upload the photo instead.")
    return url


def _coord(value, low: float, high: float) -> Optional[float]:
    if value is None or value == "" or isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number) or not (low <= number <= high):
        return None
    return round(number, 6)


def _uuid_text(value) -> Optional[str]:
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, AttributeError, TypeError):
        return None


def _new_id(value, seen: set[str]) -> str:
    """The id the editor sent when it is a fresh, well-formed one, else a new one."""
    kept = _uuid_text(value)
    if kept is None or kept in seen:
        kept = str(uuid.uuid4())
    seen.add(kept)
    return kept


# ── Partner pages, made from the guide ───────────────────────────────────────

_WEGOTRIP_PAGE = re.compile(r"^/[a-z0-9-]+-d\d+/[a-z0-9-]+-p\d+/?$")
_WORDS_MAX = 80


@dataclass(frozen=True)
class LinkPlace:
    """Where a link sits: the guide's city and country, its step, and the
    stops either side of it (for a ride)."""
    city: str
    country: str
    step: dict
    prev_stop: Optional[dict] = None
    next_stop: Optional[dict] = None


def airalo_slug(country: str) -> str:
    """Airalo's name for a country's page ("france" → airalo.com/france-esim), or ""."""
    name = (country or "").strip()
    if not name:
        return ""
    from app.services.geo_resolver import _COUNTRY_NAMES

    code = name.upper() if len(name) == 2 else next(
        (c for c, n in _COUNTRY_NAMES.items() if n.casefold() == name.casefold()), "",
    )
    return next(iter(airalo._candidates(name, code)), "")


def klook_query(words: str, place: LinkPlace) -> str:
    """What Klook is searched for: the creator's words, or the stop's name, and
    the city unless the words already say it."""
    words = words or (place.step.get("name") if place.step.get("type") == STOP else "") or ""
    if place.city and place.city.casefold() in words.casefold():
        return words
    return " ".join(w for w in (words, place.city) if w)


def _place_name(stop: Optional[dict], city: str) -> str:
    return ", ".join(p for p in ((stop or {}).get("name") or "", city) if p)


def partner_page(link: dict, place: LinkPlace) -> str:
    """The partner's page for a link, "" when there is none to make."""
    partner = link.get("partner")
    if partner == "klook":
        query = klook_query(link.get("words") or "", place)
        return klook.search_url(query) if query else ""
    if partner == "gocity":
        slug = gocity.destination_for(place.city, place.country)
        return gocity.pass_page(slug) if slug else ""
    if partner == "airalo":
        slug = airalo_slug(place.country)
        return airalo.country_page(slug) if slug else ""
    if partner == "gettransfer":
        # On a stop: a car to it, from wherever the traveller says (the
        # nearest-airport table picks small fields, e.g. Ratmalana for
        # Colombo). On a ride: from the stop before to the stop after.
        if place.step.get("type") == STOP:
            return gettransfer.booking_link(
                "economy", marker="", project_id="", to_name=_place_name(place.step, place.city),
            )
        return gettransfer.booking_link(
            "economy", marker="", project_id="",
            from_name=_place_name(place.prev_stop, place.city),
            to_name=_place_name(place.next_stop, place.city),
        )
    if partner == "wegotrip":
        url = link.get("url") or ""
        ok = host_matches(url, AFFILIATES["wegotrip"].domains) and _WEGOTRIP_PAGE.match(
            urllib.parse.urlparse(url).path or "",
        )
        return url if ok else ""
    return ""


def _link(raw, where: str, seen: set[str], place: LinkPlace) -> dict:
    if not isinstance(raw, dict):
        raise ContentError(f"{where}: a partner link is broken. Remove it and add it again.")
    label = _str(raw.get("label"))
    if len(label) > _LABEL_MAX:
        raise ContentError(f"{where}: the button text is too long ({_LABEL_MAX} characters at most).")
    link_id = _new_id(raw.get("id"), seen)

    if raw.get("kind") == EXPERIENCE:
        return {
            "id": link_id, "kind": EXPERIENCE,
            "package_id": _uuid_text(raw.get("package_id")) or "", "label": label,
        }

    partner = _str(raw.get("partner"))
    if partner not in AFFILIATES:
        raise ContentError(f"{where}: pick a partner for each link.")
    link = {"id": link_id, "kind": AFFILIATE, "partner": partner, "label": label}
    if partner == "klook":
        words = _str(raw.get("words"))
        if len(words) > _WORDS_MAX:
            raise ContentError(f"{where}: the Klook search words are too long ({_WORDS_MAX} characters at most).")
        link["words"] = words
    if partner == "wegotrip":
        link["product_title"] = _str(raw.get("product_title"))[:200]
        link["url"] = _str(raw.get("url"))[:_URL_MAX]
    link["url"] = partner_page(link, place)
    return link


def _step(raw, where: str, step_ids: set[str]) -> dict:
    if not isinstance(raw, dict):
        raise ContentError(f"{where} is broken. Remove it and add it again.")
    kind = raw.get("type")
    if kind not in STEP_KINDS:
        raise ContentError(f"{where} is not a stop, a ride or a break.")

    step = {"id": _new_id(raw.get("id"), step_ids), "type": kind}
    for key, (longest, name) in _STEP_TEXT[kind].items():
        value = _str(raw.get(key))
        if len(value) > longest:
            raise ContentError(f"{where}: the {name} is too long ({longest} characters at most).")
        step[key] = value

    if kind == STOP:
        step["lat"] = _coord(raw.get("lat"), -90.0, 90.0)
        step["lng"] = _coord(raw.get("lng"), -180.0, 180.0)
        if step["lat"] is None or step["lng"] is None:
            step["lat"] = step["lng"] = None
        step["photo_url"] = _media(raw.get("photo_url"), where)
    elif kind == MOVE:
        mode = _str(raw.get("mode"))
        step["mode"] = mode if mode in TRANSPORT_MODES else "walk"

    note = _str(raw.get("access_note"))
    if len(note) > _ACCESS_MAX:
        raise ContentError(f"{where}: the opening and access note is too long ({_ACCESS_MAX} characters at most).")
    step["access_note"] = note
    step["body_md"] = _markdown(raw, "body_md", _STEP_BODY_MAX, f"{where}'s text")

    links = raw.get("links") if isinstance(raw.get("links"), list) else []
    if len(links) > MAX_LINKS_PER_STEP:
        raise ContentError(f"{where}: {MAX_LINKS_PER_STEP} partner links at most.")
    return step


def normalize(raw) -> dict:
    """The guide as it is stored: known fields only, trimmed, ids made unique.

    Raises ContentError for anything the editor should have stopped (too long,
    a link to the wrong site). A guide still being written may be incomplete;
    `problems` says what it lacks before review.
    """
    if not isinstance(raw, dict):
        raise ContentError("The guide is empty.")
    out = {key: _text(raw, key, longest, name) for key, (longest, name) in _TOUR_TEXT.items()}
    out["cover_url"] = _media(raw.get("cover_url"), "Cover photo")
    out["intro_md"] = _markdown(raw, "intro_md", _INTRO_MAX, "The introduction")

    days = days_of(raw)
    if len(days) > MAX_DAYS:
        raise ContentError(f"A guide has {MAX_DAYS} days at most.")
    day_ids: set[str] = set()
    step_ids: set[str] = set()
    link_ids: set[str] = set()
    out["days"] = []
    for d, raw_day in enumerate(days):
        if not isinstance(raw_day, dict):
            raise ContentError(f"Day {d + 1} is broken. Remove it and add it again.")
        name = f"Day {d + 1}" if len(days) > 1 else ""
        title = _str(raw_day.get("title"))
        if len(title) > _DAY_TITLE_MAX:
            raise ContentError(f"{name or 'The day'}: its places line is too long ({_DAY_TITLE_MAX} characters at most).")
        raw_steps = raw_day.get("steps") if isinstance(raw_day.get("steps"), list) else []
        if len(raw_steps) > MAX_STEPS:
            raise ContentError(f"{name or 'A day'} has {MAX_STEPS} steps at most.")
        steps = [
            _step(s, " · ".join(p for p in (name, f"Step {i + 1}") if p), step_ids)
            for i, s in enumerate(raw_steps)
        ]
        # Links last: a ride's link needs the stops either side of it.
        for i, (raw_step, step) in enumerate(zip(raw_steps, steps)):
            place = LinkPlace(
                city=out["city"], country=out["country"], step=step,
                prev_stop=next((s for s in reversed(steps[:i]) if s["type"] == STOP), None),
                next_stop=next((s for s in steps[i + 1:] if s["type"] == STOP), None),
            )
            links = raw_step.get("links") if isinstance(raw_step.get("links"), list) else []
            where = " · ".join(p for p in (name, f"Step {i + 1}") if p)
            step["links"] = [_link(link, where, link_ids, place) for link in links]
        out["days"].append({
            "id": _new_id(raw_day.get("id"), day_ids),
            "title": title,
            "starts_at": start_time(raw_day.get("starts_at"), name or "The day"),
            "steps": steps,
        })
    return out


_CLOCK = re.compile(r"^\s*(\d{1,2})(?:[:.](\d{2}))?\s*([ap])?\.?\s*m?\.?\s*$", re.I)


def start_time(value, where: str) -> str:
    """A day's start as "HH:MM" (24-hour), from "09:00", "9:30" or "9:30 AM";
    "" for none."""
    text = _str(value)
    if not text:
        return ""
    m = _CLOCK.match(text)
    hour, minute = (int(m.group(1)), int(m.group(2) or 0)) if m else (99, 0)
    half = (m.group(3) or "").lower() if m else ""
    if half and 1 <= hour <= 12:
        hour = hour % 12 + (12 if half == "p" else 0)
    elif half:
        hour = 99
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ContentError(f"{where}: the start time should look like 09:00.")
    return f"{hour:02d}:{minute:02d}"


def days_of(content) -> list[dict]:
    """A guide's days. One saved before days existed is one day, of its steps."""
    content = content if isinstance(content, dict) else {}
    days = content.get("days")
    if isinstance(days, list):
        return days
    steps = content.get("steps")
    if isinstance(steps, list):
        return [{"id": LEGACY_DAY_ID, "title": "", "starts_at": "", "steps": steps}]
    return []


def all_steps(content) -> list[dict]:
    """Every step of every day, in order."""
    return [s for day in days_of(content) for s in (day.get("steps") or []) if isinstance(s, dict)]


def find_day(content, day_id) -> Optional[dict]:
    """The day with this id; the first day for none (a trip from before days)."""
    days = days_of(content)
    if not days:
        return None
    if not day_id:
        return days[0]
    return next((d for d in days if d.get("id") == day_id), None)


def stops(content: dict) -> list[dict]:
    return [s for s in all_steps(content) if s.get("type") == STOP]


def links(content: dict):
    """(step, link) for every partner link, in reading order."""
    for step in all_steps(content):
        for link in step.get("links") or []:
            yield step, link


def find_link(content: dict, link_id: str) -> Optional[dict]:
    return next((link for _s, link in links(content) if link.get("id") == link_id), None)


def _where(day_name: str, step: dict, number: int) -> str:
    """"Stop 3", "Travel to stop 4", "Break after stop 2", with the day first
    when the guide has several."""
    kind = step.get("type")
    if kind == STOP:
        place = f"Stop {number}"
    elif kind == MOVE:
        place = f"Travel to stop {number + 1}"
    else:
        place = f"Break after stop {number}" if number else "Break"
    return " · ".join(p for p in (day_name, place) if p)


def step_name(content: dict, step: dict) -> str:
    """"Day 2 · Stop 3 · Louvre" or "Travel to stop 4 · Metro": where a link sits."""
    days = days_of(content)
    for d, day in enumerate(days):
        number = 0
        day_name = f"Day {d + 1}" if len(days) > 1 else ""
        for s in day.get("steps") or []:
            if s.get("type") == STOP:
                number += 1
            if s is step:
                where = _where(day_name, s, number)
                if s["type"] == STOP:
                    return f"{where} · {s.get('name') or 'unnamed'}"
                if s["type"] == MOVE:
                    return f"{where} · {TRANSPORT_MODES.get(s.get('mode'), 'Walk')}"
                return f"{where} · {s.get('title') or 'Break'}"
    return ""


def problems(content: dict, *, package_ok: Optional[Callable[[str], bool]] = None) -> list[str]:
    """What the guide still needs before it can go to review or live.

    `package_ok(package_id)` says whether an Experience is still listed in the
    app; without it, Experience links are only checked for having one.
    """
    content = content or {}
    found = []
    for key, label in (
        ("title", "a title"), ("city", "the city"), ("country", "the country"),
        ("summary", "the short intro"), ("cover_url", "a cover photo"),
    ):
        if not content.get(key):
            found.append(f"Add {label}.")

    days = days_of(content)
    if len(stops(content)) < 2:
        found.append("Add at least two stops.")

    for d, day in enumerate(days):
        day_name = f"Day {d + 1}" if len(days) > 1 else ""
        steps = day.get("steps") or []
        if day_name and not day.get("title"):
            found.append(f"{day_name}: add the line of places it covers, which travellers pick days by.")
        if day_name and not any(s.get("type") == STOP for s in steps):
            found.append(f"{day_name}: add at least one stop.")
        number = 0
        for step in steps:
            if step.get("type") == STOP:
                number += 1
            where = _where(day_name, step, number)
            if step.get("type") == STOP:
                if not step.get("name"):
                    found.append(f"{where}: add its name.")
                if step.get("lat") is None or step.get("lng") is None:
                    found.append(f"{where}: put it on the map.")
            found.extend(_link_problems(step, where, content, package_ok))
    return found


def _link_problems(step: dict, where: str, content: dict, package_ok) -> list[str]:
    found = []
    for link in step.get("links") or []:
        if link.get("kind") == EXPERIENCE:
            if not link.get("package_id"):
                found.append(f"{where}: pick the experience for each Experience link.")
            elif package_ok is not None and not package_ok(link["package_id"]):
                found.append(f"{where}: an Experience it links to is no longer listed in the app.")
        elif not link.get("url"):
            found.append(f"{where}: {_no_page(link, content)}")
    return found


def _no_page(link: dict, content: dict) -> str:
    partner = link.get("partner")
    if partner == "gocity":
        return f"Go City has no pass for {content.get('city') or 'this city'}. Remove its link."
    if partner == "airalo":
        return "add the guide's country, for the Airalo link."
    if partner == "wegotrip":
        return "pick the WeGoTrip ticket for its link."
    if partner == "klook":
        return "add the words to search Klook for."
    return "remove the link and add it again."


# ── Review ───────────────────────────────────────────────────────────────────

DRAFT, PENDING, CHANGES_REQUESTED, APPROVED = "draft", "pending", "changes_requested", "approved"
STATUSES = (DRAFT, PENDING, CHANGES_REQUESTED, APPROVED)


def status_after_edit(status: str) -> str:
    """The status once the working copy changes.

    A sent guide that changes must be sent again, so an admin never approves
    something other than what was sent. A guide sent back keeps the admin's
    note in view until it goes back to them.
    """
    return CHANGES_REQUESTED if status == CHANGES_REQUESTED else DRAFT


def can_submit(status: str) -> bool:
    return status in (DRAFT, CHANGES_REQUESTED)


# ── What the app gets ────────────────────────────────────────────────────────

def card(content: dict) -> dict:
    """A guide in the app's lists."""
    content = content or {}
    return {
        "city": content.get("city") or "",
        "country": content.get("country") or "",
        "title": content.get("title") or "",
        "summary": content.get("summary") or "",
        "cover_url": content.get("cover_url") or "",
        "duration": content.get("duration") or "",
        "budget": content.get("budget") or "",
        "stop_count": len(stops(content)),
        "day_count": len(days_of(content)),
    }


def city_key(content: dict) -> tuple[str, str]:
    """Guides group into one city however the creator capitalised it."""
    content = content or {}
    return (
        " ".join((content.get("city") or "").split()).casefold(),
        " ".join((content.get("country") or "").split()).casefold(),
    )


def app_view(
    content: dict,
    *,
    tap_url: Callable[[str], str],
    package_view: Callable[[str], Optional[dict]],
) -> dict:
    """The guide as the app draws it: stops numbered, links ready to tap.

    `tap_url(link_id)` is our /go address for an affiliate link (counts the tap
    and goes on to the partner); `package_view(package_id)` is the Experience
    as its card shows it, or None when it is not listed, which drops the link.
    """
    from app.services.city_tour_trips import step_minutes

    view = card(content)
    view["intro_md"] = (content or {}).get("intro_md") or ""
    days_out = []
    for d, day in enumerate(days_of(content)):
        steps_out = []
        number = 0
        for step in day.get("steps") or []:
            out = {k: v for k, v in step.items() if k != "links"}
            out["minutes"] = step_minutes(step)
            if step.get("type") == STOP:
                number += 1
                out["number"] = number
            elif step.get("type") == MOVE:
                out["mode_label"] = TRANSPORT_MODES.get(step.get("mode"), "Walk")
            else:
                out["title"] = step.get("title") or "Break"
            out["links"] = [shown for shown in (_shown_link(link, tap_url, package_view) for link in step.get("links") or []) if shown]
            steps_out.append(out)
        days_out.append({
            "id": day.get("id") or LEGACY_DAY_ID,
            "number": d + 1,
            "title": day.get("title") or "",
            "starts_at": day.get("starts_at") or "",
            "minutes": sum(s["minutes"] for s in steps_out),
            "stop_count": number,
            "steps": steps_out,
        })
    view["days"] = days_out
    # App builds from before days read one list of steps.
    view["steps"] = [s for day in days_out for s in day["steps"]]
    return view


def _shown_link(link: dict, tap_url, package_view) -> Optional[dict]:
    if link.get("kind") == EXPERIENCE:
        package = package_view(link.get("package_id") or "")
        if package is None:
            return None
        return {
            "id": link["id"], "kind": EXPERIENCE, "partner": EXPERIENCE,
            "label": link.get("label") or package["title"],
            "package": package,
        }
    affiliate = AFFILIATES.get(link.get("partner"))
    if affiliate is None or not link.get("url"):
        return None
    return {
        "id": link["id"], "kind": AFFILIATE, "partner": affiliate.key,
        "partner_name": affiliate.name,
        "label": link.get("label") or f"Book on {affiliate.name}",
        "url": tap_url(link["id"]),
    }
