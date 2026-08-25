"""Band-aware place discovery for the Around You / Discovery sections.

The sections show ten places per category, drawn from three distance bands on
the quotas in `place_bands.BAND_QUOTAS`, so the list reads as a progression
outward rather than ten variations on "the nearest thing".

The awkward part is the outer bands. Google's Nearby Search takes a *circle*,
not a ring, and returns at most 20 results ranked by prominence — so a circle
centred on the user can never surface anything in a 25–50 km band, no matter how
large the radius: the 20 slots are always won by places near the middle. Filling
an outer band means moving the circle off the user, out onto the ring itself.

That costs requests, so the escalation is strictly cheapest-first:

    PostGIS ring query  →  Redis  →  Google (capped, and only for short bands)

Anything Google returns is written back to `attractions`, so the next user
standing in the same ~500 m tile is served entirely by the first step.
"""
import asyncio
from typing import Optional

from sqlalchemy import select

from app.core.database import async_session
from app.models.attraction import Attraction
from app.models.category import Category
from app.repositories.attraction_repository import AttractionRepository
from app.schemas.place import BandedPlacesResponse, PlaceBand
from app.services import (
    google_places_client,
    place_bands,
    place_cache_service,
    places_service,
    spend_guard,
    telemetry,
)
from app.utils.geo_utils import create_point


# Requests we are willing to spend on one band that came up short. Bands that
# the database already covers cost nothing, so on a warm tile this is never
# reached.
_MAX_REQUESTS_PER_SHORT_BAND = 3

# Bearings for the offset circles that sample an outer ring. Three gives usable
# coverage of a ring without the request count that full tiling would need
# (a 25–50 km ring needs ~16 circles to tile completely — not worth it).
_RING_BEARINGS = (0.0, 120.0, 240.0)

# Rotate the sampling directions per band so the three bands don't all probe the
# same three compass directions and inherit the same blind spots.
_BEARING_PHASE_PER_BAND = 40.0

# How many DB rows to pull per band before selection. Comfortably more than the
# handful we show, so the rating sort has something to choose between — and more
# so now that six categories are drawn from four overlapping pools, where a
# band's rows are shared with its sibling and thinned by the relevance gate.
_DB_LIMIT_PER_BAND = 40

# Cache keys with a fill already running. Without this, every request arriving
# for a cold tile before the first fill finishes starts its own — four users
# opening the app on the same street corner would each buy the same places.
_active_fills: set[str] = set()


def _cache_key(latitude: float, longitude: float, category: Optional[str]) -> str:
    cat = (category or "all").replace(" ", "_").replace("&", "and").lower()
    snap_lat = place_cache_service._snap(latitude)
    snap_lng = place_cache_service._snap(longitude)
    return f"places:banded:v1:{snap_lat}:{snap_lng}:{cat}"


def _rank_for_selection(place: dict) -> tuple:
    """Best-first within a band: review-weighted quality, then closest."""
    score = place_bands.quality_score(
        place.get("rating"), place.get("review_count")
    )
    return (-score, place.get("distance_m") or 0.0)


async def _category_ids_for(session, category: Optional[str]) -> list:
    """Resolve every category-table id a category's places may be filed under."""
    names = place_bands.db_aliases_for(category)
    if not names:
        return []
    res = await session.execute(select(Category).where(Category.name.in_(names)))
    return [c.id for c in res.scalars().all()]


