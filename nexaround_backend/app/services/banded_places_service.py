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
    excluded_keyword_service,
    google_places_client,
    place_bands,
    place_cache_service,
    places_service,
    spend_guard,
    telemetry,
)
from app.utils.geo_utils import create_point


# One Google request per short band, centred on the user. Bands the database
# already covers cost nothing, so on a warm tile this is never reached — see
# `_band_queries` for why the previous ring-sampling was dropped.
_MAX_REQUESTS_PER_SHORT_BAND = 1

# How many DB rows to pull per band before selection. Comfortably more than the
# handful we show, so the rating sort has something to choose between — and more
# so now that six categories are drawn from four overlapping pools, where a
# band's rows are shared with its sibling and thinned by the relevance gate.
#
# 40 was sized against Around You's quota (BAND_QUOTAS, 4/3/3). Discovery asks
# for `per_band=15`, and the relevance gate discards most of what a band pulls —
# Hospital survived 25 of 120 rows here — so 40 could not fill a 15-place band
# and Discovery's sections came back short. The rows exist: the same three bands
# hold roughly 13.9k / 19.8k / 2.2k candidates near Trincomalee, so this is a
# limit we chose, not data we lack. It is a PostGIS read against a GIST index
# and costs no upstream calls, so the headroom is cheap.
_DB_LIMIT_PER_BAND = 150

# How long a cold request will wait on the near band's Google fill before
# answering with what it already has. A never-queried tile can need dozens of
# calls at ~1.7s each, and awaiting them outright made those loads take 40-50s:
# response time tracked how much work the tile needed rather than anything the
# user could perceive. Past this the fill detaches and the caller answers from
# the database and Redis.
_NEAR_FILL_BUDGET_S = 2.5

# The budget when the database gave us nothing at all. Returning early is only
# an improvement if there is something to return: on a location nobody has ever
# queried, cutting the fill off at 2.5s produced a 5s wait ending in an empty
# screen — slower *and* emptier than before. A first-ever fill also pays DNS and
# TLS to Google that a warm process does not, which is precisely when it
# overruns. Waiting longer here is the lesser evil; the section is populated on
# arrival instead of blank.
_EMPTY_FILL_BUDGET_S = 8.0

# What counts as "something worth showing" for the choice above — the near
# band's own quota, so a section that can already fill its first row answers
# immediately and finishes filling behind the response.
_MIN_PLACES_TO_ANSWER_EARLY = place_bands.quota_for_band(0)

# TTL for an answer returned before its fill finished. Short on purpose: the
# detached fill is seeding rows behind it, so the next request a minute later
# recomputes against a warm database and caches the full result properly.
# Writing a partial list under the 14-day default would serve it for a
# fortnight — worse than the slow response it replaced.
_PARTIAL_CACHE_TTL_S = 60

# Cache keys with a fill already running. Without this, every request arriving
# for a cold tile before the first fill finishes starts its own — four users
# opening the app on the same street corner would each buy the same places.
_active_fills: set[str] = set()


def _tag_excluded(pool: list[dict], keywords: list[str]) -> None:
    """Mark each place an admin keyword hits, in place.

    Computed fresh on every call rather than stored in the cached payload, so
    an admin's edit takes effect on the next request with no cache
    invalidation. Only the Around You cards read this flag — see
    `living_map_page.dart`'s `_buildHiddenGemCards`.
    """
    for p in pool:
        p["excluded_by_keyword"] = place_bands.matches_excluded_keyword(
            p.get("name"), keywords
        )


def _cache_key(latitude: float, longitude: float, category: Optional[str]) -> str:
    cat = (category or "all").replace(" ", "_").replace("&", "and").lower()
    snap_lat = place_cache_service._snap(latitude)
    snap_lng = place_cache_service._snap(longitude)
    return f"places:banded:v1:{snap_lat}:{snap_lng}:{cat}"


