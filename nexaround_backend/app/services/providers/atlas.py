"""HelloSafe Atlas: travel-insurance prices and tracked links for trips abroad.

Atlas prices a trip against many insurers (Chapka, Allianz, Europ Assistance…)
and pays a commission on policies bought through a link it mints for us. The
API reference is public: https://atlas.hellosafe.com/openapi.json.

Three of Atlas's rules shape this module:
- One quoting session per traveller. A session's link resumes the same
  subscription, so two travellers must never share one. A plan therefore holds
  no Atlas link: it holds `tap_url()`, our own signed URL, and the session and
  link are made when that traveller taps it (`tap_target`, api/v1/go.py).
- No long-lived caching (API terms). Quotes are kept 25 minutes (sessions
  expire after 30) and never served stale.
- The insurer is named wherever a price is shown (API terms).

NexAround makes no claim about cover: the plan shows the lowest price, and
HelloSafe's pages present the guarantees.

Requests are signed server to server with HMAC-SHA256 (v2 scheme):
    x-atlas-key-id: ak_...
    x-atlas-timestamp: <unix_ts>
    x-atlas-signature: v2=<hmac_sha256>
where the signed message is f"{ts}.{METHOD}.{pathname}.{raw_body}".
"""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import hmac
import json
import logging
import time
import urllib.parse
from typing import Optional

from app.core.config import settings
from app.services.providers import base, config

logger = logging.getLogger(__name__)

BASE_URL = "https://atlas.hellosafe.com"
QUOTES_PATH = "/api/v1/travel/quotes"
LINKS_PATH = "/api/v1/travel/links"
# HelloSafe's own quote form: where a tap lands when no tracked link can be made.
FUNNEL_URL = "https://hellosafe.com/travel-insurance/app"
# Our endpoint behind the plan's insurance button (api/v1/go.py).
TAP_PATH = "/api/v1/go/insurance"

BUTTON_LABEL = "Get travel insurance"
DEFAULT_ADULT_AGE = 30
PLAN_TIMEOUT_S = 4.0   # priced while Gemini writes the plan; nobody waits on it
TAP_TIMEOUT_S = 6.0    # a traveller is looking at a blank page
QUOTE_TTL_S = 25 * 60  # sessions expire after 30 minutes
LINK_TTL_S = 25 * 60

TOURISM = "forTourism"
SCHENGEN = "schengenArea"

# The Schengen members, and the microstates entered only through them. A
# traveller who needs a visa for one of these gets the Schengen-compliant quote.
SCHENGEN_COUNTRIES = frozenset({
    "AT", "BE", "BG", "CH", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR",
    "HU", "IS", "IT", "LI", "LT", "LU", "LV", "MT", "NL", "NO", "PL", "PT", "RO",
    "SE", "SI", "SK",
    "AD", "MC", "SM", "VA",
})


def sign_request(key_id: str, secret: str, method: str, path: str, body_str: str = "") -> dict[str, str]:
    """Build the required Atlas v2 HMAC-SHA256 signed headers."""
    ts = str(int(time.time()))
    message = f"{ts}.{method.upper()}.{path}.{body_str}"
    sig = "v2=" + hmac.new(secret.encode("utf-8"), message.encode("utf-8"), hashlib.sha256).hexdigest()
    return {
        "content-type": "application/json",
        "x-atlas-key-id": key_id,
        "x-atlas-timestamp": ts,
        "x-atlas-signature": sig,
    }


def is_atlas_link(url: str) -> bool:
    """True for HelloSafe's own pages and for our tap URL in front of them."""
    parsed = urllib.parse.urlparse(str(url or "").strip())
    netloc = parsed.netloc.lower()
    if parsed.path == TAP_PATH:
        return True
    return netloc in ("atlas.hellosafe.com", "hellosafe.com") or netloc.endswith(".hellosafe.com")


# ── The trip ─────────────────────────────────────────────────────────────────

def intents_for(residence: str, destination: str) -> list[str]:
    """The quotes a plan asks for before it knows whether a visa is needed.

    Visa status comes from Gemini, after the fetches start, so a trip into the
    Schengen area from outside it is priced both ways and the plan keeps the
    one its visa answer calls for.
    """
    if destination.upper() in SCHENGEN_COUNTRIES and residence.upper() not in SCHENGEN_COUNTRIES:
        return [TOURISM, SCHENGEN]
    return [TOURISM]


