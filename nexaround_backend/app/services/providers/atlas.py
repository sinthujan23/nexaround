"""HelloSafe Atlas: real travel-insurance prices and tracked links for trips abroad.

Atlas quotes multiple underwriters (Chapka, Allianz, Europ Assistance, etc.)
and pays commissions on policies booked through its handoff. Unlike EKTA,
Atlas returns real premiums, guarantee ceilings (e.g. hospital fees abroad),
and allows Schengen-compliant visa intent quoting.

Requests are authenticated server-to-server with HMAC-SHA256 signatures (v2 scheme):
    x-atlas-key-id: ak_...
    x-atlas-timestamp: <unix_ts>
    x-atlas-signature: v2=<hmac_sha256>
where the signed message is:
    f"{ts}.{METHOD}.{pathname}.{raw_body}"
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
import time
import urllib.parse
from typing import Optional

from app.services.providers import base, config
from app.services.providers.money import format_amount

logger = logging.getLogger(__name__)

BASE_URL = "https://atlas.hellosafe.com"
QUOTES_PATH = "/api/v1/travel/quotes"
LINKS_PATH = "/api/v1/travel/links"

PARTNER_NAME = "HelloSafe travel insurance"
DEFAULT_BUTTON_LABEL = "Get travel insurance"
DEFAULT_ADULT_AGE = 30
TIMEOUT_S = 4.0
FRESH_TTL_S = 6 * 3600
STALE_TTL_S = 24 * 3600


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
    """True when a URL lands on HelloSafe or its Atlas redirection service."""
    parsed = urllib.parse.urlparse(str(url or "").strip())
    netloc = parsed.netloc.lower()
    return netloc in ("atlas.hellosafe.com", "hellosafe.com") or netloc.endswith(".hellosafe.com")


def plan_item(
    link: str,
    *,
    visa_needed: bool,
    insurer: str = "",
    price: Optional[float] = None,
    currency: str = "USD",
) -> dict:
    """The Booking Plan row for travel insurance.

    When a visa is required, the row is marked 'BOOK NOW' because embassies
    require proof of medical cover with the visa application.
    """
    partner_title = f"Travel insurance with {insurer}" if insurer else "Travel insurance with HelloSafe"
    price_suffix = f" · from {format_amount(price, currency)}" if price is not None else ""

    if visa_needed:
        return {
            "label": "BOOK NOW",
            "item": partner_title,
            "reason": (
                "Many embassies require travel medical insurance with the visa application. "
                f"Meets embassy medical requirements{price_suffix}. Compare plans on HelloSafe."
            ),
            "url": link,
        }
    return {
        "label": "BOOK CLOSER TO TRAVEL",
        "item": partner_title,
        "reason": (
            f"Covers medical costs, emergencies, and trip issues abroad{price_suffix}. "
            "Compare plans and guarantees on HelloSafe."
        ),
        "url": link,
    }


async def quote_and_mint(
    *,
    origin_country: str,
    dest_country: str,
    start_date: str,
    end_date: str,
    travelers: int = 1,
    currency: str = "USD",
    visa_needed: bool = False,
    trip_price: Optional[float] = None,
) -> Optional[dict]:
    """Fetch live quotes from Atlas and mint a tracked subscription link.

    Returns a dict with offer details and tracked link, or None if unavailable.
    """
    key_id = await config.setting(config.ATLAS_KEY_ID)
    secret = await config.setting(config.ATLAS_SIGNING_SECRET)
    if not (key_id and secret):
        return None

    orig = str(origin_country or "").strip().upper()
    dest = str(dest_country or "").strip().upper()
    if len(orig) != 2 or len(dest) != 2:
        return None

    # Atlas supports specific intent types
    intent = "schengenArea" if visa_needed else "forTourism"
    n_travelers = max(1, min(10, int(travelers or 1)))

    trip_payload = {
        "intent": intent,
        "startDate": str(start_date).strip(),
        "endDate": str(end_date).strip(),
        "countryResidence": orig,
        "arrivalCountries": [dest],
        "travellers": [{"age": DEFAULT_ADULT_AGE} for _ in range(n_travelers)],
        "currency": currency.upper() if currency else "USD",
    }
    if trip_price and float(trip_price) > 0:
        trip_payload["tripPrice"] = round(float(trip_price), 2)

    quotes_body = {
        "trip": trip_payload,
        "language": "en",
    }
    raw_quotes_body = json.dumps(quotes_body, separators=(",", ":"))
    quotes_headers = sign_request(key_id, secret, "POST", QUOTES_PATH, raw_quotes_body)

    cache_params = {
        "orig": orig,
        "dest": dest,
        "start": start_date,
        "end": end_date,
        "travelers": n_travelers,
        "intent": intent,
        "currency": currency.upper(),
    }

    quotes_fetched = await base.fetch(
        "atlas",
        "quotes",
        url=BASE_URL + QUOTES_PATH,
        cache_params=cache_params,
        fresh_ttl=FRESH_TTL_S,
        stale_ttl=STALE_TTL_S,
        timeout_s=TIMEOUT_S,
        method="POST",
        headers=quotes_headers,
        raw_body=raw_quotes_body,
    )
    if quotes_fetched.empty or not quotes_fetched.data:
        return None

    data = quotes_fetched.data
    session_id = data.get("sessionId")
    offers = data.get("offers") or []
    if not (session_id and offers):
        return None

    # Pick the cheapest priced offer
    priced_offers = [
        o for o in offers
        if isinstance(o, dict) and (o.get("price") or {}).get("amount") is not None
    ]
    if not priced_offers:
        return None

    cheapest = min(
        priced_offers,
        key=lambda o: float((o.get("price") or {}).get("amount") or float("inf")),
    )
    offer_id = cheapest.get("id")
    price_info = cheapest.get("price") or {}
    price_amount = float(price_info.get("amount") or 0.0)
    price_currency = str(price_info.get("currency") or currency or "USD").upper()
    insurer_name = str((cheapest.get("insurer") or {}).get("name") or "HelloSafe").strip()

    # Step 2: Mint a tracked link for this session and chosen offer
    links_body = {
        "sessionId": session_id,
        "trip": trip_payload,
        "language": "en",
        "offerId": offer_id,
        "linkCode": "odyssey_visa" if visa_needed else "odyssey_plan",
    }
    raw_links_body = json.dumps(links_body, separators=(",", ":"))
    links_headers = sign_request(key_id, secret, "POST", LINKS_PATH, raw_links_body)

    links_cache_params = {
        "session": session_id,
        "offer": offer_id,
    }

    links_fetched = await base.fetch(
        "atlas",
        "links",
        url=BASE_URL + LINKS_PATH,
        cache_params=links_cache_params,
        fresh_ttl=FRESH_TTL_S,
        stale_ttl=STALE_TTL_S,
        timeout_s=TIMEOUT_S,
        method="POST",
        headers=links_headers,
        raw_body=raw_links_body,
    )

    link_url = ""
    if not links_fetched.empty and links_fetched.data:
        link_url = str(links_fetched.data.get("url") or "").strip()

    if not link_url:
        # Fallback to general HelloSafe comparator if minting timed out
        link_url = f"https://hellosafe.com/travel-insurance?destination={dest}"

    return {
        "link": link_url,
        "session_id": session_id,
        "offer_id": offer_id,
        "price": price_amount,
        "currency": price_currency,
        "insurer": insurer_name,
        "visa_needed": visa_needed,
    }