def _rank_for_selection(place: dict) -> tuple:
    """Best-first within a band: review-weighted quality, then closest.

    Deliberately *not* ordered reviewed-first. Around You wants only its
    notable places, but this order also decides which slice of the pool
    Discovery receives — 15 per band, not the whole thing — so demoting
    unreviewed places here pushed them out of that window entirely wherever a
    band held 15 or more reviewed ones. Hospital lost all 30 of its unreviewed
    places from Discovery, which is the opposite of showing them there.
    Around You applies its own preference when it takes its quota off the front
    (see living_map_page.dart), leaving this slice untouched.
    """
    score = place_bands.quality_score(
        place.get("rating"), place.get("review_count")
    )
    return (-score, place.get("distance_m") or 0.0)


# Resolved category-id list per section name. The `categories` table holds 13
# rows and changes only when seeding meets a name it has never seen.
_category_ids_cache: dict[str, list] = {}


async def _category_ids_for(session, category: Optional[str]) -> list:
    """Resolve every category-table id a category's places may be filed under.

    Cached in process, keyed on the section rather than on the individual
    names. Keying on names looked tidier and never hit: `db_aliases_for` returns
    aliases that have no row of their own, so "is every name known?" was always
    false and the query ran on every request anyway.

    It matters because this is the *first* statement of every request, so it is
    the one that waits for a free pooled connection while background seeding
    holds them — measured at 1.7s against 110ms for all three PostGIS band
    queries combined.

    A category created after this fills is not picked up until the process
    restarts. That is an acceptable trade for a 13-row table that only grows
    when Google returns a type we have never filed before.
    """
    if category in _category_ids_cache:
        return _category_ids_cache[category]

    names = place_bands.db_aliases_for(category)
    if not names:
        _category_ids_cache[category] = []
        return []

    res = await session.execute(select(Category).where(Category.name.in_(names)))
    ids = [c.id for c in res.scalars().all()]
    _category_ids_cache[category] = ids
    return ids


