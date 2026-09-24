"""Ride apps a traveller can use in a country, asked of Gemini with Google Search.

The Odyssey itinerary shows these as display-only chips under each ground-
transport stop ("Available here: PickMe, Uber"). They come from a small,
separate grounded call per country, never from the itinerary prompt, which is
left exactly as it is. The answer is cached for 30 days and shared by every
trip to that country, so a country costs at most one call a month and the list
refreshes itself as apps enter and leave a market (Uber left Tanzania in
January 2026 and Nigeria in September 2026).

Nothing here is verified, so nothing here may fail a screen: an unknown code,
a Gemini error or an answer that is not a list of names all come back as an
empty list, which the app shows as no chips. A missing chip costs the
traveller nothing.
"""
import asyncio
import json
import logging
from datetime import datetime, timezone

from app.services import odyssey_ai_service, place_cache_service

logger = logging.getLogger(__name__)

_CACHE_TTL = 30 * 24 * 3600      # apps found: markets move in months, not days
_EMPTY_TTL = 7 * 24 * 3600       # "none here": rarely wrong, still worth a recheck
_FAILURE_TTL = 15 * 60           # Gemini failed: retry soon, not on every open
_KEY_VERSION = "v1"
_MAX_APPS = 4
_MAX_NAME_LEN = 30
_NOT_A_NAME = {"none", "n/a", "na", "no apps", "not available", "unknown"}

# Grounded calls wait on a live search. The chips appear once this returns,
# so a slow answer only delays them, but it must not hold a request for the
# helper's default 90 s per attempt.
_TIMEOUT_S = 20.0

# One lookup per country at a time, so a burst of travellers opening trips to
# the same new country buys one answer, not one each.
_locks: dict[str, asyncio.Lock] = {}

