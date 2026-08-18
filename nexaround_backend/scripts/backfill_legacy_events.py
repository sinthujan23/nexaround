#!/usr/bin/env python3
"""Import api_request_logs into api_events so history is visible.

Those rows were written before the HTTP call, so they record an *attempt* and
nothing else: no outcome, no latency, no cache tier, no cost. They are still
the only record of what the platform did between May and August, so they are
imported with `ingest='legacy'` and everything unknown left NULL rather than
guessed at.

What is carried across is real: timestamp, provider, operation, user. What is
not is left empty — a legacy row never claims a cost, because inventing one
would put a fabricated number next to a measured one and make the whole
dashboard untrustworthy.

Usage:  docker compose exec api python scripts/backfill_legacy_events.py [--commit]
"""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text                      # noqa: E402
from app.core.database import async_session      # noqa: E402
from app.services import telemetry               # noqa: E402


# api_request_logs.endpoint -> (operation, sku). Same mapping the proxy uses
# today, so legacy and live rows group together in the dashboard.
ENDPOINT_MAP = [
    ("/maps/api/place/findplacefromtext", "findplacefromtext", "find_place_atmosphere"),
    ("/maps/api/place/nearbysearch",      "nearby_search",     "nearby_search_legacy"),
    ("/maps/api/place/autocomplete",      "autocomplete",      "autocomplete_per_request"),
    ("/maps/api/place/details",           "place_details",     "place_details"),
    ("/maps/api/place/photo",             "place_photo",       "place_photo"),
    ("/maps/api/directions",              "directions",        "directions"),
    ("/maps/api/geocode",                 "geocode",           "geocoding"),
    ("/v1/geocode/reverse",               "geocode_reverse",   "geoapify_reverse"),
    ("/geocoding/v5/mapbox.places",       "geocode_reverse_fallback", "mapbox_geocoding"),
    ("/directions/v5/mapbox",             "directions",        "mapbox_directions"),
    ("/v1beta/models",                    "generate_content",  "gemini_flash_generate"),
]


def classify(endpoint: str) -> tuple[str, str | None]:
    for prefix, operation, sku in ENDPOINT_MAP:
        if endpoint.startswith(prefix):
            return operation, sku
    return (endpoint.strip("/").split("/")[-1] or "unknown"), None


INSERT = text("""
    INSERT INTO api_events (
        ts, provider, operation, sku, served_from, billable, est_cost_usd,
        user_id, cache_key, ingest
    )
    SELECT l.timestamp, l.api_name, :operation, :sku,
           'upstream', false, 0, l.user_id, NULL, 'legacy'
    FROM api_request_logs l
    WHERE l.id = :log_id
""")


async def main(commit: bool) -> int:
    async with async_session() as db:
        span = (await db.execute(text("""
            SELECT min(timestamp) lo, max(timestamp) hi, count(*) n
            FROM api_request_logs
        """))).mappings().one()
        print(f"source: {span['n']:,} rows, {span['lo']} → {span['hi']}")

        # Re-runnable: skip only the months already present, so a partition
        # lost to retention can be re-imported without duplicating the rest.
        done = set((await db.execute(text("""
            SELECT DISTINCT date_trunc('month', ts)::date
            FROM api_events WHERE ingest = 'legacy'
        """))).scalars().all())
        if done:
            print(f"already imported months: {sorted(str(d)[:7] for d in done)}")

        groups = (await db.execute(text("""
            SELECT api_name, endpoint, count(*) n
            FROM api_request_logs GROUP BY 1,2 ORDER BY 3 DESC
        """))).mappings().all()

    print(f"\n{'provider':<14}{'endpoint':<42}{'operation':<26}{'rows':>9}")
    for g in groups:
        op_name, sku = classify(g["endpoint"])
        print(f"{g['api_name']:<14}{g['endpoint'][:40]:<42}{op_name:<26}{g['n']:>9,}")

    if not commit:
        print("\ndry run — re-run with --commit to import")
        return 0

    # Partitions must exist for every month being imported, or the INSERT has
    # nowhere to route the row.
    async with async_session() as db:
        months = (await db.execute(text("""
            SELECT DISTINCT date_trunc('month', timestamp)::date m
            FROM api_request_logs ORDER BY 1
        """))).scalars().all()
        for m in months:
            await db.execute(
                text("SELECT ensure_api_events_partition(:m)"), {"m": m})
        await db.commit()
    print(f"\npartitions ensured for {len(months)} month(s)")

    total = 0
    async with async_session() as db:
        for g in groups:
            op_name, sku = classify(g["endpoint"])
            res = await db.execute(text("""
                INSERT INTO api_events (
                    ts, provider, operation, sku, served_from, billable,
                    est_cost_usd, user_id, ingest
                )
                SELECT l.timestamp, l.api_name, :operation, :sku,
                       'upstream', false, 0, l.user_id, 'legacy'
                FROM api_request_logs l
                WHERE l.api_name = :api_name AND l.endpoint = :endpoint
                  AND date_trunc('month', l.timestamp)::date <> ALL(:done)
            """), {"operation": op_name, "sku": sku,
                   "api_name": g["api_name"], "endpoint": g["endpoint"],
                   "done": list(done) or [__import__("datetime").date(1970, 1, 1)]})
            total += res.rowcount or 0
            print(f"  imported {res.rowcount:>8,}  {g['api_name']}/{op_name}")
        await db.commit()

    print(f"\nimported {total:,} legacy rows")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main("--commit" in sys.argv)))
