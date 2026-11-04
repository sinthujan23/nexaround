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
from decimal import ROUND_HALF_UP, Decimal
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


def is_published(vendor_active: bool, package_active: bool, approved: bool = True) -> bool:
    """Derived publish state. A package is only visible if its vendor is too,
    and once an admin has approved it (a vendor's new package waits)."""
    return bool(vendor_active) and bool(package_active) and bool(approved)


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


# --- Commission ----------------------------------------------------------------
#
# An admin types what the vendor gets for each price and the package's
# commission; what the traveller pays is worked out from the two, exact to the
# cent, every time the prices are saved. Vendors see only their own amounts.

def _cents(value: Decimal) -> float:
    return float(value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def _rate(percent) -> Decimal:
    return 1 + Decimal(str(percent or 0)) / 100


def with_commission(vendor_amount, percent) -> Optional[float]:
    """What the traveller pays: the vendor's amount with NexAround's
    commission on top. 12,000 at 25% -> 15,000."""
    if vendor_amount is None:
        return None
    return _cents(Decimal(str(vendor_amount)) * _rate(percent))


def without_commission(amount, percent) -> Optional[float]:
    """The vendor's amount inside a traveller's price, for an admin form from
    before commissions, which sends only the latter."""
    if amount is None:
        return None
    return _cents(Decimal(str(amount)) / _rate(percent))


def vendor_amount_of(option: Optional[dict]) -> Optional[float]:
    """What the vendor gets for an option, or a request's copy of one. Rows
    from before commissions have no `vendor_amount`: all of it was theirs."""
    if not option:
        return None
    value = option.get("vendor_amount")
    return _num(value if value is not None else option.get("amount"))


def commission_of(option: Optional[dict]) -> Optional[float]:
    """NexAround's share of an option's price (of a request's copy of one)."""
    amount, vendor = _num((option or {}).get("amount")), vendor_amount_of(option)
    if amount is None or vendor is None:
        return None
    return _cents(Decimal(str(amount)) - Decimal(str(vendor)))


def vendor_view_options(options: Optional[list[dict]]) -> list[dict]:
    """The options as the vendor reads them, their own amount as `amount`:
    no traveller price, dollars or commission."""
    return [
        {
            "id": o.get("id"),
            "amount": vendor_amount_of(o),
            "basis": o.get("basis") or "per_person",
            "min_people": o.get("min_people"),
            "max_people": o.get("max_people"),
        }
        for o in options or []
    ]


def commission_totals(rows: list[dict]) -> list[dict]:
    """The commission report's rows summed per vendor and currency, largest
    commission first. Each row has vendor_id, vendor_name, currency and the
    three amounts; a row with no price (on request) counts as a booking only."""
    totals: dict = {}
    for row in rows:
        key = (row.get("vendor_id"), row.get("currency"))
        total = totals.setdefault(key, {
            "vendor_id": row.get("vendor_id"),
            "vendor_name": row.get("vendor_name"),
            "currency": row.get("currency"),
            "bookings": 0,
            "traveller_amount": Decimal(0),
            "vendor_amount": Decimal(0),
            "commission_amount": Decimal(0),
        })
        total["bookings"] += 1
        for field in ("traveller_amount", "vendor_amount", "commission_amount"):
            if row.get(field) is not None:
                total[field] += Decimal(str(row[field]))
    out = [
        {**t, **{f: _cents(t[f]) for f in ("traveller_amount", "vendor_amount", "commission_amount")}}
        for t in totals.values()
    ]
    return sorted(out, key=lambda t: (-t["commission_amount"], t["vendor_name"] or ""))


def option_bounds(option: dict, package_max: Optional[int]) -> tuple[int, Optional[int]]:
    """Guests an option allows: a blank min is 1, a blank max the package's."""
    return int(option.get("min_people") or 1), option.get("max_people") or package_max


def too_many_guests(party_size: Optional[int], package_max: Optional[int]) -> Optional[str]:
    """The package's own maximum (a boat's seats), for a request with no price
    to check it against; None when it fits or there is no maximum."""
    if package_max and party_size and party_size > package_max:
        return f"This experience takes up to {package_max} guests."
    return None


def option_label(option: dict, currency: str, package_max: Optional[int]) -> str:
    """ "LKR 30,000 ($90) / group (max 7)", "LKR 8,000 ($24) / person (min 3)"."""
    least, most = option_bounds(option, package_max)
    return format_price(
        option.get("amount"), currency, option.get("basis") or "per_person",
        most, option.get("usd"), least,
    )


def vendor_option_label(snapshot: Optional[dict]) -> Optional[str]:
    """A request's chosen price as the vendor reads it: their own amount,
    never the traveller's price or NexAround's dollar price (both carry the
    commission). "LKR 8,000 / person (min 3)"; None for a price-on-request
    package."""
    amount = vendor_amount_of(snapshot)
    if amount is None:
        return None
    return option_label(
        {**snapshot, "amount": amount, "usd": None}, snapshot.get("currency") or "USD", None,
    )


def convert_price(
    amount: Optional[float], currency: str, usd: Optional[float],
    target: str, per_usd: dict,
) -> tuple[Optional[float], bool]:
    """A price in the traveller's chosen currency, and whether it is approximate.

    Display only: the booking stays at the vendor's price. Dollars use the
    admin's typed price when there is one (it is what the bracket shows), and
    other currencies go through it too, so every view agrees. (None, False)
    when there is no rate.
    """
    code, target = (currency or "USD").upper(), target.upper()
    if amount is None:
        return None, False
    if target == code:
        return float(amount), False
    if target == "USD" and usd is not None:
        return float(usd), False
    from_rate = 1.0 if code == "USD" else per_usd.get(code)
    base = float(usd) if usd is not None else (float(amount) / from_rate if from_rate else None)
    to_rate = 1.0 if target == "USD" else per_usd.get(target)
    if base is None or not to_rate:
        return None, False
    return base * float(to_rate), True


def display_label(
    option: dict, currency: str, package_max: Optional[int],
    target: Optional[str], per_usd: dict,
) -> Optional[str]:
    """ "≈ INR 10,850 / group (max 6)" for a traveller who picked INR; None
    when they picked nothing, or there is no rate for it."""
    if not target:
        return None
    value, approximate = convert_price(
        option.get("amount"), currency, option.get("usd"), target, per_usd,
    )
    if value is None:
        return None
    # Whole units read better; cents only for a small amount.
    value = round(value) if value >= 20 else round(value, 2)
    least, most = option_bounds(option, package_max)
    code = target.upper()
    label = format_price(value, code, option.get("basis") or "per_person", most, None, least)
    return label.replace(f"{code} ", f"≈ {code} ", 1) if approximate else label


def _sent_vendor_amount(raw: dict, percent, vendor: bool) -> Optional[float]:
    """The vendor's amount in a saved option. A vendor's `amount` is their own;
    an admin's form sends `vendor_amount`, and one from before commissions
    only the traveller's `amount`, which the commission comes back out of."""
    if vendor:
        return _num(raw.get("amount"))
    if raw.get("vendor_amount") is not None:
        return _num(raw["vendor_amount"])
    return without_commission(raw.get("amount"), percent)


def normalize_price_options(
    incoming: list[dict], existing: Optional[list[dict]], *,
    vendor: bool = False, percent=0,
) -> list[dict]:
    """Clean options from a form, keeping ids the package already has.

    An unknown or missing id gets a new one, so a request can name the option
    it was made for. A `vendor` may not set dollars: each option keeps the
    dollar price it had, by id; a new one has none. The traveller's price is
    worked out from the vendor's amount and `percent`.
    """
    old = {o.get("id"): o for o in existing or [] if o.get("id")}
    out, seen = [], set()
    for raw in incoming:
        option_id = raw.get("id")
        if option_id not in old or option_id in seen:
            option_id = _new_option_id()
        seen.add(option_id)
        usd = old.get(option_id, {}).get("usd") if vendor else raw.get("usd")
        vendor_amount = _sent_vendor_amount(raw, percent, vendor)
        out.append({
            "id": option_id,
            "vendor_amount": vendor_amount,
            "amount": with_commission(vendor_amount, percent),
            "usd": _num(usd),
            "basis": raw.get("basis") or "per_person",
            "min_people": raw.get("min_people") or None,
            "max_people": raw.get("max_people") or None,
        })
    return out


def legacy_price_options(
    existing: Optional[list[dict]], amount, usd, basis, *,
    vendor: bool = False, percent=0,
) -> list[dict]:
    """Options for a save that sent only the single price fields (an older
    form): the first option becomes that price and the others stay."""
    if amount is None or basis == "on_request":
        return []
    rest = list(existing or [])
    first = dict(rest.pop(0)) if rest else {"id": _new_option_id(), "min_people": None, "max_people": None}
    vendor_amount = _sent_vendor_amount({"amount": amount}, percent, vendor)
    first.update(
        vendor_amount=vendor_amount, amount=with_commission(vendor_amount, percent),
        usd=_num(usd), basis=basis or "per_person",
    )
    return [first, *rest]


def price_options_for_save(
    data, existing: Optional[list[dict]], *, vendor: bool = False, percent=0,
) -> list[dict]:
    """The options a package save stores. `data` is the validated payload and
    `percent` the package's commission.

    A vendor never sets dollars: their options keep the ones the admin typed.
    """
    if data.price_options is None:
        usd = (existing or [{}])[0].get("usd") if vendor else getattr(data, "price_usd", None)
        return legacy_price_options(
            existing, data.price_amount, usd, data.price_basis, vendor=vendor, percent=percent,
        )
    return normalize_price_options(
        [o.model_dump() for o in data.price_options], existing, vendor=vendor, percent=percent,
    )


def apply_price_options(package, options: list[dict]) -> None:
    """Store the options and mirror the first into the single price fields.

    The traveller's prices are worked out again from the vendor's amounts and
    the package's commission as it is now, so a commission changed since the
    options were made (a vendor's edit waiting for review) still applies.
    """
    percent = getattr(package, "commission_percent", None) or 0
    options = [
        {**o, "vendor_amount": vendor_amount_of(o),
         "amount": with_commission(vendor_amount_of(o), percent)}
        for o in options
    ]
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
    currency: str, package_max: Optional[int], percent=0,
) -> tuple[Optional[dict], Optional[str]]:
    """The option a request is for, as a snapshot, or the reason it can't be.

    No id means the first option: an app from before price options showed
    only that one. A price-on-request package has no option to pick. The
    snapshot keeps the split as it was (vendor's amount, commission and its
    `percent`): the package's prices may change later.
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
        "vendor_amount": vendor_amount_of(option),
        "commission_amount": commission_of(option),
        "commission_percent": _num(percent) or 0.0,
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
