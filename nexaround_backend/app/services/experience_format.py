"""Pure formatting and validation rules for the Experiences marketplace.

Everything in here is a plain function over plain values: no database, no
network, no settings lookup. That is deliberate — `tests/` in this project is
pure-function-only, so this module is the part of the feature that can actually
be tested on this box. The rules most likely to break silently live here rather
than inline in a router.
"""

import re
import uuid
from datetime import date, timedelta
from typing import Optional

# How far ahead a traveller may ask for a date on a package that sets no window
# of its own, and the longest window a package may set. The app's calendar
# stops at the same place.
DEFAULT_BOOKING_WINDOW_DAYS = 365
MAX_BOOKING_WINDOW_DAYS = 365

# How near "nearby" is. Beyond this the app shows the "showing the nearest"
# banner instead of a plain list. Lives server-side and is echoed in the
# response so it can be retuned without an app release.
NEARBY_THRESHOLD_M = 50_000

# The categories the Experiences tab chips are built from.
EXPERIENCE_CATEGORIES = (
    "boat",
    "water_sports",
    "guided_tour",
    "wildlife",
    "cultural",
    "adventure",
    "food",
    "other",
)

PRICE_BASES = ("per_person", "per_group", "per_hour", "from", "on_request")



def resolve_package_point(
    vendor_lat: Optional[float],
    vendor_lng: Optional[float],
    uses_vendor_location: bool,
    override_lat: Optional[float] = None,
    override_lng: Optional[float] = None,
) -> tuple[Optional[float], Optional[float]]:
    """Which point a package is searched by, or (None, None) when it has none.

    The package's own coordinates are a copy of the vendor's unless the admin
    gave that package its own meeting point. Getting this wrong is invisible:
    the card still renders, the vendor is still right, and only the distance is
    quietly stale — so the rule lives in one tested function rather than being
    re-derived at each write site.

    A vendor may have no exact location (only a country), and then a package
    that follows it has no point either. That is stored as NULL rather than a
    guess: a made-up point would draw a pin and a distance that are simply wrong.
    """
    if uses_vendor_location:
        return vendor_lat, vendor_lng
    if override_lat is None or override_lng is None:
        # Asked for its own point but never given one: fall back to the vendor.
        return vendor_lat, vendor_lng
    return override_lat, override_lng


def vendor_place_problem(
    latitude: Optional[float],
    longitude: Optional[float],
    country_code: Optional[str],
) -> Optional[str]:
    """Why a vendor's place cannot be saved, or None when it can.

    The exact location is optional; the country is not. Without a pin the
    country is the only thing a traveller can browse the vendor by, and with
    one it is read from the pin (or chosen) so the by-country list stays whole.
    """
    if (latitude is None) != (longitude is None):
        return "Latitude and longitude must be given together."
    if not (country_code or "").strip():
        return "Choose a country."
    return None


# `system_settings` key for how Experiences are browsed in the app.
COUNTRY_MODE_KEY = "experiences_country_mode"


def parse_country_mode(value: Optional[str]) -> bool:
    """True: browse Experiences by country. False: nearest first.

    On unless explicitly switched off, so a missing or garbled value can never
    flip the app back to a mode whose vendors may have no location.
    """
    return (value or "").strip().lower() not in ("false", "0", "off", "no")


def is_published(vendor_active: bool, package_active: bool) -> bool:
    """Derived publish state. A package is only visible if its vendor is too."""
    return bool(vendor_active) and bool(package_active)


def is_nearby(nearest_m: Optional[float], threshold_m: int = NEARBY_THRESHOLD_M) -> bool:
    """Whether the closest result is near enough to skip the distance banner."""
    if nearest_m is None:
        return False
    return nearest_m <= threshold_m


