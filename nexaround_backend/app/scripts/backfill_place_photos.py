"""One-off backfill: give photo-less rows a Google Place ID, and their photos.

The gap this closes: ~5.5k attractions were seeded with neither a
`google_place_id` nor any `photo_urls`. Every photo fix in the read path keys
off one or the other, so these rows could never show a picture no matter what
— they fell straight through to the category icon. Nothing was broken; there
was simply no identifier to ask Google with.

Resolution is by name plus stored location, the same Places API (New) Text
Search the detail page uses to resolve a local row. A match is only accepted
if it comes back within `_MAX_MATCH_M` of the coordinates we already hold —
the names in this table are generic enough ("Sunrise garden", "Marwa Stores")
that an unchecked first result would happily attach the wrong place's photos
to the row, which is worse than the icon it replaces.

Expect roughly a third of rows to gain photos: sampling showed most of the
rest are tanks, playing fields and unnamed spots that Google itself holds no
photograph of. Those still get their Place ID stored, so they are not
re-resolved on the next run and can be enriched later.

Usage:
    python -m app.scripts.backfill_place_photos              # dry run (default)
    python -m app.scripts.backfill_place_photos --apply      # write the changes
    python -m app.scripts.backfill_place_photos --limit 50   # cap rows examined
"""
import argparse
import asyncio
import sys

import httpx
from sqlalchemy import text

from app.core.database import async_session
from app.services.google_places_client import _haversine_m
from app.services.settings_service import SettingsService
from app.services.places_service import _photo_url

_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText"
_FIELD_MASK = "places.id,places.location,places.photos"

#: How far a returned place may sit from the coordinates we already store
#: before the match is rejected as a different place of a similar name.
_MAX_MATCH_M = 3000.0

#: Bias radius for the search itself. Wider than the acceptance radius so a
#: slightly-off stored coordinate still surfaces the right candidate, which
#: the distance check then confirms.
_BIAS_M = 10000.0

#: Matches to_place_dict — the app renders one hero and keeps a spare.
_MAX_PHOTOS = 2

#: Google is fine with this; the point is to stay a good citizen on a job that
#: issues thousands of requests back to back.
_CONCURRENCY = 5


async def _resolve(client, api_key, row) -> dict | None:
    """Find the Google place for one row, or None if nothing trustworthy."""
    body = {
        "textQuery": row["name"],
        "maxResultCount": 1,
        "locationBias": {"circle": {
            "center": {"latitude": row["lat"], "longitude": row["lng"]},
            "radius": _BIAS_M,
        }},
    }
    resp = await client.post(
        _SEARCH_URL, json=body, timeout=30.0,
        headers={
            "X-Goog-Api-Key": api_key,
            "Content-Type": "application/json",
            "X-Goog-FieldMask": _FIELD_MASK,
        },
    )
    if resp.status_code != 200:
        print(f"  ! HTTP {resp.status_code} for {row['name'][:40]!r}")
        return None
    data = resp.json()
    if "error" in data:
        err = data["error"]
        print(f"  ! {err.get('status')}: {err.get('message', '')[:80]}")
        return None

    places = data.get("places") or []
    if not places:
        return None
    place = places[0]
    loc = place.get("location") or {}
    if loc.get("latitude") is None:
        return None

    distance = _haversine_m(row["lat"], row["lng"], loc["latitude"], loc["longitude"])
    if distance > _MAX_MATCH_M:
        # A same-named place somewhere else. Leaving the row alone is correct.
        return None

    photos = [
        _photo_url(ph["name"], idx)
        for idx, ph in enumerate((place.get("photos") or [])[:_MAX_PHOTOS])
        if ph.get("name")
    ]
    return {"place_id": place["id"], "photos": photos, "distance_m": distance}


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="write the changes")
    parser.add_argument("--limit", type=int, default=None, help="cap rows examined")
    args = parser.parse_args()

    async with async_session() as db:
        api_key = await SettingsService(db).get_setting("google_maps_api_key")
    if not api_key:
        print("google_maps_api_key not configured — nothing to do.")
        return 1

    sql = """
        select id::text as id, name,
               ST_Y(location::geometry) as lat,
               ST_X(location::geometry) as lng
        from attractions
        where coalesce(array_length(photo_urls, 1), 0) = 0
          and google_place_id is null
        order by id
    """
    if args.limit:
        sql += f" limit {int(args.limit)}"

    async with async_session() as db:
        rows = [dict(r) for r in (await db.execute(text(sql))).mappings()]

    mode = "APPLY" if args.apply else "DRY RUN"
    print(f"[{mode}] {len(rows)} rows with no photo and no Google ID\n")

    sem = asyncio.Semaphore(_CONCURRENCY)
    resolved = with_photos = unmatched = 0
    updates: list[dict] = []

    async with httpx.AsyncClient() as client:
        async def work(row):
            nonlocal resolved, with_photos, unmatched
            async with sem:
                try:
                    hit = await _resolve(client, api_key, row)
                except Exception as e:
                    print(f"  ! {row['name'][:40]!r}: {e}")
                    return
            if not hit:
                unmatched += 1
                return
            resolved += 1
            if hit["photos"]:
                with_photos += 1
            updates.append({
                "id": row["id"],
                "gid": hit["place_id"],
                "photos": hit["photos"],
            })

        # Chunked so progress is visible and a long run can be watched.
        for start in range(0, len(rows), 100):
            chunk = rows[start:start + 100]
            await asyncio.gather(*(work(r) for r in chunk))
            print(f"  … {min(start + 100, len(rows))}/{len(rows)}  "
                  f"resolved={resolved} with_photos={with_photos} unmatched={unmatched}")

    print(f"\n[{mode}] examined={len(rows)} resolved={resolved} "
          f"with_photos={with_photos} unmatched={unmatched}")

    if not args.apply:
        print("\nSample of what would be written:")
        for u in updates[:10]:
            print(f"  {u['gid']}  photos={len(u['photos'])}")
        print("\nDry run — nothing written. Re-run with --apply.")
        return 0

    written = 0
    async with async_session() as db:
        for u in updates:
            await db.execute(
                text("""update attractions
                        set google_place_id = :gid,
                            photo_urls = case when :n > 0 then :photos else photo_urls end
                        where id = cast(:id as uuid)"""),
                {"gid": u["gid"], "photos": u["photos"],
                 "n": len(u["photos"]), "id": u["id"]},
            )
            written += 1
        await db.commit()

    print(f"Wrote {written} rows ({with_photos} of them gained photos).")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