def _iso_date(value: str) -> Optional[dt.date]:
    try:
        return dt.date.fromisoformat(str(value or "").strip())
    except ValueError:
        return None


def trip(
    *,
    residence: str,
    destination: str,
    start_date: str,
    end_date: str,
    travelers: int,
    intent: str = TOURISM,
) -> Optional[dict]:
    """The Atlas `trip` for a plan, or None when it cannot be priced.

    Priced in USD, so one cached answer serves every traveller; the plan
    converts it. Odyssey asks for no ages, so every traveller is an adult of
    DEFAULT_ADULT_AGE, which is why the plan says "from".
    """
    orig = str(residence or "").strip().upper()
    dest = str(destination or "").strip().upper()
    start, end = _iso_date(start_date), _iso_date(end_date)
    if len(orig) != 2 or len(dest) != 2 or orig == dest or intent not in (TOURISM, SCHENGEN):
        return None
    if start is None or end is None or end < start:
        return None
    return {
        "intent": intent,
        "startDate": start.isoformat(),
        "endDate": end.isoformat(),
        "countryResidence": orig,
        "arrivalCountries": [dest],
        "travellers": [{"age": DEFAULT_ADULT_AGE} for _ in range(max(1, min(10, int(travelers or 1))))],
        "currency": "USD",
    }


# ── Atlas calls ──────────────────────────────────────────────────────────────

async def _credentials() -> Optional[tuple[str, str]]:
    key_id = await config.setting(config.ATLAS_KEY_ID)
    secret = await config.setting(config.ATLAS_SIGNING_SECRET)
    return (key_id, secret) if key_id and secret else None


def _cheapest(data) -> dict:
    """The cheapest priced offer and the session that priced it; {} for none."""
    data = data if isinstance(data, dict) else {}
    offers = [
        o for o in data.get("offers") or []
        if isinstance(o, dict) and (o.get("price") or {}).get("amount") is not None
    ]
    session = str(data.get("sessionId") or "")
    if not (offers and session):
        return {}
    best = min(offers, key=lambda o: float(o["price"]["amount"]))
    return {
        "session_id": session,
        "offer_id": best.get("id"),
        "price": float(best["price"]["amount"]),
        "currency": str(best["price"].get("currency") or "USD").upper(),
        "insurer": str((best.get("insurer") or {}).get("name") or "").strip() or "HelloSafe",
        "offers": len(offers),
    }


async def quote(trip: dict, *, traveller: str = "", timeout_s: float = PLAN_TIMEOUT_S) -> Optional[dict]:
    """The cheapest offer for a trip (see `_cheapest`), or None.

    `traveller` keeps one person's session to themselves. A plan's quote is
    shared by every plan with the same trip, which is safe only because its
    session never mints a link; a tap's quote is that traveller's alone.
    """
    creds = await _credentials()
    if not creds:
        return None
    body = json.dumps({"trip": trip, "language": "en"}, separators=(",", ":"))
    fetched = await base.fetch(
        "atlas", "quotes",
        url=BASE_URL + QUOTES_PATH,
        cache_params={**trip, "traveller": traveller},
        fresh_ttl=QUOTE_TTL_S,
        empty_ttl=QUOTE_TTL_S,
        timeout_s=timeout_s,
        method="POST",
        headers=sign_request(*creds, "POST", QUOTES_PATH, body),
        raw_body=body,
        transform=_cheapest,
        is_empty=lambda d: not d,
    )
    return fetched.data if fetched.ok else None


async def mint_link(trip: dict, session_id: str, *, timeout_s: float = TAP_TIMEOUT_S) -> str:
    """The tracked link for one traveller's session, or "".

    No `offerId`: the traveller lands on HelloSafe's offer list and chooses
    there, which keeps the choice of cover theirs and HelloSafe's.
    """
    creds = await _credentials()
    if not creds or not session_id:
        return ""
    body = json.dumps({"sessionId": session_id, "trip": trip, "language": "en"}, separators=(",", ":"))
    fetched = await base.fetch(
        "atlas", "links",
        url=BASE_URL + LINKS_PATH,
        cache_params={"session": session_id},
        fresh_ttl=LINK_TTL_S,
        timeout_s=timeout_s,
        method="POST",
        headers=sign_request(*creds, "POST", LINKS_PATH, body),
        raw_body=body,
        transform=lambda d: str((d or {}).get("url") or "").strip() if isinstance(d, dict) else "",
        is_empty=lambda url: not url,
    )
    return fetched.data if fetched.ok else ""