def format_price(
    amount: Optional[float],
    currency: str = "USD",
    basis: str = "per_person",
    max_participants: Optional[int] = None,
    usd: Optional[float] = None,
    min_people: Optional[int] = None,
) -> str:
    """Human price for a card. `None` means the vendor quotes on request.

    A group price carries the group size from the package's "Max
    participants" field: "QAR 499 / group (max 4)". The admin's typed dollar
    price follows in brackets: "QAR 499 ($137) / group (max 4)", none when the
    price is in dollars already. A price option's minimum shows when it is
    more than one: "LKR 8,000 ($24) / person (min 3)". Nothing is typed into
    the label itself; the price fields make it.
    """
    if amount is None or basis == "on_request":
        return "Price on request"

    # Whole numbers read better without trailing zeros on a card.
    def rendered(value: float) -> str:
        value = float(value)
        return f"{value:,.0f}" if value == int(value) else f"{value:,.2f}"

    # Always the ISO code ("INR 7,500", "QAR 499"), never a symbol: a list
    # mixing "₹7,500" with "INR 13,037" reads as two systems. The bracket
    # alone uses "$", the client's choice.
    code = (currency or "USD").strip().upper()
    price = f"{code} {rendered(amount)}"
    if usd is not None and code != "USD":
        price = f"{price} (${rendered(usd)})"

    least = f"min {min_people}" if min_people and min_people > 1 else None
    if basis == "per_person":
        return f"{price} / person" + (f" ({least})" if least else "")
    if basis == "per_group":
        size = ", ".join(
            p for p in (least, f"max {max_participants}" if max_participants else None) if p
        )
        return f"{price} / group" + (f" ({size})" if size else "")
    if basis == "per_hour":
        return f"{price} / hour" + (f" ({least})" if least else "")
    if basis == "from":
        return f"From {price}" + (f" ({least})" if least else "")
    return price


# --- Price options -----------------------------------------------------------
#
# A package may be sold at several prices ("LKR 30,000 per trip, max 7" or
# "LKR 8,000 per person, min 3"). They live in `price_options`, first one first;
# the first is mirrored into price_amount / price_usd / price_basis, which
# older apps, share text and emails read.

# What a price option may be: every basis but "on_request", which is no
# option at all.
OPTION_BASES = ("per_person", "per_group", "per_hour", "from")
MAX_PRICE_OPTIONS = 6


def _new_option_id() -> str:
    return uuid.uuid4().hex[:8]


def _num(value) -> Optional[float]:
    return None if value is None else float(value)


def option_bounds(option: dict, package_max: Optional[int]) -> tuple[int, Optional[int]]:
    """Guests an option allows: a blank min is 1, a blank max the package's."""
    return int(option.get("min_people") or 1), option.get("max_people") or package_max


def option_label(option: dict, currency: str, package_max: Optional[int]) -> str:
    """ "LKR 30,000 ($90) / group (max 7)", "LKR 8,000 ($24) / person (min 3)"."""
    least, most = option_bounds(option, package_max)
    return format_price(
        option.get("amount"), currency, option.get("basis") or "per_person",
        most, option.get("usd"), least,
    )


def normalize_price_options(
    incoming: list[dict], existing: Optional[list[dict]], *, keep_usd: bool = False,
) -> list[dict]:
    """Clean options from a form, keeping ids the package already has.

    An unknown or missing id gets a new one, so a request can name the option
    it was made for. With `keep_usd` (a vendor's save, who may not set dollars)
    each option keeps the dollar price it had, by id; a new one has none.
    """
    old = {o.get("id"): o for o in existing or [] if o.get("id")}
    out, seen = [], set()
    for raw in incoming:
        option_id = raw.get("id")
        if option_id not in old or option_id in seen:
            option_id = _new_option_id()
        seen.add(option_id)
        usd = old.get(option_id, {}).get("usd") if keep_usd else raw.get("usd")
        out.append({
            "id": option_id,
            "amount": _num(raw.get("amount")),
            "usd": _num(usd),
            "basis": raw.get("basis") or "per_person",
            "min_people": raw.get("min_people") or None,
            "max_people": raw.get("max_people") or None,
        })
    return out


def legacy_price_options(
    existing: Optional[list[dict]], amount, usd, basis,
) -> list[dict]:
    """Options for a save that sent only the single price fields (an older
    form): the first option becomes that price and the others stay."""
    if amount is None or basis == "on_request":
        return []
    rest = list(existing or [])
    first = dict(rest.pop(0)) if rest else {"id": _new_option_id(), "min_people": None, "max_people": None}
    first.update(amount=_num(amount), usd=_num(usd), basis=basis or "per_person")
    return [first, *rest]


