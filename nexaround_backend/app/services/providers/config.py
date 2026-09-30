"""Keys and switches for the travel-data providers, as set in the admin panel.

Each provider has a mode:

    off     never called — the default, so shipping code starts nothing
    shadow  called and logged, but nothing it returns reaches a plan
    live    its data is used in plans

The panel writes these to `system_settings`. Every process keeps its own copy
of the settings, so they are re-read at most every CONFIG_TTL_S: a switch
flipped in the panel reaches the Odyssey worker within a minute, no restart.
"""
from __future__ import annotations

import logging
import time

logger = logging.getLogger(__name__)

PROVIDERS = ("gettransfer", "airalo", "wegotrip", "aviasales", "klook", "gocity", "kiwi")

OFF, SHADOW, LIVE = "off", "shadow", "live"
MODES = (OFF, SHADOW, LIVE)

# Travelpayouts: the API token (Aviasales data), the partner ID stamped on
# every affiliate link ("marker"), and the Project ID links are credited to
# ("trs"). GetTransfer issues its own token through Travelpayouts support.
TRAVELPAYOUTS_API_TOKEN = "travelpayouts_api_token"
TRAVELPAYOUTS_MARKER = "travelpayouts_marker"
TRAVELPAYOUTS_PROJECT_ID = "travelpayouts_project_id"
GETTRANSFER_API_TOKEN = "gettransfer_api_token"

KEYS = (
    TRAVELPAYOUTS_API_TOKEN,
    TRAVELPAYOUTS_MARKER,
    TRAVELPAYOUTS_PROJECT_ID,
    GETTRANSFER_API_TOKEN,
)

CONFIG_TTL_S = 60


def mode_key(provider: str) -> str:
    return f"provider_mode_{provider}"


MODE_KEYS = tuple(mode_key(p) for p in PROVIDERS)

_config: dict[str, str] = {}
_config_at: float = 0.0


async def _load(force: bool = False) -> dict[str, str]:
    global _config, _config_at
    now = time.time()
    if not force and _config_at and (now - _config_at) < CONFIG_TTL_S:
        return _config
    try:
        from app.core.database import async_session
        from app.services.settings_service import SettingsService

        async with async_session() as db:
            settings = await SettingsService(db).load_settings()
        _config = {k: str(settings.get(k) or "").strip() for k in KEYS + MODE_KEYS}
        _config_at = now
    except Exception as e:
        # Keep the last good copy; with none, everything reads as off.
        logger.warning("providers: could not load settings: %s", e)
        _config_at = now
    return _config


async def refresh() -> dict[str, str]:
    """Re-read now — called after the admin saves, so the API sees it at once."""
    return await _load(force=True)


async def mode(provider: str) -> str:
    value = (await _load()).get(mode_key(provider), "").lower()
    return value if value in MODES else OFF


async def setting(key: str) -> str:
    return (await _load()).get(key, "")