async def _seed_place_dicts(place_dicts: list[dict]) -> None:
    """Persist Google results so later requests in this tile never pay for them.

    Deliberately conservative: a place already at these coordinates is skipped
    rather than updated, because this path runs opportunistically and should
    never be the reason an admin-curated attraction gets overwritten.
    """
    if not place_dicts:
        return
    try:
        async with async_session() as session:
            repo = AttractionRepository(session)
            cat_cache: dict[str, object] = {}

            # One query for every coordinate already stored in the area these
            # places cover, instead of a round trip per place. Seeding a band
            # fill of ~60 places used to mean ~60 sequential SELECTs.
            usable = [
                p for p in place_dicts
                if p.get("name")
                and p.get("latitude") is not None
                and p.get("longitude") is not None
            ]
            if not usable:
                return
            lats = [p["latitude"] for p in usable]
            lngs = [p["longitude"] for p in usable]
            # Padded by the same 1e-6 the duplicate check tolerates, so a point
            # sitting exactly on the edge is still compared against.
            pad = 0.000001
            seen_coords = await repo.get_coordinates_in_bounds(
                min(lats) - pad, min(lngs) - pad,
                max(lats) + pad, max(lngs) + pad,
            )

            for p in usable:
                name = p["name"]
                plat = p["latitude"]
                plng = p["longitude"]
                coord = (round(plat, 6), round(plng, 6))
                # Also guards against duplicates *within* this batch: the same
                # place can arrive from two overlapping sampling circles.
                if coord in seen_coords:
                    continue
                seen_coords.add(coord)

                cat_id = None
                resolved = p.get("category_name")
                if resolved:
                    if resolved not in cat_cache:
                        res = await session.execute(
                            select(Category).where(Category.name == resolved)
                        )
                        cat_obj = res.scalar_one_or_none()
                        if not cat_obj:
                            cat_obj = Category(
                                name=resolved, icon="place", color="#607D8B"
                            )
                            session.add(cat_obj)
                            await session.flush()
                        cat_cache[resolved] = cat_obj
                    cat_id = cat_cache[resolved].id

                session.add(Attraction(
                    name=name,
                    google_place_id=places_service._google_id_of(p),
                    description=p.get("description") or "",
                    location=create_point(plat, plng),
                    category_id=cat_id,
                    address=p.get("address") or "",
                    opening_hours=p.get("opening_hours") or {},
                    entry_fee=p.get("entry_fee") or 0.0,
                    currency=p.get("currency") or "USD",
                    rating=p.get("rating") or 0.0,
                    review_count=p.get("review_count") or 0,
                    photo_urls=p.get("photo_urls") or [],
                    tags=p.get("tags") or [],
                    geofence_radius_m=100,
                    is_active=True,
                ))
            await session.commit()
    except Exception as e:
        print(f"⚠️ banded seed failed: {e}")


def _band_queries(
    latitude: float,
    longitude: float,
    category: Optional[str],
    band_index: int,
    band_min: int,
    band_max: int,
) -> list[tuple[float, float, int, str, Optional[list[str]]]]:
    """Plan the Google requests for one short band.

    Returns (lat, lng, radius, group_name, included_types) tuples.

    The inner band is reachable from the user's own position, so its requests
    differ only by type sub-group. Outer bands must be sampled from circles
    sitting on the ring itself, so there each request differs by *both* bearing
    and sub-group — one request buys geographic spread and thematic spread at
    once, instead of having to choose.
    """
    subgroups = place_bands.subgroups_for(category)
    queries: list[tuple[float, float, int, str, Optional[list[str]]]] = []

    if band_min <= 0:
        # Inner band: one circle on the user, fanned across sub-groups. Every
        # sub-group gets a slot here rather than the outer bands' rotation —
        # this is the band users actually look at, and a circle on the user is
        # the cheapest request we make, so it is the wrong place to economise.
        for name, types in subgroups:
            queries.append((latitude, longitude, band_max, name, types))
        return queries

    mid = (band_min + band_max) / 2.0
    sample_radius = max(int((band_max - band_min) / 2.0), 1)
    phase = band_index * _BEARING_PHASE_PER_BAND

    for i, bearing in enumerate(_RING_BEARINGS[:_MAX_REQUESTS_PER_SHORT_BAND]):
        olat, olng = places_service.offset_lat_lng(
            latitude, longitude, bearing + phase, mid
        )
        # Stagger which sub-group pairs with which bearing across bands, so no
        # sub-group is permanently stuck sampling the same direction.
        name, types = subgroups[(band_index + i) % len(subgroups)]
        queries.append((olat, olng, sample_radius, name, types))

    return queries