def price_options_for_save(data, existing: Optional[list[dict]], *, vendor: bool = False) -> list[dict]:
    """The options a package save stores. `data` is the validated payload.

    A vendor never sets dollars: their options keep the ones the admin typed.
    """
    if data.price_options is None:
        usd = (existing or [{}])[0].get("usd") if vendor else getattr(data, "price_usd", None)
        return legacy_price_options(existing, data.price_amount, usd, data.price_basis)
    return normalize_price_options(
        [o.model_dump() for o in data.price_options], existing, keep_usd=vendor,
    )


def apply_price_options(package, options: list[dict]) -> None:
    """Store the options and mirror the first into the single price fields."""
    package.price_options = options
    if options:
        first = options[0]
        package.price_amount = first["amount"]
        package.price_usd = first["usd"]
        package.price_basis = first["basis"]
    else:
        package.price_amount = None
        package.price_usd = None


def pick_price_option(
    options: Optional[list[dict]], option_id: Optional[str], party_size: Optional[int],
    currency: str, package_max: Optional[int],
) -> tuple[Optional[dict], Optional[str]]:
    """The option a request is for, as a snapshot, or the reason it can't be.

    No id means the first option: an app from before price options showed
    only that one. A price-on-request package has no option to pick.
    """
    if not options:
        return None, None
    if option_id:
        option = next((o for o in options if o.get("id") == option_id), None)
        if option is None:
            return None, (
                "The prices for this experience have changed. "
                "Please go back and choose a price again."
            )
    else:
        option = options[0]
    least, most = option_bounds(option, package_max)
    if party_size is not None and party_size < least:
        return None, f"This price is for at least {least} guests."
    if party_size is not None and most and party_size > most:
        return None, f"This price is for up to {most} guests."
    snapshot = {
        **option,
        "currency": currency,
        "label": option_label(option, currency, package_max),
    }
    return snapshot, None


def format_duration(minutes: Optional[int]) -> str:
    """`90 -> '1h 30m'`, `60 -> '1h'`, `45 -> '45m'`, `None -> ''`."""
    if not minutes or minutes <= 0:
        return ""
    hours, mins = divmod(int(minutes), 60)
    if hours and mins:
        return f"{hours}h {mins}m"
    if hours:
        return f"{hours}h"
    return f"{mins}m"


def normalize_phone(raw: Optional[str]) -> Optional[str]:
    """Digits (and a leading +) only, for a `tel:` link."""
    if not raw:
        return None
    cleaned = "".join(ch for ch in raw if ch.isdigit() or ch == "+")
    cleaned = "+" + cleaned.replace("+", "") if cleaned.startswith("+") else cleaned.replace("+", "")
    digits = cleaned.lstrip("+")
    if len(digits) < 7:
        return None
    return cleaned


def whatsapp_number(raw: Optional[str]) -> Optional[str]:
    """Digits only — `wa.me` rejects a leading '+'."""
    if not raw:
        return None
    digits = "".join(ch for ch in raw if ch.isdigit())
    if len(digits) < 7:
        return None
    return digits


def validate_enquiry_payload(payload: dict) -> list[str]:
    """Server-side enquiry rules, mirrored by the Dart form validator."""
    errors: list[str] = []

    name = (payload.get("contact_name") or "").strip()
    if len(name) < 2:
        errors.append("Please enter your name.")

    if not whatsapp_number(payload.get("contact_phone")):
        errors.append("Please enter a valid phone number.")

    email = (payload.get("contact_email") or "").strip()
    if email and ("@" not in email or "." not in email.split("@")[-1]):
        errors.append("Please enter a valid email address.")

    party_size = payload.get("party_size")
    if party_size is not None and (party_size < 1 or party_size > 100):
        errors.append("Party size must be between 1 and 100.")

    message = payload.get("message") or ""
    if len(message) > 2000:
        errors.append("Message is too long.")

    return errors


def booking_window_error(
    preferred: Optional[date],
    today: date,
    window_days: Optional[int] = None,
) -> Optional[str]:
    """Why a traveller may not ask for `preferred`, or None when they may.

    `window_days` is the package's own window; None means the platform
    default. `today` is the server's UTC date, and the traveller's own date can
    be a day either side of it, so each end allows one day of slack rather
    than refusing a date the app's calendar offered.
    """
    if preferred is None:
        return None
    if preferred < today - timedelta(days=1):
        return "Please choose a date that hasn't passed."
    window = window_days or DEFAULT_BOOKING_WINDOW_DAYS
    if preferred > today + timedelta(days=window + 1):
        days = "1 day" if window == 1 else f"{window} days"
        return f"This experience can only be booked up to {days} ahead."
    return None


