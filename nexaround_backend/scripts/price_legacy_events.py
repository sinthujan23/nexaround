#!/usr/bin/env python3
"""Attach cost estimates to the imported legacy rows.

The import deliberately left cost at zero because the old log recorded an
attempt and never its outcome — so nothing in it proves a call was billed. That
was the right default, but it leaves the dashboard reporting $0.00 against
287,000 real provider calls, which is its own kind of wrong.

This prices them: every legacy row is an upstream attempt, so it is billed at
its SKU rate. The result is an **upper bound**, and it is labelled as one
everywhere it appears. Two things it knowingly overstates:

  * calls that failed. Nginx logs for 3-17 Aug show ~93% of Find Place calls
    returning real data before the key broke on the 14th, and 13-28% after.
  * the free tier. 10,000 calls per SKU per month are not charged; that is
    applied at read time in the dashboard, not baked into the row.

Usage:  docker compose exec api python scripts/price_legacy_events.py [--commit]
"""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text                    # noqa: E402
from app.core.database import async_session    # noqa: E402


PREVIEW = text("""
    SELECT e.sku, r.unit_cost_usd, count(*) rows,
           count(*) * r.unit_cost_usd est_cost
    FROM api_events e
    JOIN api_sku_rates r ON r.sku = e.sku
    WHERE e.ingest = 'legacy' AND e.served_from = 'upstream'
    GROUP BY 1, 2 ORDER BY est_cost DESC
""")

# Token-priced SKUs stay at zero: without recorded token counts there is no
# honest way to price a Gemini call, and a made-up number is worse than a gap.
APPLY = text("""
    UPDATE api_events e
    SET billable = true,
        est_cost_usd = r.unit_cost_usd
    FROM api_sku_rates r
    WHERE r.sku = e.sku
      AND e.ingest = 'legacy'
      AND e.served_from = 'upstream'
      AND r.unit_cost_usd > 0
""")


async def main(commit: bool) -> int:
    async with async_session() as db:
        rows = (await db.execute(PREVIEW)).mappings().all()

    print(f"{'sku':<28}{'rate':>10}{'rows':>12}{'est. cost':>14}")
    total = 0.0
    for r in rows:
        cost = float(r["est_cost"] or 0)
        total += cost
        print(f"{r['sku']:<28}{float(r['unit_cost_usd']):>10.6f}"
              f"{r['rows']:>12,}{cost:>14,.2f}")
    print(f"{'':<28}{'':>10}{'':>12}{'-' * 14}")
    print(f"{'upper bound before free tier':<28}{'':>10}{'':>12}{total:>14,.2f}")

    if not commit:
        print("\ndry run — re-run with --commit to write these estimates")
        return 0

    async with async_session() as db:
        res = await db.execute(APPLY)
        await db.commit()
    print(f"\npriced {res.rowcount:,} legacy rows")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main("--commit" in sys.argv)))
