"""Firebase Cloud Messaging sender.

Lazily initialises the Firebase Admin SDK from a service-account JSON stored in
SystemSettings under ``firebase_service_account_json`` (set via the admin panel
the same way the other API keys are — so there's no credential file to deploy).
Sending is a logged no-op when the key isn't configured, so Odyssey generation
never fails just because notifications aren't set up yet.
"""
import asyncio
import base64
import json
import logging
import os
from typing import Optional

from app.core.config import settings

logger = logging.getLogger(__name__)

_app = None  # cached firebase_admin app instance


def _resolve_credential(db_json: Optional[str]) -> Optional[dict]:
    """Resolve the service-account JSON from the most secure source available:
      1) a file path on the server   (FIREBASE_SERVICE_ACCOUNT_FILE)
      2) an env var: raw JSON or b64  (FIREBASE_SERVICE_ACCOUNT_JSON)
      3) the admin-panel DB setting   (least preferred — lives in the database)
    """
    # 1) File on the server (secret never leaves the box).
    path = (settings.FIREBASE_SERVICE_ACCOUNT_FILE or "").strip()
    if path:
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"FCM: cannot read {path}: {e}")
        else:
            logger.error(f"FCM: FIREBASE_SERVICE_ACCOUNT_FILE not found: {path}")

    # 2) env var, then 3) DB setting.
    for raw in (settings.FIREBASE_SERVICE_ACCOUNT_JSON, db_json):
        raw = (raw or "").strip()
        if not raw:
            continue
        # Accept base64-encoded JSON (avoids newline/quoting pain in .env files).
        if not raw.startswith("{"):
            try:
                raw = base64.b64decode(raw).decode("utf-8")
            except Exception:
                pass
        try:
            return json.loads(raw)
        except Exception as e:
            logger.error(f"FCM: invalid service-account JSON: {e}")
    return None


def _ensure_app(db_json: Optional[str]):
    """Initialise (once) and return the firebase_admin app, or None on failure."""
    global _app
    if _app is not None:
        return _app
    data = _resolve_credential(db_json)
    if not data:
        logger.warning("FCM: no service-account credential configured")
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(data)
        try:
            _app = firebase_admin.get_app()
        except ValueError:
            _app = firebase_admin.initialize_app(cred)
    except Exception as e:
        logger.error(f"FCM init failed: {e}")
        _app = None
    return _app


async def send_to_token(
    db,
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Send a push to a single device token. Returns True on success."""
    if not token:
        return False

    # DB setting is only the fallback; the file/env path is preferred.
    db_json = None
    try:
        from app.services.settings_service import SettingsService
        db_json = await SettingsService(db).get_setting("firebase_service_account_json")
    except Exception:
        pass

    app = _ensure_app(db_json)
    if app is None:
        logger.warning("FCM skipped: no Firebase credential configured")
        return False

    try:
        from firebase_admin import messaging

        message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(aps=messaging.Aps(sound="default")),
            ),
        )
        # messaging.send is blocking — run it off the event loop.
        await asyncio.to_thread(messaging.send, message)
        return True
    except Exception as e:
        logger.error(f"FCM send failed: {e}")
        return False