# ISO 3166-1 alpha-2 codes and English names, generated from the tz database's
# iso3166.tab rather than typed. It doubles as the allow-list: only a real
# code can reach Gemini, which caps what a stray or hostile request can spend
# at one cached call per country.
COUNTRY_NAMES: dict[str, str] = {
    "AD": "Andorra", "AE": "United Arab Emirates", "AF": "Afghanistan",
    "AG": "Antigua and Barbuda", "AI": "Anguilla", "AL": "Albania", "AM": "Armenia",
    "AO": "Angola", "AQ": "Antarctica", "AR": "Argentina", "AS": "American Samoa",
    "AT": "Austria", "AU": "Australia", "AW": "Aruba", "AX": "Åland Islands",
    "AZ": "Azerbaijan", "BA": "Bosnia and Herzegovina", "BB": "Barbados",
    "BD": "Bangladesh", "BE": "Belgium", "BF": "Burkina Faso", "BG": "Bulgaria",
    "BH": "Bahrain", "BI": "Burundi", "BJ": "Benin", "BL": "St Barthelemy",
    "BM": "Bermuda", "BN": "Brunei", "BO": "Bolivia", "BQ": "Caribbean NL",
    "BR": "Brazil", "BS": "Bahamas", "BT": "Bhutan", "BV": "Bouvet Island",
    "BW": "Botswana", "BY": "Belarus", "BZ": "Belize", "CA": "Canada",
    "CC": "Cocos (Keeling) Islands", "CD": "Democratic Republic of the Congo",
    "CF": "Central African Rep.", "CG": "Republic of the Congo",
    "CH": "Switzerland", "CI": "Côte d'Ivoire", "CK": "Cook Islands", "CL": "Chile",
    "CM": "Cameroon", "CN": "China", "CO": "Colombia", "CR": "Costa Rica",
    "CU": "Cuba", "CV": "Cape Verde", "CW": "Curaçao", "CX": "Christmas Island",
    "CY": "Cyprus", "CZ": "Czech Republic", "DE": "Germany", "DJ": "Djibouti",
    "DK": "Denmark", "DM": "Dominica", "DO": "Dominican Republic", "DZ": "Algeria",
    "EC": "Ecuador", "EE": "Estonia", "EG": "Egypt", "EH": "Western Sahara",
    "ER": "Eritrea", "ES": "Spain", "ET": "Ethiopia", "FI": "Finland", "FJ": "Fiji",
    "FK": "Falkland Islands", "FM": "Micronesia", "FO": "Faroe Islands",
    "FR": "France", "GA": "Gabon", "GB": "United Kingdom", "GD": "Grenada",
    "GE": "Georgia", "GF": "French Guiana", "GG": "Guernsey", "GH": "Ghana",
    "GI": "Gibraltar", "GL": "Greenland", "GM": "Gambia", "GN": "Guinea",
    "GP": "Guadeloupe", "GQ": "Equatorial Guinea", "GR": "Greece",
    "GS": "South Georgia and the South Sandwich Islands", "GT": "Guatemala",
    "GU": "Guam", "GW": "Guinea-Bissau", "GY": "Guyana", "HK": "Hong Kong",
    "HM": "Heard Island and McDonald Islands", "HN": "Honduras", "HR": "Croatia",
    "HT": "Haiti", "HU": "Hungary", "ID": "Indonesia", "IE": "Ireland",
    "IL": "Israel", "IM": "Isle of Man", "IN": "India",
    "IO": "British Indian Ocean Territory", "IQ": "Iraq", "IR": "Iran",
    "IS": "Iceland", "IT": "Italy", "JE": "Jersey", "JM": "Jamaica", "JO": "Jordan",
    "JP": "Japan", "KE": "Kenya", "KG": "Kyrgyzstan", "KH": "Cambodia",
    "KI": "Kiribati", "KM": "Comoros", "KN": "St Kitts and Nevis",
    "KP": "North Korea", "KR": "South Korea", "KW": "Kuwait",
    "KY": "Cayman Islands", "KZ": "Kazakhstan", "LA": "Laos", "LB": "Lebanon",
    "LC": "St Lucia", "LI": "Liechtenstein", "LK": "Sri Lanka", "LR": "Liberia",
    "LS": "Lesotho", "LT": "Lithuania", "LU": "Luxembourg", "LV": "Latvia",
    "LY": "Libya", "MA": "Morocco", "MC": "Monaco", "MD": "Moldova",
    "ME": "Montenegro", "MF": "Saint Martin", "MG": "Madagascar",
    "MH": "Marshall Islands", "MK": "North Macedonia", "ML": "Mali",
    "MM": "Myanmar", "MN": "Mongolia", "MO": "Macau",
    "MP": "Northern Mariana Islands", "MQ": "Martinique", "MR": "Mauritania",
    "MS": "Montserrat", "MT": "Malta", "MU": "Mauritius", "MV": "Maldives",
    "MW": "Malawi", "MX": "Mexico", "MY": "Malaysia", "MZ": "Mozambique",
    "NA": "Namibia", "NC": "New Caledonia", "NE": "Niger", "NF": "Norfolk Island",
    "NG": "Nigeria", "NI": "Nicaragua", "NL": "Netherlands", "NO": "Norway",
    "NP": "Nepal", "NR": "Nauru", "NU": "Niue", "NZ": "New Zealand", "OM": "Oman",
    "PA": "Panama", "PE": "Peru", "PF": "French Polynesia",
    "PG": "Papua New Guinea", "PH": "Philippines", "PK": "Pakistan", "PL": "Poland",
    "PM": "St Pierre and Miquelon", "PN": "Pitcairn", "PR": "Puerto Rico",
    "PS": "Palestine", "PT": "Portugal", "PW": "Palau", "PY": "Paraguay",
    "QA": "Qatar", "RE": "Réunion", "RO": "Romania", "RS": "Serbia", "RU": "Russia",
    "RW": "Rwanda", "SA": "Saudi Arabia", "SB": "Solomon Islands",
    "SC": "Seychelles", "SD": "Sudan", "SE": "Sweden", "SG": "Singapore",
    "SH": "St Helena", "SI": "Slovenia", "SJ": "Svalbard and Jan Mayen",
    "SK": "Slovakia", "SL": "Sierra Leone", "SM": "San Marino", "SN": "Senegal",
    "SO": "Somalia", "SR": "Suriname", "SS": "South Sudan",
    "ST": "Sao Tome and Principe", "SV": "El Salvador", "SX": "Sint Maarten",
    "SY": "Syria", "SZ": "Eswatini", "TC": "Turks and Caicos Islands", "TD": "Chad",
    "TF": "French S. Terr.", "TG": "Togo", "TH": "Thailand", "TJ": "Tajikistan",
    "TK": "Tokelau", "TL": "East Timor", "TM": "Turkmenistan", "TN": "Tunisia",
    "TO": "Tonga", "TR": "Turkey", "TT": "Trinidad and Tobago", "TV": "Tuvalu",
    "TW": "Taiwan", "TZ": "Tanzania", "UA": "Ukraine", "UG": "Uganda",
    "UM": "US minor outlying islands", "US": "United States", "UY": "Uruguay",
    "UZ": "Uzbekistan", "VA": "Vatican City", "VC": "St Vincent", "VE": "Venezuela",
    "VG": "British Virgin Islands", "VI": "US Virgin Islands", "VN": "Vietnam",
    "VU": "Vanuatu", "WF": "Wallis and Futuna", "WS": "Samoa", "YE": "Yemen",
    "YT": "Mayotte", "ZA": "South Africa", "ZM": "Zambia", "ZW": "Zimbabwe",
}