async def _seed_place_dicts(place_dicts: list[dict]) -> None:
    """Persist Google results so later requests in this tile never pay for them.

    Deliberately conservative: this path runs opportunistically and must never
    be the reason an admin-curated attraction changes. The coordinate scan below
    skips anything already stored, and `upsert_seeded_place` only ever fills a
    blank field or refreshes a review count — a name, description or photo set
    already on the row is left alone.
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

            # The rows this batch might already hold, in two queries rather than
            # two per place. Passed into every upsert below so folding sixty
            # places in costs no further round trips — it used to cost ~120,
            # each holding a pooled connection, which is what made the next
            # request wait over a second just to acquire one.
            existing_index = await repo.find_existing_for_seed(
                min_lat=min(lats) - pad, min_lng=min(lngs) - pad,
                max_lat=max(lats) + pad, max_lng=max(lngs) + pad,
                google_place_ids=[
                    g for g in (places_service._google_id_of(p) for p in usable) if g
                ],
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

                # This path had no duplicate check at all, so every band fill
                # re-inserted places it already held. Shares the seeder used by
                # places_service so both refresh a row instead of stacking copies.
                await places_service.upsert_seeded_place(
                    session, repo, p,
                    name=name, latitude=plat, longitude=plng,
                    category_id=cat_id,
                    existing_index=existing_index,
                )
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
    """Plan the Google requests for one short band: exactly one, centred.

    Returns (lat, lng, radius, group_name, included_types) tuples.

    This used to sample outer bands from three circles offset around the ring
    (`_RING_BEARINGS`), crossed with type sub-groups, because a circle centred
    on the user cannot reach a 25-50km ring: Google ranks its 20 results by
    prominence and the near ones always win. That reasoning is sound in
    isolation and cost 44 Google calls for one cold screen — at roughly 1.7s
    each, most of a 5-11s cold load.

    The trade is deliberate. Google is now the *fallback* tier, not the primary
    one: Redis answers a warm tile in milliseconds, PostGIS answers a covered
    one in tens, and this runs only for bands neither could fill. One centred
    call per band caps a cold screen at 18 calls instead of 44, and what it does
    return is seeded, so the ring fills in from the database on later visits
    rather than being bought again every time.

    Cost of the trade, stated plainly: a genuinely new location's outer bands
    come back thinner on the first visit than the ring sampling made them.
    """
    subgroups = place_bands.subgroups_for(category)
    # Sub-groups exist to stop one type crowding out the others in Google's
    # 20-result ranking. With a single call per band they collapse into one
    # request's includedTypes; the relevance gate downstream still splits the
    # results back into the right section.
    types: list[str] = []
    for _, group_types in subgroups:
        for t in group_types or ():
            if t not in types:
                types.append(t)

    label = category or "all"
    return [(latitude, longitude, band_max, label, types or None)]


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
    #
    # Detached, not awaited. The caller already has these places in hand; making
    # it wait while ~60 rows are written buys it nothing, and the write holds a
    # pooled connection throughout, which is what left the *next* request
    # waiting seconds just to acquire one of its own. `_seed_place_dicts` opens
    # its own session, so it is safe to outlive this call.
    places_service.spawn_background(_seed_place_dicts(place_dicts))

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
    excluded_keywords = await excluded_keyword_service.get_active_keywords()

    if not force_refresh:
        cached = await place_cache_service.get_cached(key)
        if cached is not None:
            async with telemetry.track(
                "internal", "nearby_banded", cache_key=key
            ) as t:
                t.hit("redis")
            _tag_excluded(cached, excluded_keywords)
            return _assemble(
                latitude, longitude, category, bands, cached, max_photos,
                cached_flag=True, source="cache", per_band=per_band,
            )

    # ── Step 1: PostGIS ring queries ─────────────────────────────────────────
    async with async_session() as session:
        category_ids = await _category_ids_for(session, category)
        # Narrow to plausible rows in SQL so the per-band limit is spent on
        # candidates rather than on a category sibling's places.
        pre_tags, pre_names = place_bands.sql_prefilter(category)

    # One session per band, not one shared across the gather.
    #
    # An AsyncSession is a single connection with a single transaction, and
    # SQLAlchemy guards it against concurrent use — gathering three queries onto
    # one does not run them in parallel, it serialises them under that guard.
    # The three ring queries take ~0.7s when each has its own connection and
    # ~3.5s sharing one, which was most of a cold response.
    async def _band_query(band_min: int, band_max: int):
        async with async_session() as band_session:
            return await AttractionRepository(band_session).get_nearby(
                latitude=latitude,
                longitude=longitude,
                radius_m=float(band_max),
                min_radius_m=float(band_min) if band_min > 0 else None,
                category_ids=category_ids or None,
                any_tags=pre_tags or None,
                any_name_ilike=pre_names or None,
                limit=_DB_LIMIT_PER_BAND,
                is_active=True,
                # The band's rows are cut to _DB_LIMIT_PER_BAND before anything
                # ranks them, so the cut has to keep the places worth showing
                # rather than merely the closest ones.
                order_by_prominence=True,
            )

    band_rows = await asyncio.gather(*(
        _band_query(band_min, band_max) for band_min, band_max in bands
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
    defer_bands: list[int] = []
    near_fill_incomplete = False

    # ── Step 2: Google, only for bands the database could not cover ──────────
    # The near band (index 0) is what the user actually looks at first, so it
    # is the only one worth making this caller wait for. Any short far band
    # always falls through to the background fill below — regardless of
    # whether the near band also needed filling — so a cold far band can never
    # add its latency to the response the user is staring at.
    if short_bands and key not in _active_fills:
        allowed, reason = await spend_guard.allowed(None)
        if not allowed:
            print(f"skipping banded Google fill: {reason}")
        else:
            if 0 in short_bands:
                _active_fills.add(key)
                near_task = asyncio.ensure_future(
                    _google_fill_band(
                        latitude=latitude,
                        longitude=longitude,
                        category=category,
                        band_index=0,
                        band_min=bands[0][0],
                        band_max=bands[0][1],
                    )
                )
                try:
                    # Wait, but only for as long as a user will. A cold tile can
                    # need dozens of Google calls at ~1.7s each, and awaiting
                    # them outright is what made a never-queried location take
                    # 40-50s: the response time was a function of how much work
                    # the tile needed rather than of anything the user could see.
                    #
                    # Past the budget the caller gets what the database and
                    # Redis already hold and the fill carries on without it —
                    # the same bargain the far bands already make. The task is
                    # deliberately not cancelled: it is most of the way through
                    # paid calls, and letting it finish means it warms the cache
                    # for the next visitor instead of wasting the spend.
                    budget = (
                        _NEAR_FILL_BUDGET_S
                        if len(pool) >= _MIN_PLACES_TO_ANSWER_EARLY
                        else _EMPTY_FILL_BUDGET_S
                    )
                    near_filled = await asyncio.wait_for(
                        asyncio.shield(near_task), timeout=budget
                    )
                    pool.extend(near_filled)
                    source = "google"
                    _active_fills.discard(key)
                except asyncio.TimeoutError:
                    # `_active_fills` stays held until the detached task
                    # finishes, so a second request arriving meanwhile joins the
                    # cached answer rather than starting its own duplicate fill.
                    near_task.add_done_callback(
                        lambda _t, k=key: _active_fills.discard(k)
                    )
                    near_fill_incomplete = True
                except Exception:
                    _active_fills.discard(key)
                    raise

            far_short = [i for i in short_bands if i != 0]
            if far_short:
                # Fill the gaps after responding and let the next request serve
                # the richer result. Deferred rather than spawned here: the
                # background task retires this cache key when it finishes, and
                # it must not be able to do so before the write below has
                # happened, or the thinner list would serve out the whole
                # 14-day TTL.
                defer_bands = far_short
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
    await place_cache_service.set_cached(
        key, deduped,
        ttl=_PARTIAL_CACHE_TTL_S if near_fill_incomplete else None,
    )
    _tag_excluded(deduped, excluded_keywords)

    if defer_bands:
        places_service.spawn_background(_fill_bands_bg(
            latitude=latitude,
            longitude=longitude,
            category=category,
            band_indices=defer_bands,
            bands=bands,
            key=key,
        ))
    return _assemble(
        latitude, longitude, category, bands, deduped, max_photos,
        cached_flag=False, source=source, per_band=per_band,
        pending=bool(defer_bands) or near_fill_incomplete,
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
    pending: bool = False,
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

        if category == "Medical":
            # Client-requested even mix: pharmacy / medical_center / other,
            # round-robin rather than pure quality order, so a band doesn't
            # fill up entirely with whichever subtype has the deepest pool
            # here. Each group is still walked in `band_pool`'s existing
            # quality order internally. A group that runs dry just drops out
            # of the rotation — the shortfall that leaves in `picks` is made
            # up by the unmodified total-shortfall backfill below, which is
            # where "fall back to the major sub category" falls out for free:
            # it pulls next-best from whatever's left overall, which in
            # practice is the subtype with supply.
            groups: dict[str, list[dict]] = {
                "pharmacy": [], "medical_center": [], "other": [],
            }
            for p in band_pool:
                groups[place_bands.medical_subgroup(p.get("tags"), p.get("name"))].append(p)
            order = ["pharmacy", "medical_center", "other"]
            idx = {g: 0 for g in order}
            while len(picks) < quota:
                progressed = False
                for g in order:
                    if len(picks) >= quota:
                        break
                    items = groups[g]
                    while idx[g] < len(items) and not _claim(items[idx[g]]):
                        idx[g] += 1
                    if idx[g] < len(items):
                        picks.append(items[idx[g]])
                        idx[g] += 1
                        progressed = True
                if not progressed:
                    break
        else:
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

    # Deliberately empty. This used to repeat every place already present in
    # `bands`, so each one was serialised twice and Around You's six categories
    # weighed 254KB gzipped instead of 129KB — on a mobile connection, paid for
    # on every cold load.
    #
    # Nothing reads it: `fetchBandedPlaces` takes `data['bands']` and always
    # has (checked against every revision of google_places_service.dart in the
    # history). The key stays in the response rather than being removed from
    # the schema so any client that touches it still finds valid JSON.
    return BandedPlacesResponse(
        category=category or "all",
        bands=band_models,
        places=[],
        cached=cached_flag,
        source=source,
        pending=pending,
    )
