"""Odyssey generation as a background job.

The HTTP layer (`api/v1/itineraries.py`) saves a placeholder itinerary and
returns 202 in a few milliseconds; the 35–120 s of Gemini and SerpApi work
happens here, in the worker process, via `app.core.job_queue`.

`dispatch` is the seam. It enqueues for the worker, and if Redis is down —
which the API cannot serve through anyway, since it holds the JWT blacklist —
it falls back to the pre-worker behaviour of running the job as a FastAPI
BackgroundTask in the API process. The fallback is deliberately the *whole*
old path rather than an error: a generation that runs in the wrong process is
better than one that does not run.
"""
import logging
import uuid
from typing import Optional

from fastapi import BackgroundTasks

from app.core import job_queue
from app.core.database import async_session
from app.repositories.itinerary_repository import ItineraryRepository
from app.services import odyssey_ai_service
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

JOB_NAME = "generate_odyssey"


async def dispatch(background_tasks: BackgroundTasks, **kwargs) -> None:
    """Hand a generation to the worker, or run it in-process if the queue is
    unreachable. `kwargs` are exactly `run_generation`'s parameters."""
    try:
        job_id = await job_queue.enqueue(JOB_NAME, **kwargs)
        logger.info("Odyssey %s queued as job %s", kwargs.get("itinerary_id"), job_id)
    except Exception as e:
        logger.warning(
            "Odyssey %s: job queue unavailable (%s) — running in-process",
            kwargs.get("itinerary_id"), e,
        )
        background_tasks.add_task(run_generation, **kwargs)


async def run_job(**kwargs) -> None:
    """Worker entry point. Job payloads are JSON, so the UUIDs the API passed
    arrive as strings and are rebuilt here; everything else is JSON-native."""
    kwargs["itinerary_id"] = uuid.UUID(str(kwargs["itinerary_id"]))
    kwargs["user_id"] = uuid.UUID(str(kwargs["user_id"]))
    await run_generation(**kwargs)


async def run_generation(
    itinerary_id: uuid.UUID,
    user_id: uuid.UUID,
    destination: str,
    mood: str,
    budget: float,
    days: int,
    currency: str,
    travelers: int = 1,
    include_flights: bool = False,
    departure_city: str = "",
    departure_country: str = "",
    nationality: str = "",
    has_visa: bool = False,
    flight_start_date: Optional[str] = None,
    flight_end_date: Optional[str] = None,
    include_hotels: bool = False,
    hotel_check_in_date: Optional[str] = None,
    hotel_check_out_date: Optional[str] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    destination_place_id: str = "",
    destination_latitude: Optional[float] = None,
    destination_longitude: Optional[float] = None,
    destination_address: str = "",
    departure_latitude: Optional[float] = None,
    departure_longitude: Optional[float] = None,
) -> None:
    """The generation itself.

    Two short sessions rather than one long one. The old shape opened a
    session, then awaited 35–120 s of Gemini and SerpApi inside it, holding a
    pooled connection idle the whole time (PERFORMANCE_REPORT B6). Reading the
    inputs and writing the outcome are the only moments that need Postgres,
    so those are the only moments that get a connection.
    """
    async with async_session() as db:
        repo = ItineraryRepository(db)
        itin = await repo.get_by_id(itinerary_id, user_id)
        if itin is None:
            return

        svc = SettingsService(db)
        api_key = await svc.get_setting("gemini_api_key")
        if not api_key:
            logger.error("Odyssey generation skipped: gemini_api_key not configured")
            print(f"[ODYSSEY] FAILED {itinerary_id}: gemini_api_key not configured", flush=True)
            _mark_failed(itin, "Gemini API key is not configured")
            await repo.update(itin)
            return

        unsplash_api_key = await svc.get_setting("unsplash_api_key")
        serpapi_key = await svc.get_setting("serpapi_key")

    # No session is open across this await.
    error: Optional[str] = None
    title = items = None
    try:
        title, items = await odyssey_ai_service.generate_odyssey(
            destination=destination,
            mood=mood,
            budget=budget,
            days=days,
            currency=currency,
            travelers=travelers,
            api_key=api_key,
            unsplash_api_key=unsplash_api_key,
            serpapi_key=serpapi_key or "",
            include_flights=include_flights,
            departure_city=departure_city,
            departure_country=departure_country,
            nationality=nationality,
            has_visa=has_visa,
            flight_start_date=flight_start_date,
            flight_end_date=flight_end_date,
            include_hotels=include_hotels,
            hotel_check_in_date=hotel_check_in_date,
            hotel_check_out_date=hotel_check_out_date,
            start_date=start_date or "",
            end_date=end_date or "",
            destination_place_id=destination_place_id or "",
            destination_latitude=destination_latitude,
            destination_longitude=destination_longitude,
            destination_address=destination_address or "",
            departure_latitude=departure_latitude,
            departure_longitude=departure_longitude,
        )
        print(f"[ODYSSEY] SUCCESS {itinerary_id}: {title}", flush=True)
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        logger.error(f"Odyssey generation failed for {itinerary_id}: {e}")
        print(f"[ODYSSEY] FAILED {itinerary_id}: {e}\n{tb}", flush=True)
        error = str(e)

    async with async_session() as db:
        repo = ItineraryRepository(db)
        # Re-read rather than reuse: the first session is closed, and the user
        # may have deleted the itinerary while it was generating, in which case
        # there is nothing to write to and the plan is simply discarded.
        itin = await repo.get_by_id(itinerary_id, user_id)
        if itin is None:
            logger.info("Odyssey %s vanished during generation; discarding result", itinerary_id)
            return
        if error is not None:
            _mark_failed(itin, error)
        else:
            _keep_existing_cover(itin, items)
            itin.title = title
            itin.items = items
            itin.status = "active"
            start_dt_str = start_date or flight_start_date or hotel_check_in_date
            if start_dt_str:
                try:
                    from datetime import datetime as dt
                    itin.trip_date = dt.strptime(start_dt_str, "%Y-%m-%d").date()
                except Exception:
                    pass
        await repo.update(itin)

        if itin.status == "active":
            await notify_ready(db, user_id, itin.title, itinerary_id)


