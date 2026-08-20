"""Is this budget capable of buying the trip at all?

Someone asking for three days in Dubai on 200 LKR — about 70 US cents — cannot
be served by any itinerary, and generating one costs a Gemini call, a SerpAPI
flight lookup and a hotel lookup before producing something the user has to
throw away. This module answers the question before any of that is spent.

Two principles shape every number below:

  * **The floor is a floor.** Figures are hostel-and-street-food minimums, not
    realistic budgets. They exist to separate "impossible" from "tight", and
    being too low is the safe direction.
  * **Silence beats a wrong answer.** `minimum_budget` returns None whenever the
    destination cannot be identified confidently, and the caller must then let
    the request through. Blocking a real trip is a far worse failure than
    letting an absurd one reach the model.
"""
from typing import Optional


# Daily on-the-ground minimum per traveller, in USD: a dorm bed, street food and
# public transport. Deliberately austere — a real trip costs multiples of this.
DAILY_FLOOR_USD: dict[str, float] = {
    "budget": 20.0,
    "moderate": 35.0,
    "upper": 60.0,
    "expensive": 90.0,
    "premium": 140.0,
}

DEFAULT_TIER = "moderate"

# Cheapest plausible return airfare for any international hop, per traveller.
# One flat figure rather than a distance model: this is a floor, and a Colombo
# –Chennai hop should not be judged against a Colombo–London fare.
INTERNATIONAL_FLIGHT_FLOOR_USD = 120.0

COUNTRY_TIER: dict[str, str] = {
    # South and Southeast Asia
    "LK": "budget", "IN": "budget", "NP": "budget", "BD": "budget",
    "PK": "budget", "VN": "budget", "KH": "budget", "LA": "budget",
    "ID": "budget", "MM": "budget", "PH": "budget",
    "TH": "moderate", "MY": "moderate", "CN": "moderate", "MV": "expensive",
    # Middle East
    "AE": "upper", "QA": "upper", "SA": "upper", "OM": "upper",
    "BH": "upper", "KW": "upper", "TR": "moderate", "JO": "moderate",
    "IL": "expensive",
    # Europe
    "GB": "expensive", "FR": "expensive", "DE": "expensive", "NL": "expensive",
    "BE": "expensive", "AT": "expensive", "IE": "expensive", "IT": "upper",
    "ES": "upper", "PT": "upper", "GR": "upper", "CZ": "upper", "PL": "moderate",
    "HU": "moderate", "RO": "moderate", "HR": "upper",
    "CH": "premium", "NO": "premium", "IS": "premium", "DK": "premium",
    "SE": "expensive", "FI": "expensive",
    # Americas
    "US": "expensive", "CA": "expensive", "MX": "moderate", "BR": "moderate",
    "AR": "moderate", "CO": "budget", "PE": "budget", "CL": "moderate",
    # Africa
    "EG": "budget", "MA": "moderate", "ZA": "moderate", "KE": "moderate",
    "TZ": "moderate", "NG": "moderate",
    # Asia-Pacific
    "JP": "expensive", "KR": "upper", "TW": "upper", "HK": "expensive",
    "SG": "expensive", "AU": "expensive", "NZ": "expensive",
}

