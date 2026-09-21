"""Pure formatting and validation rules for the Experiences marketplace.

Everything in here is a plain function over plain values: no database, no
network, no settings lookup. That is deliberate — `tests/` in this project is
pure-function-only, so this module is the part of the feature that can actually
be tested on this box. The rules most likely to break silently live here rather
than inline in a router.
"""

from typing import Optional

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

PRICE_BASES = ("per_person", "per_group", "from", "on_request")

_CURRENCY_SYMBOLS = {
    "USD": "$",
    "EUR": "€",
    "GBP": "£",
    "LKR": "Rs ",
    "INR": "₹",
    "AED": "AED ",
}


def resolve_package_point(
    vendor_lat: float,
    vendor_lng: float,
    uses_vendor_location: bool,
    override_lat: Optional[float] = None,
    override_lng: Optional[float] = None,
) -> tuple[float, float]:
    """Which point a package is searched by.

    The package's own coordinates are a copy of the vendor's unless the admin
    gave that package its own meeting point. Getting this wrong is invisible:
    the card still renders, the vendor is still right, and only the distance is
    quietly stale — so the rule lives in one tested function rather than being
    re-derived at each write site.
    """
    if uses_vendor_location:
        return vendor_lat, vendor_lng
    if override_lat is None or override_lng is None:
        # Asked for its own point but never given one: fall back to the vendor
        # rather than writing a NULL the NOT NULL column would reject anyway.
        return vendor_lat, vendor_lng
    return override_lat, override_lng


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
) -> str:
    """Human price for a card. `None` means the vendor quotes on request."""
    if amount is None or basis == "on_request":
        return "Price on request"

    symbol = _CURRENCY_SYMBOLS.get((currency or "").upper(), f"{currency} ")
    # Whole numbers read better without trailing zeros on a card.
    whole = float(amount)
    rendered = f"{whole:,.0f}" if whole == int(whole) else f"{whole:,.2f}"
    price = f"{symbol}{rendered}"

    if basis == "per_person":
        return f"{price} / person"
    if basis == "per_group":
        return f"{price} / group"
    if basis == "from":
        return f"From {price}"
    return price


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