def normalise_code(code: str | None) -> str | None:
    """The upper-case ISO code, or None when it names no country."""
    key = (code or "").strip().upper()
    return key if key in COUNTRY_NAMES else None


def _key(code: str) -> str:
    return f"ride_apps:{_KEY_VERSION}:{code}"


def build_prompt(code: str) -> str:
    name = COUNTRY_NAMES[code]
    # The month is spelled out because a model left to pick its own search
    # terms dates them by its training data: Flash searched "... Nigeria 2024"
    # for this very question, the year before Uber left.
    today = datetime.now(timezone.utc).strftime("%B %Y")
    return f"""Which ride-hailing or taxi-booking apps can a visiting traveller use to book local rides in {name} (ISO country code {code}) today, {today}? Search Google for current information.

Rules:
- Only apps that currently operate for passengers in {name}. Leave out any app that has left the country, is banned there, or only delivers food.
- Most useful for a visiting traveller first, at most {_MAX_APPS}.
- Use each app's own short brand name, for example "Uber", "Bolt" or "Grab".
- If no such app works in {name}, return an empty list.

Return ONLY a JSON object with this exact shape: {{"apps": ["App name", "App name"]}}"""


def clean_app_names(value) -> list[str]:
    """Keep the model's list only as far as it looks like app names."""
    if not isinstance(value, list):
        return []
    seen: set[str] = set()
    names: list[str] = []
    for item in value:
        if not isinstance(item, str):
            continue
        name = " ".join(item.split())
        low = name.lower()
        if (
            not name
            or len(name) > _MAX_NAME_LEN
            or "http" in low
            or "www." in low
            or low in _NOT_A_NAME
            or low in seen
        ):
            continue
        seen.add(low)
        names.append(name)
        if len(names) == _MAX_APPS:
            break
    return names


def _from_cache(raw: str | None) -> list[str] | None:
    if raw is None:
        return None
    try:
        value = json.loads(raw)
    except (TypeError, ValueError):
        return None
    return value if isinstance(value, list) else None


async def ride_apps_for(code: str | None, api_key: str) -> list[str]:
    """The ride apps for a country, from the cache or one grounded Gemini call."""
    code = normalise_code(code)
    if not code:
        return []
    key = _key(code)
    cached = _from_cache(await place_cache_service.get_raw(key))
    if cached is not None:
        return cached

    lock = _locks.setdefault(code, asyncio.Lock())
    async with lock:
        # Whoever held the lock may have just filled it.
        cached = _from_cache(await place_cache_service.get_raw(key))
        if cached is not None:
            return cached
        try:
            text, _ = await odyssey_ai_service._call_gemini(
                build_prompt(code),
                api_key,
                max_tokens=512,
                thinking_budget=0,
                use_grounding=True,
                operation="odyssey_ride_apps",
                timeout_s=_TIMEOUT_S,
                models=odyssey_ai_service._LITE_MODELS,
            )
            apps = clean_app_names(odyssey_ai_service._parse_json(text).get("apps"))
        except Exception as e:
            logger.warning("Ride apps lookup for %s failed: %s", code, e)
            await place_cache_service.set_raw(key, "[]", ttl=_FAILURE_TTL)
            return []
        await place_cache_service.set_raw(
            key, json.dumps(apps), ttl=_CACHE_TTL if apps else _EMPTY_TTL,
        )
        return apps