def _keep_existing_cover(itin, items: list) -> None:
    """Never swap the cover out from under the user.

    The list endpoint fills a cover onto the placeholder within seconds of it
    being created, and the user watches that picture for the whole
    generation. Both paths now resolve through the same cache, so the
    finished plan normally carries the identical URL — this is the guard for
    when it does not (cache expired in between, Unsplash down for one of the
    two calls): the picture already on screen wins.
    """
    try:
        old_meta = itin.items[0] if isinstance(itin.items, list) and itin.items else None
        existing = old_meta.get("cover_url") if isinstance(old_meta, dict) else ""
        new_meta = items[0] if isinstance(items, list) and items else None
        if existing and isinstance(new_meta, dict) and new_meta.get("kind") == "odyssey_meta":
            new_meta["cover_url"] = existing
    except Exception:  # decoration; never fail the write over it
        pass


def _mark_failed(itin, reason: str) -> None:
    """Flip to failed, keeping the meta item and recording why on it — the
    retry endpoint rebuilds its call from that meta, and the app shows the
    reason."""
    itin.status = "failed"
    if itin.items and isinstance(itin.items, list) and len(itin.items) > 0:
        first_item = dict(itin.items[0])
        first_item["failure_reason"] = reason
        itin.items = [first_item] + list(itin.items[1:])


async def notify_ready(db, user_id, title, itinerary_id) -> None:
    """Best-effort push telling the user their Odyssey finished generating.
    Sends to every device the user is signed in on (Android + iOS) and prunes
    any tokens FCM reports as dead."""
    try:
        from sqlalchemy import select
        from app.models.user import User
        from app.services import fcm_service

        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user:
            return
        prefs = user.preferences or {}
        tokens = list(prefs.get("fcm_tokens") or [])
        legacy = prefs.get("fcm_token")  # pre-multi-device single token
        if legacy and legacy not in tokens:
            tokens.append(legacy)
        if not tokens:
            logger.warning(f"Odyssey ready but user {user_id} has no device tokens")
            return

        invalid = await fcm_service.send_to_tokens(
            db,
            tokens,
            title="Your Odyssey is ready ✨",
            body=title or "Tap to view your trip plan.",
            data={"type": "odyssey_ready", "itinerary_id": str(itinerary_id)},
        )
        if invalid:
            new_prefs = {**prefs, "fcm_tokens": [t for t in tokens if t not in invalid]}
            new_prefs.pop("fcm_token", None)  # drop legacy if it was dead
            user.preferences = new_prefs
            await db.commit()
    except Exception as e:
        logger.error(f"Odyssey-ready notification failed for {itinerary_id}: {e}")