# Destination strings arrive as free text ("Dubai", "Dubai, UAE", "dubai uae").
# Only well-known, unambiguous names belong here: an entry that guesses wrong
# blocks a real trip, while a missing entry merely lets one through.
PLACE_COUNTRY: dict[str, str] = {
    # Sri Lanka — the common domestic case, where no flight floor applies
    "sri lanka": "LK", "colombo": "LK", "kandy": "LK", "galle": "LK",
    "jaffna": "LK", "trincomalee": "LK", "ella": "LK", "sigiriya": "LK",
    "nuwara eliya": "LK", "anuradhapura": "LK", "negombo": "LK",
    "mirissa": "LK", "arugam bay": "LK", "batticaloa": "LK", "matara": "LK",
    "kinniya": "LK", "dambulla": "LK", "polonnaruwa": "LK", "hikkaduwa": "LK",
    # Middle East
    "dubai": "AE", "abu dhabi": "AE", "uae": "AE",
    "united arab emirates": "AE", "sharjah": "AE",
    "doha": "QA", "qatar": "QA", "riyadh": "SA", "jeddah": "SA",
    "saudi arabia": "SA", "muscat": "OM", "oman": "OM",
    "kuwait": "KW", "bahrain": "BH", "manama": "BH",
    "istanbul": "TR", "turkey": "TR", "antalya": "TR",
    # South and Southeast Asia
    "india": "IN", "delhi": "IN", "mumbai": "IN", "chennai": "IN",
    "bangalore": "IN", "goa": "IN", "kerala": "IN", "kochi": "IN",
    "jaipur": "IN", "agra": "IN",
    "nepal": "NP", "kathmandu": "NP", "pokhara": "NP",
    "maldives": "MV", "male": "MV",
    "bangkok": "TH", "thailand": "TH", "phuket": "TH", "chiang mai": "TH",
    "krabi": "TH", "pattaya": "TH",
    "singapore": "SG",
    "malaysia": "MY", "kuala lumpur": "MY", "penang": "MY", "langkawi": "MY",
    "vietnam": "VN", "hanoi": "VN", "ho chi minh": "VN", "da nang": "VN",
    "indonesia": "ID", "bali": "ID", "jakarta": "ID",
    "cambodia": "KH", "siem reap": "KH", "phnom penh": "KH",
    "philippines": "PH", "manila": "PH", "cebu": "PH", "boracay": "PH",
    "japan": "JP", "tokyo": "JP", "osaka": "JP", "kyoto": "JP",
    "south korea": "KR", "seoul": "KR", "busan": "KR",
    "china": "CN", "beijing": "CN", "shanghai": "CN",
    "hong kong": "HK", "taiwan": "TW", "taipei": "TW",
    # Europe
    "london": "GB", "united kingdom": "GB", "uk": "GB", "england": "GB",
    "scotland": "GB", "edinburgh": "GB", "manchester": "GB",
    "paris": "FR", "france": "FR", "nice": "FR",
    "germany": "DE", "berlin": "DE", "munich": "DE", "frankfurt": "DE",
    "amsterdam": "NL", "netherlands": "NL",
    "italy": "IT", "rome": "IT", "milan": "IT", "venice": "IT",
    "florence": "IT", "naples": "IT",
    "spain": "ES", "barcelona": "ES", "madrid": "ES", "seville": "ES",
    "portugal": "PT", "lisbon": "PT", "porto": "PT",
    "greece": "GR", "athens": "GR", "santorini": "GR", "mykonos": "GR",
    "switzerland": "CH", "zurich": "CH", "geneva": "CH", "interlaken": "CH",
    "norway": "NO", "oslo": "NO", "iceland": "IS", "reykjavik": "IS",
    "denmark": "DK", "copenhagen": "DK", "sweden": "SE", "stockholm": "SE",
    "finland": "FI", "helsinki": "FI",
    "prague": "CZ", "czech republic": "CZ", "vienna": "AT", "austria": "AT",
    "poland": "PL", "warsaw": "PL", "krakow": "PL",
    "hungary": "HU", "budapest": "HU", "croatia": "HR", "dubrovnik": "HR",
    "ireland": "IE", "dublin": "IE", "belgium": "BE", "brussels": "BE",
    # Americas
    "usa": "US", "united states": "US", "new york": "US", "los angeles": "US",
    "san francisco": "US", "las vegas": "US", "miami": "US", "chicago": "US",
    "canada": "CA", "toronto": "CA", "vancouver": "CA", "montreal": "CA",
    "mexico": "MX", "cancun": "MX", "mexico city": "MX",
    "brazil": "BR", "rio de janeiro": "BR", "sao paulo": "BR",
    "argentina": "AR", "buenos aires": "AR", "peru": "PE", "lima": "PE",
    "colombia": "CO", "chile": "CL",
    # Africa and Oceania
    "egypt": "EG", "cairo": "EG", "morocco": "MA", "marrakech": "MA",
    "south africa": "ZA", "cape town": "ZA", "johannesburg": "ZA",
    "kenya": "KE", "nairobi": "KE", "tanzania": "TZ", "zanzibar": "TZ",
    "australia": "AU", "sydney": "AU", "melbourne": "AU",
    "new zealand": "NZ", "auckland": "NZ", "queenstown": "NZ",
}

# Units of each currency per 1 USD. Used only to compare a budget against a
# floor, never to price anything, so drift of a few percent is immaterial —
# the decision it feeds is "is this three orders of magnitude short?".
FX_PER_USD: dict[str, float] = {
    "USD": 1.0, "LKR": 300.0, "INR": 83.0, "EUR": 0.92, "GBP": 0.79,
    "AUD": 1.52, "CAD": 1.36, "JPY": 150.0, "CNY": 7.24, "SGD": 1.34,
    "MYR": 4.70, "THB": 36.0, "AED": 3.67, "SAR": 3.75, "QAR": 3.64,
    "CHF": 0.88, "NZD": 1.64, "ZAR": 18.5, "TRY": 32.0, "IDR": 15700.0,
    "PHP": 56.0, "VND": 25000.0, "PKR": 278.0, "BDT": 110.0, "NPR": 133.0,
    "MVR": 15.4, "KRW": 1330.0, "HKD": 7.82, "TWD": 32.0, "BRL": 5.05,
    "MXN": 17.0, "EGP": 48.0, "MAD": 10.0, "KES": 130.0, "NGN": 1500.0,
    "SEK": 10.5, "NOK": 10.7, "DKK": 6.9, "PLN": 3.95, "CZK": 23.0,
    "HUF": 360.0, "RON": 4.57, "ARS": 900.0,
}


