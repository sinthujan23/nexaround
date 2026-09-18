from typing import List, Optional
import asyncio
import logging
import uuid
import json
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.itinerary import Itinerary
from app.repositories.itinerary_repository import ItineraryRepository
from app.repositories.attraction_repository import AttractionRepository
from app.services.ai_service import ai_service
from app.services import odyssey_ai_service, odyssey_jobs
from app.services.settings_service import SettingsService
from app.services import cover_photo_service
from app.schemas.itinerary import (
    BUDGET_RANGE,
    DAYS_RANGE,
    DESTINATION_MAX,
    ItineraryCreate,
    ItineraryUpdate,
    ItineraryResponse,
    MOOD_MAX,
    OdysseyGenerateRequest,
    OdysseyRoutePreviewRequest,
    OdysseyRoutePreviewResponse,
    OdysseySwapRequest,
    OdysseyPartnerSwapRequest,
    TRAVELERS_RANGE,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/itineraries", tags=["itineraries"])


@router.post("/odyssey/route-preview", response_model=OdysseyRoutePreviewResponse)
async def preview_odyssey_route(
    data: OdysseyRoutePreviewRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The cities a trip would visit, before committing to generating it.

    Generation already begins by planning this route; running it here lets the
    traveller see and change it first. The route that comes back is handed to
    POST /odyssey/generate unchanged as `preset_route`, so accepting a preview
    costs nothing extra — the planning call is not repeated.

    Authenticated and rate-limited by the same middleware as generation: it
    spends a Gemini call, and `exclude_cities` lets a client ask for another
    region as often as it likes.
    """
    settings = SettingsService(db)
    api_key = await settings.get_setting("gemini_api_key")
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Route planning is unavailable right now.",
        )
    try:
        route, notice = await odyssey_ai_service.preview_route(
            destination=data.destination,
            days=data.days,
            mood=data.mood,
            travelers=data.travelers,
            api_key=api_key,
            include_flights=data.include_flights,
            departure_city=data.departure_city or "",
            departure_country=data.departure_country or "",
            departure_latitude=data.departure_latitude,
            departure_longitude=data.departure_longitude,
            start_date=data.hotel_check_in_date or data.start_date or "",
            destination_place_id=data.destination_place_id or "",
            destination_latitude=data.destination_latitude,
            destination_longitude=data.destination_longitude,
            destination_address=data.destination_address or "",
            entry_city=data.entry_city or "",
            exit_city=data.exit_city or "",
            only_this_city=data.only_this_city,
            entry_latitude=data.entry_latitude,
            entry_longitude=data.entry_longitude,
            exit_latitude=data.exit_latitude,
            exit_longitude=data.exit_longitude,
            exclude_cities=list(data.exclude_cities or []),
        )
    except Exception as e:
        # A preview that fails must not block the trip: the app falls back to
        # generating without one, which is exactly what it did before.
        logger.warning("Route preview for %r failed: %s", data.destination, e)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not plan a route just now.",
        )
    return OdysseyRoutePreviewResponse(route=route, notice=notice)


@router.post("/odyssey/generate", response_model=ItineraryResponse, status_code=status.HTTP_202_ACCEPTED)
async def generate_odyssey(
    data: OdysseyGenerateRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Kick off a server-side AI Odyssey. Returns a 'generating' itinerary
    immediately; a background task fills in the plan (or marks it 'failed').

    The mobile app polls GET /itineraries to see the status flip to 'active'.
    """
    # Budget feasibility is now checked post-generation using real SerpApi
    # flight/hotel prices rather than a static dictionary. This avoids false
    # blocks for destinations not in the dictionary (e.g. "Petra") and ensures
    # every generated plan shows honest, real pricing.

    repo = ItineraryRepository(db)
    start_dt_str = data.start_date or data.flight_start_date or data.hotel_check_in_date or ""
    end_dt_str = data.end_date or data.flight_end_date or data.hotel_check_out_date or ""

    trip_dt = None
    if start_dt_str:
        try:
            from datetime import datetime as dt
            trip_dt = dt.strptime(start_dt_str, "%Y-%m-%d").date()
        except Exception:
            pass

    generation_params = {
        "destination": data.destination,
        "mood": data.mood,
        "budget": data.budget,
        "days": data.days,
        "currency": data.currency,
        "travelers": data.travelers,
        "include_flights": data.include_flights,
        "departure_city": data.departure_city or "",
        "departure_country": data.departure_country or "",
        "nationality": data.nationality or "",
        "has_visa": data.has_visa,
        "flight_start_date": data.flight_start_date,
        "flight_end_date": data.flight_end_date,
        "include_hotels": data.include_hotels,
        "hotel_check_in_date": data.hotel_check_in_date,
        "hotel_check_out_date": data.hotel_check_out_date,
        "start_date": data.start_date,
        "end_date": data.end_date,
        # The retry endpoint reads all three of these back out (see the
        # rebuild below). Entry and exit were being read there and never
        # written here, so a retried Odyssey silently lost the cities the
        # traveller had chosen — fixed by storing them alongside the rest.
        "entry_city": data.entry_city or "",
        "exit_city": data.exit_city or "",
        "only_this_city": data.only_this_city,
        "entry_latitude": data.entry_latitude,
        "entry_longitude": data.entry_longitude,
        "exit_latitude": data.exit_latitude,
        "exit_longitude": data.exit_longitude,
        # Stored, not just forwarded: the retry endpoint rebuilds its call from
        # these, so leaving them out would make a retried Odyssey lose the
        # grounding the first attempt had.
        "destination_place_id": data.destination_place_id or "",
        "destination_latitude": data.destination_latitude,
        "destination_longitude": data.destination_longitude,
        "destination_address": data.destination_address or "",
        "departure_latitude": data.departure_latitude,
        "departure_longitude": data.departure_longitude,
    }
    meta = odyssey_ai_service.build_meta_item(
        destination=data.destination,
        mood=data.mood,
        budget=data.budget,
        currency=data.currency,
        days=data.days,
        nights=data.days - 1 if data.days > 1 else 0,
        travelers=data.travelers,
        start_date=start_dt_str,
        end_date=end_dt_str,
        departure_city=data.departure_city or "",
        generation_params=generation_params,
        budget_breakdown={
            "stay": round(data.budget * 0.35, 2),
            "transit": round(data.budget * 0.30, 2),
            "food": round(data.budget * 0.20, 2),
            "activities": round(data.budget * 0.15, 2),
            "total": data.budget,
        },
    )
    placeholder = Itinerary(
        user_id=current_user.id,
        title=f"Planning {data.destination}…" if data.destination else "Planning your Odyssey…",
        items=[meta],
        status="generating",
        trip_date=trip_dt,
    )
    saved = await repo.create(placeholder)

    await odyssey_jobs.dispatch(
        background_tasks,
        itinerary_id=saved.id,
        user_id=current_user.id,
        destination=data.destination,
        mood=data.mood,
        budget=data.budget,
        days=data.days,
        currency=data.currency,
        travelers=data.travelers,
        include_flights=data.include_flights,
        departure_city=data.departure_city,
        departure_country=data.departure_country,
        nationality=data.nationality,
        has_visa=data.has_visa,
        flight_start_date=data.flight_start_date,
        flight_end_date=data.flight_end_date,
        include_hotels=data.include_hotels,
        hotel_check_in_date=data.hotel_check_in_date,
        hotel_check_out_date=data.hotel_check_out_date,
        start_date=data.start_date,
        end_date=data.end_date,
        entry_city=data.entry_city or "",
        exit_city=data.exit_city or "",
        only_this_city=data.only_this_city,
        entry_latitude=data.entry_latitude,
        entry_longitude=data.entry_longitude,
        exit_latitude=data.exit_latitude,
        exit_longitude=data.exit_longitude,
        destination_place_id=data.destination_place_id or "",
        destination_latitude=data.destination_latitude,
        destination_longitude=data.destination_longitude,
        destination_address=data.destination_address or "",
        departure_latitude=data.departure_latitude,
        departure_longitude=data.departure_longitude,
        # Dumped to a plain dict here rather than in the worker: the job
        # payload is JSON, and a pydantic model is not.
        preset_route=(
            data.preset_route.model_dump() if data.preset_route is not None else None
        ),
    )
    return saved


@router.post("/{itinerary_id}/odyssey/swap", response_model=ItineraryResponse)
async def swap_odyssey_activity(
    itinerary_id: uuid.UUID,
    data: OdysseySwapRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Replace a single activity in a saved Odyssey with an AI-suggested
    alternative (e.g. the user already visited it or isn't interested). Runs
    synchronously — a single place is fast — and returns the updated itinerary.
    """
    repo = ItineraryRepository(db)
    itin = await repo.get_by_id(itinerary_id, current_user.id)
    if not itin:
        raise HTTPException(status_code=404, detail="Itinerary not found")

    items = [dict(it) for it in (itin.items or [])]
    meta = next((it for it in items if it.get("kind") == "odyssey_meta"), {})
    if not meta:
        raise HTTPException(status_code=400, detail="Not an Odyssey")

    day_positions = [i for i, it in enumerate(items) if it.get("kind") == "day"]
    if data.day_index < 0 or data.day_index >= len(day_positions):
        raise HTTPException(status_code=400, detail="Invalid day index")
    pos = day_positions[data.day_index]
    day = dict(items[pos])
    activities = [dict(a) for a in (day.get("activities") or [])]
    if data.activity_index < 0 or data.activity_index >= len(activities):
        raise HTTPException(status_code=400, detail="Invalid activity index")

    api_key = await SettingsService(db).get_setting("gemini_api_key")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI is not configured")

    old = activities[data.activity_index]
    existing_names = [
        str(a.get("name") or "")
        for d in items if d.get("kind") == "day"
        for a in (d.get("activities") or [])
    ]

    # Which city that day is spent in, and where it is. Both are already on the
    # stored plan — the swap prompt simply never asked for them, so a
    # replacement for a day in Kandy was solicited as somewhere "near Sri
    # Lanka" and could land anywhere in the country, or on a namesake abroad.
    legs = [l for l in (meta.get("legs") or []) if isinstance(l, dict)]
    day_no = int(day.get("day") or data.day_index + 1)
    leg = next(
        (
            l for l in legs
            if int(l.get("start_day") or 0) <= day_no <= int(l.get("end_day") or 0)
        ),
        None,
    )
    dctx = meta.get("destination_context") or {}

    def _coord(value):
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    swap_city = str((leg or {}).get("city") or "")
    swap_lat = _coord((leg or {}).get("latitude"))
    swap_lng = _coord((leg or {}).get("longitude"))
    if swap_lat is None or swap_lng is None:
        # No leg for that day, or a plan stored before legs carried coordinates:
        # the destination's own point still beats naming a whole country.
        swap_lat, swap_lng = _coord(dctx.get("latitude")), _coord(dctx.get("longitude"))

    try:
        replacement = await odyssey_ai_service.generate_replacement_activity(
            city=swap_city,
            latitude=swap_lat,
            longitude=swap_lng,
            country=str(dctx.get("country") or ""),
            destination=str(meta.get("destination") or ""),
            mood=str(meta.get("mood") or ""),
            budget=float(meta.get("budget") or 0),
            currency=str(meta.get("currency") or "USD"),
            day_no=int(day.get("day") or data.day_index + 1),
            theme=str(day.get("theme") or ""),
            time_slot=str(old.get("time") or ""),
            old_name=str(old.get("name") or ""),
            reason=data.reason,
            existing_names=existing_names,
            api_key=api_key,
        )
    except Exception as e:
        logger.error(f"Odyssey swap failed for {itinerary_id}: {e}")
        raise HTTPException(status_code=502, detail="Could not generate a replacement")

    activities[data.activity_index] = replacement
    day["activities"] = activities
    items[pos] = day
    itin.items = items  # reassign whole list so SQLAlchemy persists the JSON change
    return await repo.update(itin)


@router.post("/{itinerary_id}/odyssey/swap-partner", response_model=ItineraryResponse)
async def swap_odyssey_partner(
    itinerary_id: uuid.UUID,
    data: OdysseyPartnerSwapRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Replace a single booking partner in a saved Odyssey with an AI-suggested
    alternative. Runs synchronously and returns the updated itinerary.
    """
    repo = ItineraryRepository(db)
    itin = await repo.get_by_id(itinerary_id, current_user.id)
    if not itin:
        raise HTTPException(status_code=404, detail="Itinerary not found")

    items = [dict(it) for it in (itin.items or [])]
    meta_idx = next((i for i, it in enumerate(items) if it.get("kind") == "odyssey_meta"), -1)
    if meta_idx == -1:
        raise HTTPException(status_code=400, detail="Not an Odyssey")
    
    meta = dict(items[meta_idx])
    partners = [dict(p) for p in (meta.get("booking_partners") or [])]
    
    # Find the partner to swap
    target_idx = next((i for i, p in enumerate(partners) if p.get("name") == data.partner_name), -1)
    if target_idx == -1:
        raise HTTPException(status_code=400, detail="Booking partner not found in this Odyssey")
    
    target_partner = partners[target_idx]
    partner_type = target_partner.get("type", "hotels")

    api_key = await SettingsService(db).get_setting("gemini_api_key")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI is not configured")

    # Collect existing names to avoid duplicates
    avoid_names = [str(p.get("name") or "") for p in partners]

    try:
        replacement = await odyssey_ai_service.generate_replacement_partner(
            destination=str(meta.get("destination") or ""),
            partner_name=data.partner_name,
            partner_type=partner_type,
            reason=data.reason,
            avoid_names=avoid_names,
            api_key=api_key,
        )
    except Exception as e:
        logger.error(f"Odyssey partner swap failed for {itinerary_id}: {e}")
        raise HTTPException(status_code=502, detail="Could not generate a replacement partner")

    partners[target_idx] = replacement
    meta["booking_partners"] = partners
    items[meta_idx] = meta
    itin.items = items  # reassign whole list so SQLAlchemy persists the JSON change
    return await repo.update(itin)


@router.post("/{itinerary_id}/odyssey/retry", response_model=ItineraryResponse, status_code=status.HTTP_202_ACCEPTED)
async def retry_odyssey_generation(
    itinerary_id: uuid.UUID,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Re-trigger generation for a failed Odyssey."""
    repo = ItineraryRepository(db)
    itin = await repo.get_by_id(itinerary_id, current_user.id)
    if not itin:
        raise HTTPException(status_code=404, detail="Itinerary not found")

    items = [dict(it) for it in (itin.items or [])]
    meta = next((it for it in items if it.get("kind") == "odyssey_meta"), {})
    if not meta:
        raise HTTPException(status_code=400, detail="Not an Odyssey")

    gen_params = meta.get("generation_params") or {}

    def _clamp(value, bounds, fallback):
        """Hold a replayed parameter to the same bounds a fresh request has.

        Clamped, not refused: the traveller is retrying a trip that already
        exists and wants it to work. Trips stored before these bounds existed
        carry values outside them - one has travelers=110, another days=31 -
        and replaying those books 110 rooms or asks for a month in one call.
        """
        lo, hi = bounds
        try:
            n = type(fallback)(value)
        except (TypeError, ValueError):
            return fallback
        if n != n:                       # NaN
            return fallback
        return max(lo, min(hi, n))

    destination = str(
        gen_params.get("destination") or meta.get("destination") or itin.title or ""
    )[:DESTINATION_MAX]
    def _coord_or_none(value):
        """A replayed coordinate, or None when it is missing or unusable."""
        try:
            n = float(value)
        except (TypeError, ValueError):
            return None
        return None if n != n else n          # NaN is not a location

    entry_city = str(gen_params.get("entry_city") or "")[:DESTINATION_MAX]
    exit_city = str(gen_params.get("exit_city") or "")[:DESTINATION_MAX]
    only_this_city = bool(gen_params.get("only_this_city") or False)
    mood = str(gen_params.get("mood") or meta.get("mood") or "balanced")[:MOOD_MAX]
    budget = _clamp(
        gen_params.get("budget") or meta.get("budget") or 1000.0, BUDGET_RANGE, 1000.0,
    )
    days = _clamp(gen_params.get("days") or meta.get("days") or 3, DAYS_RANGE, 3)
    currency = gen_params.get("currency") or meta.get("currency") or "USD"
    travelers = _clamp(
        gen_params.get("travelers") or meta.get("travelers") or 1, TRAVELERS_RANGE, 1,
    )
    include_flights = bool(gen_params.get("include_flights", False))
    departure_city = gen_params.get("departure_city") or meta.get("departure_city") or ""
    departure_country = gen_params.get("departure_country") or ""
    nationality = gen_params.get("nationality") or ""
    has_visa = bool(gen_params.get("has_visa", False))
    flight_start_date = gen_params.get("flight_start_date")
    flight_end_date = gen_params.get("flight_end_date")
    include_hotels = bool(gen_params.get("include_hotels", False))
    hotel_check_in_date = gen_params.get("hotel_check_in_date")
    hotel_check_out_date = gen_params.get("hotel_check_out_date")
    start_date = gen_params.get("start_date") or meta.get("start_date") or ""
    end_date = gen_params.get("end_date") or meta.get("end_date") or ""
    # A retry must not be less grounded than the first attempt. Falls back to
    # whatever the finished meta recorded, so an Odyssey generated before the
    # client sent these still retries with the context the backend resolved.
    _dctx = meta.get("destination_context") or {}
    destination_place_id = gen_params.get("destination_place_id") or _dctx.get("place_id") or ""
    destination_latitude = gen_params.get("destination_latitude") or _dctx.get("latitude")
    destination_longitude = gen_params.get("destination_longitude") or _dctx.get("longitude")
    destination_address = (
        gen_params.get("destination_address") or _dctx.get("formatted_address") or ""
    )
    departure_latitude = gen_params.get("departure_latitude")
    departure_longitude = gen_params.get("departure_longitude")

    meta.pop("failure_reason", None)
    itin.status = "generating"
    itin.items = [meta]
    saved = await repo.update(itin)

    await odyssey_jobs.dispatch(
        background_tasks,
        itinerary_id=saved.id,
        user_id=current_user.id,
        destination=destination,
        mood=mood,
        budget=budget,
        days=days,
        currency=currency,
        travelers=travelers,
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
        start_date=start_date,
        end_date=end_date,
        entry_city=entry_city,
        exit_city=exit_city,
        only_this_city=only_this_city,
        entry_latitude=_coord_or_none(gen_params.get("entry_latitude")),
        entry_longitude=_coord_or_none(gen_params.get("entry_longitude")),
        exit_latitude=_coord_or_none(gen_params.get("exit_latitude")),
        exit_longitude=_coord_or_none(gen_params.get("exit_longitude")),
        destination_place_id=destination_place_id,
        destination_latitude=destination_latitude,
        destination_longitude=destination_longitude,
        destination_address=destination_address,
        departure_latitude=departure_latitude,
        departure_longitude=departure_longitude,
    )
    return saved


@router.post("/generate", response_model=dict)
async def generate_ai_itinerary(
    location: str,
    days: int = 1,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Generate an AI-powered itinerary based on nearby attractions.
    """
    attraction_repo = AttractionRepository(db)
    # Get some nearby attractions for context (e.g. from center of Colombo)
    attractions = await attraction_repo.get_nearby(6.9271, 79.8612, 10000.0)
    
    data_str = "\n".join([f"- {a.name}: {a.description}" for a in attractions[:10]])
    
    itinerary_json = await ai_service.generate_itinerary(
        location, 
        data_str, 
        days,
        preferences=current_user.preferences
    )
    
    if not itinerary_json:
        raise HTTPException(status_code=500, detail="Failed to generate itinerary")
        
    try:
        return json.loads(itinerary_json)
    except:
        return {"error": "AI response was not valid JSON", "raw": itinerary_json}

# Cover lookups go through app/services/cover_photo_service.py — one cached,
# deterministic Unsplash search per destination, shared with the generation
# path so the placeholder's cover and the finished plan's cover are the same
# photo. The history of why it is cached (the detail screen's 3 s poll once
# cost fifty Unsplash calls per generation) lives there too.
_COVER_CONCURRENCY = 4                # simultaneous Unsplash lookups per request


async def _cover_for_destination(destination: str, api_key: str) -> str:
    return await cover_photo_service.cover_for_destination(destination, api_key)


async def _heal_itinerary_covers(
    itineraries: List[Itinerary], repo: ItineraryRepository, db: AsyncSession
) -> None:
    """Fill in missing odyssey cover photos for a batch of itineraries.

    Replaces a per-itinerary sequential loop. Beyond the caching above:

      * one lookup per *distinct destination*, not one per itinerary
      * lookups run concurrently, bounded by _COVER_CONCURRENCY — sequentially
        they cost ~240 ms each, so ten uncovered itineraries added ~2.4 s of
        serial external I/O to a plain "list my trips" call
    """
    pending: dict[str, list] = {}
    for itin in itineraries:
        items = itin.items or []
        if not (isinstance(items, list) and items):
            continue
        meta = items[0]
        if not (isinstance(meta, dict) and meta.get("kind") == "odyssey_meta"):
            continue
        if meta.get("cover_url"):
            continue
        destination = (meta.get("destination") or "").strip()
        if not destination:
            continue
        pending.setdefault(destination, []).append(itin)

    if not pending:
        return

    # Only the country-level fallback needs this; the primary source is
    # Google Places, so a missing key does not skip the lookup.
    api_key = await SettingsService(db).get_setting("unsplash_api_key") or ""

    async def _resolve(dest: str) -> tuple:
        try:
            return dest, await _cover_for_destination(dest, api_key)
        except Exception:
            # One destination failing must not lose the others, and must never
            # fail the request — the cover is decoration.
            logger.exception("cover lookup failed for destination %r", dest)
            return dest, ""

    resolved: dict = {}
    destinations = list(pending)
    for i in range(0, len(destinations), _COVER_CONCURRENCY):
        chunk = destinations[i:i + _COVER_CONCURRENCY]
        for dest, url in await asyncio.gather(*(_resolve(d) for d in chunk)):
            resolved[dest] = url

    for destination, itins in pending.items():
        url = resolved.get(destination)
        if not url:
            continue
        for itin in itins:
            items = itin.items or []
            new_items = [dict(i) if isinstance(i, dict) else i for i in items]
            new_items[0]["cover_url"] = url
            itin.items = new_items
            await repo.update(itin)


async def _heal_itinerary_cover_photo(itin: Itinerary, repo: ItineraryRepository, db: AsyncSession) -> None:
    """Single-itinerary wrapper, kept for the detail endpoint."""
    await _heal_itinerary_covers([itin], repo, db)


@router.get("/", response_model=List[ItineraryResponse])
async def get_my_itineraries(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itineraries = await repo.get_by_user(current_user.id)
    try:
        await _heal_itinerary_covers(itineraries, repo, db)
    except Exception as e:
        logger.error(f"Failed to heal itinerary covers: {e}")
    return itineraries


@router.post("/", response_model=ItineraryResponse, status_code=status.HTTP_201_CREATED)
async def create_itinerary(
    data: ItineraryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = Itinerary(
        user_id=current_user.id,
        title=data.title,
        trip_date=data.trip_date,
        items=[item.model_dump() for item in data.items],
        status=data.status
    )
    return await repo.create(itinerary)


@router.get("/{itinerary_id}", response_model=ItineraryResponse)
async def get_itinerary(
    itinerary_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = await repo.get_by_id(itinerary_id, current_user.id)
    if not itinerary:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    try:
        await _heal_itinerary_cover_photo(itinerary, repo, db)
    except Exception as e:
        logger.error(f"Failed to heal itinerary {itinerary_id} cover: {e}")
    return itinerary

@router.put("/{itinerary_id}", response_model=ItineraryResponse)
async def update_itinerary(
    itinerary_id: uuid.UUID,
    data: ItineraryUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = await repo.get_by_id(itinerary_id, current_user.id)
    if not itinerary:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    
    if data.title is not None:
        itinerary.title = data.title
    if data.trip_date is not None:
        itinerary.trip_date = data.trip_date
    if data.items is not None:
        itinerary.items = [item.model_dump() for item in data.items]
    if data.status is not None:
        itinerary.status = data.status
        
    return await repo.update(itinerary)

@router.delete("/{itinerary_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_itinerary(
    itinerary_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = await repo.get_by_id(itinerary_id, current_user.id)
    if not itinerary:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    await repo.delete(itinerary)
    return None