def funnel_url(trip: dict) -> str:
    """HelloSafe's quote form with the trip filled in. Credits no one."""
    return FUNNEL_URL + "?" + urllib.parse.urlencode({
        "countryResidence": trip["countryResidence"],
        "arrivalCountries": ",".join(trip["arrivalCountries"]),
        "nbTravellers": len(trip["travellers"]),
        "intent": trip["intent"],
    })


# ── The plan's button ────────────────────────────────────────────────────────

def _sig(payload: str) -> str:
    key = settings.SECRET_KEY.encode("utf-8")
    return hmac.new(key, f"atlas-tap.{payload}".encode("utf-8"), hashlib.sha256).hexdigest()[:32]


def tap_url(trip: dict) -> str:
    """The plan's link: our endpoint, signed, so only a trip we priced is asked for."""
    fields = [
        trip["countryResidence"], trip["arrivalCountries"][0], trip["startDate"],
        trip["endDate"], len(trip["travellers"]), trip["intent"],
    ]
    payload = base64.urlsafe_b64encode(
        json.dumps(fields, separators=(",", ":")).encode("utf-8")
    ).decode("ascii").rstrip("=")
    return f"{settings.PUBLIC_BASE_URL.rstrip('/')}{TAP_PATH}?t={payload}.{_sig(payload)}"


def trip_from_token(token: str) -> Optional[dict]:
    """The trip a tap URL's `t` names, or None when we did not sign it."""
    payload, _, sig = str(token or "").partition(".")
    if not payload or not hmac.compare_digest(sig, _sig(payload)):
        return None
    try:
        raw = base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
        residence, destination, start, end, travelers, intent = json.loads(raw)
    except Exception:
        return None
    return trip(
        residence=residence, destination=destination, start_date=start,
        end_date=end, travelers=travelers, intent=intent,
    )


async def tap_target(trip: dict, *, traveller: str) -> str:
    """Where a tap on the plan's button goes.

    A tracked link made for this traveller while Atlas is live and the trip is
    still ahead; otherwise HelloSafe's form for the trip, so the traveller is
    never stranded, though that sale is credited to no one.
    """
    start = _iso_date(trip["startDate"])
    if await config.mode("atlas") == config.LIVE and start and start >= dt.date.today():
        priced = await quote(trip, traveller=traveller, timeout_s=TAP_TIMEOUT_S)
        if priced:
            link = await mint_link(trip, priced["session_id"])
            if link:
                return link
            logger.info("atlas: no tracked link for session; sending the tap to the form")
    return funnel_url(trip)


def button_label(amount: str, insurer: str) -> str:
    """"Insurance from INR 1,520 · Chapka": the insurer stays with the price,
    and short, since the button is one line (partner_pill.dart)."""
    return f"Insurance from {amount} · {insurer}" if amount else BUTTON_LABEL


def plan_item(url: str, *, visa_needed: bool, amount: str = "", insurer: str = "", travelers: int = 1) -> dict:
    """The Booking Plan row for travel insurance. It names no cover.

    With a visa to get, the row is "BOOK NOW": many embassies ask for travel
    medical insurance with the application.
    """
    party = f" for {travelers} travellers" if travelers > 1 else ""
    offer = f"From {amount}{party} with {insurer}. " if amount and insurer else ""
    if visa_needed:
        label = "BOOK NOW"
        reason = (
            "Many embassies ask for travel medical insurance with a visa application. "
            f"{offer}Compare plans and cover on HelloSafe."
        )
    else:
        label = "BOOK CLOSER TO TRAVEL"
        reason = f"{offer}Compare plans and cover for this trip on HelloSafe."
    return {"label": label, "item": "Travel insurance on HelloSafe", "reason": reason, "url": url}