async def _google_fill_band(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    band_index: int,
    band_min: int,
    band_max: int,
) -> list[dict]:
    """Fetch, band-filter and persist Google results for one short band."""
    queries = _band_queries(
        latitude, longitude, category, band_index, band_min, band_max
    )

    async def fetch_one(lat, lng, rad, group, types):
        try:
            return await google_places_client.nearby_search(
                latitude=lat,
                longitude=lng,
                category=category,
                radius=rad,
                included_types_override=types,
                type_group=group,
            )
        except Exception as e:
            print(f"⚠️ banded fetch failed ({category} b{band_index} {group}): {e}")
            return []

    results = await asyncio.gather(*(fetch_one(*q) for q in queries))

    raw: list[dict] = []
    seen: set[str] = set()
    for group_results in results:
        for p in group_results:
            pid = p.get("id") or p.get("place_id")
            if pid and pid not in seen:
                seen.add(pid)
                raw.append(p)

    if not raw:
        return []

    if category == "Food & Drink":
        raw = google_places_client.filter_food(raw)

    place_dicts = [
        google_places_client.to_place_dict(
            p, latitude, longitude, category, places_service._photo_url
        )
        for p in raw
    ]

    # The sampling circles overlap the band edges, so distance is re-checked
    # against the true haversine rather than trusted from the query geometry.
    in_band = [
        p for p in place_dicts
        if band_min <= (p.get("distance_m") or 0.0) <= band_max
        and place_bands.is_relevant(category, p.get("tags"), p.get("name"))
    ]

    # Everything fetched is worth persisting, including the out-of-band spill —
    # it was paid for, and it fills a neighbouring band for the next caller.
    await _seed_place_dicts(place_dicts)

    return in_band