def _normalise(text: str, keep_commas: bool = False) -> str:
    raw = (text or "").lower()
    if not keep_commas:
        raw = raw.replace(",", " ")
    return " ".join(raw.split())


# Below this length a place name is too collidable to match loosely: "nice"
# turned "somewhere nice" into a trip to France, and "male", "goa" and "ella"
# hide inside ordinary words. Short names still match when they are the whole
# input, which is what a destination field normally holds.
_MIN_LOOSE_MATCH = 5


def country_for(place: str) -> Optional[str]:
    """Best-effort country code for a free-text place name, or None when unsure.

    Matching is deliberately conservative, in three widening steps: the whole
    input, then any comma-separated part of it ("Dubai, UAE"), then a run of
    whole words inside it. Substring matching is *not* used — it read "nice" out
    of "somewhere nice" and would have blocked that trip on French prices.
    """
    text = _normalise(place)
    if not text:
        return None

    if text in PLACE_COUNTRY:
        return PLACE_COUNTRY[text]

    for part in (p.strip() for p in _normalise(place, keep_commas=True).split(",")):
        if part and part in PLACE_COUNTRY:
            return PLACE_COUNTRY[part]

    words = text.split()
    best: Optional[str] = None
    best_len = 0
    for name, code in PLACE_COUNTRY.items():
        if len(name) < _MIN_LOOSE_MATCH or len(name) <= best_len:
            continue
        name_words = name.split()
        span = len(name_words)
        # Whole-word runs only, so "goa" never matches "goad".
        if any(words[i:i + span] == name_words for i in range(len(words) - span + 1)):
            best, best_len = code, len(name)
    return best


def to_usd(amount: float, currency: str) -> Optional[float]:
    rate = FX_PER_USD.get((currency or "").strip().upper())
    if not rate:
        return None
    return amount / rate


def from_usd(amount_usd: float, currency: str) -> Optional[float]:
    rate = FX_PER_USD.get((currency or "").strip().upper())
    if not rate:
        return None
    return amount_usd * rate


def _round_up(value: float) -> float:
    """Round to something a person would actually type."""
    if value <= 0:
        return 0.0
    for step in (10, 50, 100, 500, 1000, 5000, 10000):
        if value <= step * 20:
            return float(-(-value // step) * step)
    return float(-(-value // 50000) * 50000)


def minimum_budget(
    *,
    destination: str,
    days: int,
    travelers: int = 1,
    currency: str = "USD",
    departure_country: str = "",
    include_flights: bool = False,
) -> Optional[dict]:
    """Cheapest budget that could conceivably buy this trip.

    Returns None when the answer is unknown — an unrecognised destination or an
    unsupported currency — and the caller must treat that as "allow". Otherwise
    returns the floor in both USD and the caller's currency, with the pieces it
    was built from so the message can explain itself.
    """
    country = country_for(destination)
    if country is None:
        return None
    if not FX_PER_USD.get((currency or "").strip().upper()):
        return None

    days = max(int(days or 1), 1)
    travelers = max(int(travelers or 1), 1)

    tier = COUNTRY_TIER.get(country, DEFAULT_TIER)
    daily = DAILY_FLOOR_USD.get(tier, DAILY_FLOOR_USD[DEFAULT_TIER])
    ground_usd = daily * days * travelers

    # A flight floor only applies when the traveller must actually cross a
    # border. Departure country is often blank, in which case assume domestic:
    # under-counting keeps a real trip from being blocked.
    departure = (departure_country or "").strip().upper()
    departure_code = departure if len(departure) == 2 else (
        country_for(departure_country) or ""
    )
    crosses_border = bool(departure_code) and departure_code != country
    flight_usd = (
        INTERNATIONAL_FLIGHT_FLOOR_USD * travelers
        if (crosses_border or include_flights) and departure_code != country
        else 0.0
    )

    total_usd = ground_usd + flight_usd
    local = from_usd(total_usd, currency)
    if local is None:
        return None

    return {
        "country": country,
        "tier": tier,
        "days": days,
        "travelers": travelers,
        "minimum_usd": round(total_usd, 2),
        "minimum": _round_up(local),
        "currency": (currency or "USD").strip().upper(),
        "ground_usd": round(ground_usd, 2),
        "flight_usd": round(flight_usd, 2),
        "includes_flight": flight_usd > 0,
    }


def shortfall_message(floor: dict, destination: str) -> str:
    """One sentence a traveller can act on."""
    days = floor["days"]
    # Attributive, so always singular: "a 3-day trip", never "a 3-days trip".
    amount = f"{floor['currency']} {floor['minimum']:,.0f}"
    who = "" if floor["travelers"] == 1 else f" for {floor['travelers']} travellers"
    flight = " including flights" if floor["includes_flight"] else ""
    return (
        f"A {days}-day trip to {destination}{who} needs at least "
        f"about {amount}{flight}. Please raise your budget to continue."
    )
