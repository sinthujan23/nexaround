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


async def _resolve_app(db):
    """Resolve the credential (file/env/DB) and return the firebase app or None."""
    db_json = None
    try:
        from app.services.settings_service import SettingsService
        db_json = await SettingsService(db).get_setting("firebase_service_account_json")
    except Exception:
        pass
    return _ensure_app(db_json)


def _build_message(token, title, body, data):
    from firebase_admin import messaging
    return messaging.Message(
        token=token,
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
        android=messaging.AndroidConfig(priority="high"),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    sound="default",
                    content_available=True,
                    mutable_content=True,
                )
            ),
        ),
    )


async def _send_one(token, title, body, data):
    """Send to one token. Returns (ok: bool, status: str). status is '' on
    success, else a coarse error code used for pruning + diagnostics."""
    from firebase_admin import messaging
    try:
        msg_id = await asyncio.to_thread(
            messaging.send, _build_message(token, title, body, data)
        )
        logger.info(f"FCM ✅ sent to {token[:14]}… msg={msg_id}")
        return True, ""
    except Exception as e:
        name = type(e).__name__
        msg = str(e)
        # Stale/invalid token → prune it.
        if "Unregistered" in name or "not a valid FCM" in msg or "not found" in msg.lower():
            logger.warning(f"FCM ⚠️ token unregistered (will prune): {token[:14]}…")
            return False, "UNREGISTERED"
        # APNs key / Team-ID / Key-ID / environment problem (iOS-specific).
        if "ThirdPartyAuth" in name or "APNS" in msg or "APNs" in msg or "BadDeviceToken" in msg:
            logger.error(f"FCM ❌ APNs config/env error for {token[:14]}… — check APNs key & sandbox/production: {msg}")
            return False, "APNS"
        logger.error(f"FCM ❌ send failed for {token[:14]}…: {name}: {msg}")
        return False, name


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
    app = await _resolve_app(db)
    if app is None:
        logger.warning("FCM skipped: no Firebase credential configured")
        return False
    ok, _ = await _send_one(token, title, body, data)
    return ok


async def send_multicast(
    db,
    tokens: list,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> tuple:
    """Send one notification to MANY device tokens efficiently.

    Uses FCM multicast (``send_each_for_multicast``) in batches of 500 — one API
    round-trip per 500 devices instead of one per device, which is what makes a
    broadcast to thousands of users cheap and fast. Returns
    ``(success_count, failure_count, unregistered_tokens, token_status)`` where
    ``token_status`` maps each token to 'sent' | 'failed' | 'unregistered', so
    the caller can record real delivery stats, prune dead tokens, AND attribute
    per-user delivery outcomes.
    """
    from firebase_admin import messaging

    uniq = [t for t in dict.fromkeys(tokens) if t]  # dedup + drop empties
    if not uniq:
        return 0, 0, [], {}
    app = await _resolve_app(db)
    if app is None:
        logger.warning("FCM multicast skipped: no Firebase credential configured")
        return 0, len(uniq), [], {t: "failed" for t in uniq}

    data = {k: str(v) for k, v in (data or {}).items()}
    success = 0
    failure = 0
    unregistered: list = []
    token_status: dict = {}

    for i in range(0, len(uniq), 500):
        batch = uniq[i:i + 500]
        message = messaging.MulticastMessage(
            tokens=batch,
            notification=messaging.Notification(title=title, body=body),
            data=data,
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                headers={"apns-priority": "10"},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound="default",
                        content_available=True,
                        mutable_content=True,
                    )
                ),
            ),
        )
        try:
            resp = await asyncio.to_thread(
                messaging.send_each_for_multicast, message
            )
        except Exception as e:
            logger.error(f"FCM multicast batch failed: {e}")
            failure += len(batch)
            for t in batch:
                token_status[t] = "failed"
            continue
        success += resp.success_count
        failure += resp.failure_count
        for idx, r in enumerate(resp.responses):
            tok_snippet = batch[idx][:15] if batch[idx] else "empty"
            if r.success:
                token_status[batch[idx]] = "sent"
                logger.info(f"FCM ✅ push delivered to token {tok_snippet}...")
                continue
            err = r.exception
            name = type(err).__name__ if err else ""
            msg = str(err) if err else ""
            logger.error(f"FCM ❌ push failed for token {tok_snippet}...: {name} - {msg}")
            if "Unregistered" in name or "not a valid FCM" in msg or "not found" in msg.lower():
                unregistered.append(batch[idx])
                token_status[batch[idx]] = "unregistered"
            else:
                token_status[batch[idx]] = "failed"

    logger.info(
        f"FCM multicast '{title}': {success} ok, {failure} failed, "
        f"{len(unregistered)} to prune"
    )
    return success, failure, unregistered, token_status


async def send_to_tokens(
    db,
    tokens: list,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> list:
    """Send to many device tokens (one user can have several — Android + iOS).
    Returns the tokens FCM reports as UNREGISTERED so the caller can prune them.
    """
    uniq = [t for t in dict.fromkeys(tokens) if t]  # dedup + drop empties
    if not uniq:
        logger.warning("FCM skipped: user has no device tokens")
        return []
    app = await _resolve_app(db)
    if app is None:
        logger.warning("FCM skipped: no Firebase credential configured")
        return []
    logger.info(f"FCM: sending '{title}' to {len(uniq)} device token(s)")
    invalid = []
    for t in uniq:
        ok, status = await _send_one(t, title, body, data)
        if status == "UNREGISTERED":
            invalid.append(t)
    return invalid