async def get_nearby_banded(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    max_photos: int = 1,
    force_refresh: bool = False,
    per_band: Optional[int] = None,
) -> BandedPlacesResponse:
    """One category's section, drawn across its distance bands and backfilled.

    `per_band` overrides the per-band quota for callers that want a longer list:
    Discovery lists everything it can, while Around You is the quick-access strip
    and takes only BAND_QUOTAS from each band. Both are served from the *same*
    cached pool — what we fetch and cache is deliberately independent of
    `per_band`, so the two surfaces share one entry rather than fragmenting the
    cache into a warm copy per requested length.
    """
    category = google_places_client.canonical_category(category)
    bands = place_bands.bands_for(category)
    key = _cache_key(latitude, longitude, category)

    if not force_refresh:
        cached = await place_cache_service.get_cached(key)
        if cached is not None:
            async with telemetry.track(
                "internal", "nearby_banded", cache_key=key
            ) as t:
                t.hit("redis")
            return _assemble(
                latitude, longitude, category, bands, cached, max_photos,
                cached_flag=True, source="cache", per_band=per_band,
            )

    # ── Step 1: PostGIS ring queries ─────────────────────────────────────────
    async with async_session() as session:
        repo = AttractionRepository(session)
        category_ids = await _category_ids_for(session, category)
        # Narrow to plausible rows in SQL so the per-band limit is spent on
        # candidates rather than on a category sibling's places.
        pre_tags, pre_names = place_bands.sql_prefilter(category)

        band_rows = await asyncio.gather(*(
            repo.get_nearby(
                latitude=latitude,
                longitude=longitude,
                radius_m=float(band_max),
                min_radius_m=float(band_min) if band_min > 0 else None,
                category_ids=category_ids or None,
                any_tags=pre_tags or None,
                any_name_ilike=pre_names or None,
                limit=_DB_LIMIT_PER_BAND,
                is_active=True,
            )
            for band_min, band_max in bands
        ))

        pool: list[dict] = []
        for rows in band_rows:
            pool.extend(
                p for p in (
                    places_service.attraction_to_place_dict(attr, dist)
                    for attr, dist in rows
                )
                # The stored category is not trusted here: POI pulls in rows
                # filed as 'Experiences', and older rows were categorised by a
                # vocabulary that has since changed. Membership is re-derived
                # from each place's own Google types.
                if place_bands.is_relevant(category, p.get("tags"), p.get("name"))
            )

    short_bands = [
        i for i, (bmin, bmax) in enumerate(bands)
        if sum(1 for p in pool if bmin <= (p.get("distance_m") or 0) <= bmax)
        < place_bands.quota_for_band(i)
    ]

    source = "database"
    defer_fill = False

    # ── Step 2: Google, only for bands the database could not cover ──────────
    if short_bands and key not in _active_fills:
        allowed, reason = await spend_guard.allowed(None)
        if not allowed:
            print(f"skipping banded Google fill: {reason}")
        elif len(pool) < place_bands.quota_for_band(0):
            # Nothing worth showing yet — fill inline so this caller gets a
            # populated section rather than an empty one.
            _active_fills.add(key)
            try:
                filled = await asyncio.gather(*(
                    _google_fill_band(
                        latitude=latitude,
                        longitude=longitude,
                        category=category,
                        band_index=i,
                        band_min=bands[i][0],
                        band_max=bands[i][1],
                    )
                    for i in short_bands
                ))
            finally:
                _active_fills.discard(key)
            for got in filled:
                pool.extend(got)
            source = "google"
        else:
            # There is already enough to render. Fill the gaps after responding
            # and let the next request serve the richer result. Deferred rather
            # than spawned here: the background task retires this cache key when
            # it finishes, and it must not be able to do so before the write
            # below has happened, or the thinner list would serve out the whole
            # 14-day TTL.
            defer_fill = True

    # Dedupe: the DB rows and a fresh Google fetch can describe the same place.
    deduped: list[dict] = []
    seen_ids: set[str] = set()
    seen_names: set[tuple] = set()
    for p in sorted(pool, key=_rank_for_selection):
        pid = str(p.get("id") or "")
        name_key = (
            (p.get("name") or "").strip().lower(),
            round(p.get("latitude") or 0.0, 4),
            round(p.get("longitude") or 0.0, 4),
        )
        if pid in seen_ids or name_key in seen_names:
            continue
        seen_ids.add(pid)
        seen_names.add(name_key)
        deduped.append(p)

    await place_cache_service.set_cached(key, deduped)

    if defer_fill:
        places_service.spawn_background(_fill_bands_bg(
            latitude=latitude,
            longitude=longitude,
            category=category,
            band_indices=short_bands,
            bands=bands,
            key=key,
        ))

    return _assemble(
        latitude, longitude, category, bands, deduped, max_photos,
        cached_flag=False, source=source, per_band=per_band,
    )


async def _fill_bands_bg(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    band_indices: list[int],
    bands: list[tuple[int, int]],
    key: str,
) -> None:
    """Fill short bands after responding, then drop the stale cache entry."""
    if key in _active_fills:
        return
    _active_fills.add(key)
    try:
        await asyncio.gather(*(
            _google_fill_band(
                latitude=latitude,
                longitude=longitude,
                category=category,
                band_index=i,
                band_min=bands[i][0],
                band_max=bands[i][1],
            )
            for i in band_indices
        ))
        # The newly seeded rows are not in the cached payload, so retire it
        # rather than leave the thinner list to serve for the full TTL.
        await place_cache_service.delete_cached(key)
    except Exception as e:
        print(f"⚠️ background band fill failed for {category}: {e}")
    finally:
        _active_fills.discard(key)