# --- Dates a package cannot be booked ----------------------------------------
#
# Stored on the package as a list of inclusive ranges, `[{"start": "2026-11-01",
# "end": "2026-11-05"}]`, with ISO dates so the JSON is the same in the
# database, the admin panel, the partner portal and the app. A single blocked
# day is a range whose start and end are equal. Anything not covered is
# available.

MAX_UNAVAILABLE_RANGES = 200


def merge_date_ranges(ranges) -> list[dict]:
    """Sorted, with overlapping and touching ranges joined.

    `ranges` is anything iterable of objects (or dicts) with `start` and `end`.
    Touching means the next starts the day after the previous ends: Nov 1-3 and
    Nov 4-6 are one block, Nov 1-3 and Nov 5-6 are two.
    """
    pairs = []
    for r in ranges:
        start = r["start"] if isinstance(r, dict) else r.start
        end = r["end"] if isinstance(r, dict) else r.end
        start = date.fromisoformat(start) if isinstance(start, str) else start
        end = date.fromisoformat(end) if isinstance(end, str) else end
        if end < start:
            start, end = end, start
        pairs.append((start, end))
    pairs.sort()

    merged: list[list[date]] = []
    for start, end in pairs:
        if merged and start <= merged[-1][1] + timedelta(days=1):
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return [{"start": a.isoformat(), "end": b.isoformat()} for a, b in merged]


def is_date_unavailable(day: Optional[date], ranges) -> bool:
    """Whether `day` falls inside any stored range. `ranges` may be None."""
    if day is None:
        return False
    for r in ranges or []:
        if date.fromisoformat(r["start"]) <= day <= date.fromisoformat(r["end"]):
            return True
    return False


def unavailable_error(preferred: Optional[date], ranges) -> Optional[str]:
    """Why a traveller may not ask for `preferred`, or None when it is open."""
    if is_date_unavailable(preferred, ranges):
        return "That date is not available for this experience. Please choose another date."
    return None


def package_field_value(data, key: str):
    """The value to store for `key` from a validated package payload: a plain
    copy for most, merged JSON-ready dicts for the unavailable dates."""
    value = getattr(data, key)
    if key == "unavailable_ranges":
        return merge_date_ranges(value or [])
    if key == "region_label":
        # A cleared text box arrives as "", which should show nothing.
        return (value or "").strip() or None
    return value


# --- Description formatting --------------------------------------------------
#
# A package description is stored as light Markdown: `#`/`##`/`###` headings,
# `**bold**`, `*italic*`, `- ` / `1. ` lists and a `---` divider. That is all
# the admin and partner editors can write. App versions that predate the
# formatting would print those symbols, so the API's plain `description` is the
# same text with the symbols removed, and the formatted text travels separately.

_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+")
_DIVIDER = re.compile(r"^\s*([-*_])(\s*\1){2,}\s*$")
_BULLET = re.compile(r"^(\s*)[-*+]\s+")
_BOLD = re.compile(r"(\*\*|__)(?=\S)(.+?)(?<=\S)\1")
_ITALIC = re.compile(r"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])")


def strip_markdown(text: Optional[str]) -> Optional[str]:
    """`text` with the formatting symbols removed and its line breaks kept.

    None and "" come back unchanged so a package with no description still
    reads as having none.
    """
    if not text:
        return text
    lines: list[str] = []
    for line in text.replace("\r\n", "\n").split("\n"):
        if _DIVIDER.match(line):
            lines.append("")
            continue
        line = _HEADING.sub("", line)
        line = _BULLET.sub(lambda m: f"{m.group(1)}\u2022 ", line)
        line = _BOLD.sub(r"\2", line)
        line = _ITALIC.sub(r"\1", line)
        lines.append(line.rstrip())
    out = "\n".join(lines)
    return re.sub(r"\n{3,}", "\n\n", out).strip()