def _assemble(
    latitude: float,
    longitude: float,
    category: Optional[str],
    bands: list[tuple[int, int]],
    pool: list[dict],
    max_photos: int,
    *,
    cached_flag: bool,
    source: str,
    per_band: Optional[int] = None,
) -> BandedPlacesResponse:
    """Fill each band to its quota, then backfill to ten from whatever is left.

    Backfill is nearest-first: when a band is genuinely empty — no hospital
    within 25–50 km — the honest substitute is another close place, not a
    padded-out band boundary.
    """
    remaining = sorted(pool, key=_rank_for_selection)
    chosen: list[list[dict]] = []
    taken_ids: set[str] = set()
    # Google labels a great many unnamed tanks and inlets with nothing but the
    # district name, so a section could show "Trincomalee" four times and
    # "WAWE" three — all real, distinct rows at different coordinates, so the
    # id/coordinate dedupe never touched them. One entry per name is worth far
    # more to a reader than a complete list of things called the same thing.
    taken_names: set[str] = set()

    def _claim(place: dict) -> bool:
        """Take a place, unless its id or name is already spoken for."""
        pid = str(place.get("id") or "")
        name = (place.get("name") or "").strip().lower()
        if pid in taken_ids or (name and name in taken_names):
            return False
        taken_ids.add(pid)
        if name:
            taken_names.add(name)
        return True

    for i, (band_min, band_max) in enumerate(bands):
        quota = per_band if per_band is not None else place_bands.quota_for_band(i)
        band_pool = [
            p for p in remaining
            if band_min <= (p.get("distance_m") or 0.0) <= band_max
        ]
        # Places quality_score would rank out but that are independently
        # provable as significant (see priority_ids_for_band) get first claim
        # on the quota, still taken in quality order among themselves; the
        # normal pass below then fills whatever's left exactly as before.
        priority_ids = place_bands.priority_ids_for_band(category, band_pool)

        picks = []
        for p in band_pool:
            if len(picks) >= quota:
                break
            if str(p.get("id") or "") in priority_ids and _claim(p):
                picks.append(p)
        for p in band_pool:
            if len(picks) >= quota:
                break
            if not _claim(p):
                continue
            picks.append(p)
        # `remaining` is in selection order (review-weighted quality), and the
        # quota above is taken from the front of it — so `picks` already holds
        # the band's best (plus any priority places pulled in ahead of that
        # order). Sorting for display happens once, at the end, after every
        # band has chosen; sorting here would leave callers that take the
        # first N of a band with the nearest N rather than the best N.
        chosen.append(picks)

    target_total = (
        per_band * len(bands) if per_band is not None
        else place_bands.TOTAL_PER_CATEGORY
    )
    shortfall = target_total - sum(len(c) for c in chosen)
    if shortfall > 0:
        leftovers = sorted(
            (p for p in pool if str(p.get("id") or "") not in taken_ids),
            key=lambda p: p.get("distance_m") or 0.0,
        )
        filled = 0
        for p in leftovers:
            if filled >= shortfall:
                break
            if not _claim(p):
                continue
            filled += 1
            dist = p.get("distance_m") or 0.0
            # File each backfilled place under the band it actually falls in, so
            # the client's band headings stay truthful; anything beyond the last
            # band's edge lands in the outermost one.
            target = len(bands) - 1
            for i, (band_min, band_max) in enumerate(bands):
                if band_min <= dist <= band_max:
                    target = i
                    break
            chosen[target].append(p)

    # Each band stays in *selection* order — best first. That is the order a
    # caller taking only part of a band needs: Around You takes BAND_QUOTAS off
    # the front and must get the band's best, not its nearest. Sorting bands by
    # distance here is what made the app show three unreviewed ponds ahead of
    # Marble Beach and its 1,763 reviews.
    #
    # `places` below carries the display order instead, nearest first, for
    # callers that render the whole thing.
    band_models = [
        PlaceBand(
            index=i,
            min_m=float(band_min),
            max_m=float(band_max),
            label=place_bands.band_label(band_min, band_max),
            places=places_service._format_response_places(
                picks, max_photos, len(picks), 0
            ),
        )
        for i, ((band_min, band_max), picks) in enumerate(zip(bands, chosen))
    ]

    flat = sorted(
        (p for band in band_models for p in band.places),
        key=lambda p: p.distance_m if p.distance_m is not None else 0.0,
    )

    return BandedPlacesResponse(
        category=category or "all",
        bands=band_models,
        places=flat,
        cached=cached_flag,
        source=source,
    )
