"""Ingest actual billed cost from Google Cloud, and calibrate rates from it.

Two sources, one destination. A CSV exported from Billing → Reports works today
and covers history; the BigQuery detailed-usage export works automatically but
only from the day it is enabled. Both land in api_billing_actual so the
dashboard does not care which produced a given row.

The point of holding actual cost next to estimates is calibration. A per-call
rate that nobody checks drifts silently — ours ran 15x high and named the wrong
provider as the top cost, because Places was fully covered by free-tier credits
while Gemini quietly became the whole bill. `calibrate_rates` closes that loop:
real cost divided by real usage is the rate, no guessing.
"""
import csv
import io
import logging
import re
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Optional

from sqlalchemy import text

from app.core.database import async_session

logger = logging.getLogger(__name__)


# Google's SKU descriptions mapped onto the operations we record. Matched
# case-insensitively as substrings, most specific first — "Places API Place
# Details" must win over a bare "Places API".
SKU_PATTERNS = [
    (r"find place",                     "findplacefromtext"),
    (r"place details",                  "place_details"),
    (r"place photo",                    "place_photo"),
    (r"nearby search",                  "nearby_search"),
    (r"text search",                    "text_search"),
    (r"autocomplete",                   "autocomplete"),
    (r"\bdirections\b",                 "directions"),
    (r"geocoding|geocode",              "geocode"),
    (r"gemini|generative language",     "generate_content"),
    (r"maps.*(sdk|tiles|dynamic)",      "maps_sdk"),
]


def map_sku(description: str) -> Optional[str]:
    d = (description or "").lower()
    for pattern, operation in SKU_PATTERNS:
        if re.search(pattern, d):
            return operation
    return None


def _dec(value) -> Decimal:
    if value is None or value == "":
        return Decimal("0")
    try:
        # Console CSVs quote thousands separators and occasionally a currency mark.
        return Decimal(re.sub(r"[^\d.\-]", "", str(value)) or "0")
    except (InvalidOperation, ValueError):
        return Decimal("0")


def _find(row: dict, *candidates: str) -> Optional[str]:
    """Locate a column by fuzzy name.

    Google has shipped several header spellings across export versions and
    locales, so matching on a normalised substring is more durable than
    pinning exact names.
    """
    norm = {re.sub(r"[^a-z]", "", k.lower()): k for k in row if k}
    # Exact matches across every candidate before any substring match. Without
    # that ordering, "pricingunit" matches "usageamountinpricingunits" and the
    # unit column silently returns the quantity.
    for cand in candidates:
        key = re.sub(r"[^a-z]", "", cand.lower())
        if key in norm:
            return row[norm[key]]
    for cand in candidates:
        key = re.sub(r"[^a-z]", "", cand.lower())
        for nk, original in norm.items():
            if key in nk:
                return row[original]
    return None


UPSERT = text("""
    INSERT INTO api_billing_actual (
        usage_date, project_id, service, sku, sku_id, usage_amount,
        usage_unit, cost, credits, currency, mapped_operation, source
    ) VALUES (
        :usage_date, :project_id, :service, :sku, :sku_id, :usage_amount,
        :usage_unit, :cost, :credits, :currency, :mapped_operation, :source
    )
    ON CONFLICT (usage_date, project_id, sku, currency) DO UPDATE SET
        usage_amount     = EXCLUDED.usage_amount,
        usage_unit       = EXCLUDED.usage_unit,
        cost             = EXCLUDED.cost,
        credits          = EXCLUDED.credits,
        service          = EXCLUDED.service,
        mapped_operation = EXCLUDED.mapped_operation,
        source           = EXCLUDED.source,
        imported_at      = now()
""")


async def import_csv(content: bytes, default_currency: str = "INR") -> dict:
    """Load a Billing → Reports / Cost table CSV export."""
    text_content = content.decode("utf-8-sig", errors="replace")

    # Console exports often prepend metadata lines before the real header; find
    # the first line that looks like one rather than assuming row zero.
    lines = text_content.splitlines()
    start = 0
    for i, line in enumerate(lines[:25]):
        low = line.lower()
        if ("sku" in low or "service" in low) and ("cost" in low or "usage" in low):
            start = i
            break
    reader = csv.DictReader(io.StringIO("\n".join(lines[start:])))

    imported = skipped = 0
    unmapped: set[str] = set()
    async with async_session() as db:
        for row in reader:
            if not row or all(v in (None, "") for v in row.values()):
                continue
            sku = _find(row, "skudescription", "sku", "skuname")
            raw_date = _find(row, "usagedate", "usagestartdate", "date", "day")
            if not sku or not raw_date:
                skipped += 1
                continue

            parsed = None
            for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%b %d, %Y", "%d %b %Y"):
                try:
                    parsed = datetime.strptime(raw_date.strip()[:11], fmt).date()
                    break
                except (ValueError, AttributeError):
                    continue
            if parsed is None:
                skipped += 1
                continue

            operation = map_sku(sku)
            if operation is None:
                unmapped.add(sku)

            await db.execute(UPSERT, {
                "usage_date": parsed,
                "project_id": (_find(row, "projectid", "projectname", "project") or None),
                "service": (_find(row, "servicedescription", "service") or "unknown")[:128],
                "sku": sku[:256],
                "sku_id": (_find(row, "skuid") or None),
                "usage_amount": _dec(_find(row, "usageamountinpricingunits",
                                           "usageamount", "usage", "quantity")),
                "usage_unit": (_find(row, "pricingunit", "usageunit", "unit") or None),
                "cost": _dec(_find(row, "usagecost", "cost", "subtotal", "charges")),
                "credits": _dec(_find(row, "credits", "othersavings",
                                      "promotionsandothers", "savings")),
                "currency": (_find(row, "currency") or default_currency)[:8],
                "mapped_operation": operation,
                "source": "csv",
            })
            imported += 1
        await db.commit()

    return {"imported": imported, "skipped": skipped,
            "unmapped_skus": sorted(unmapped)[:40]}


BQ_SQL = """
    SELECT
      DATE(usage_start_time)                    AS usage_date,
      project.id                                AS project_id,
      service.description                       AS service,
      sku.description                           AS sku,
      sku.id                                    AS sku_id,
      SUM(usage.amount_in_pricing_units)        AS usage_amount,
      ANY_VALUE(usage.pricing_unit)             AS usage_unit,
      SUM(cost)                                 AS cost,
      SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS credits,
      ANY_VALUE(currency)                       AS currency
    FROM `{table}`
    WHERE DATE(usage_start_time) >= @since
    GROUP BY 1,2,3,4,5
"""


async def sync_bigquery(days: int = 35) -> dict:
    """Pull the detailed usage export. Requires the BigQuery client and a
    service-account key with dataset read access."""
    from datetime import timedelta
    try:
        from google.cloud import bigquery
    except ImportError:
        return {"error": "google-cloud-bigquery is not installed in this image"}

    async with async_session() as db:
        dataset = (await db.execute(text(
            "SELECT value FROM system_settings WHERE key='gcp_billing_dataset'"
        ))).scalar()
    if not dataset:
        return {"error": "gcp_billing_dataset is not configured"}

    client = bigquery.Client()
    since = (datetime.now(timezone.utc) - timedelta(days=days)).date()
    job = client.query(
        BQ_SQL.format(table=dataset),
        job_config=bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter("since", "DATE", since)]),
    )

    imported = 0
    async with async_session() as db:
        for r in job.result():
            await db.execute(UPSERT, {
                "usage_date": r.usage_date, "project_id": r.project_id,
                "service": (r.service or "unknown")[:128], "sku": (r.sku or "")[:256],
                "sku_id": r.sku_id, "usage_amount": r.usage_amount,
                "usage_unit": r.usage_unit, "cost": r.cost, "credits": r.credits,
                "currency": r.currency or "USD",
                "mapped_operation": map_sku(r.sku or ""), "source": "bigquery",
            })
            imported += 1
        await db.commit()
    return {"imported": imported, "since": str(since)}


async def calibrate_rates(min_usage: float = 100.0) -> dict:
    """Derive per-call rates from actual cost divided by actual usage.

    Only SKUs with meaningful volume are calibrated — dividing a rounding-error
    cost by three calls produces a confident and wrong number. Rates set this
    way are marked `source='billing'` so the dashboard can show which figures
    rest on measurement and which are still someone's guess.
    """
    rows_sql = text("""
        SELECT mapped_operation, sum(usage_amount) usage, sum(cost) cost,
               sum(credits) credits, max(currency) currency
        FROM api_billing_actual
        WHERE mapped_operation IS NOT NULL
          AND usage_date >= CURRENT_DATE - 60
        GROUP BY 1 HAVING sum(usage_amount) >= :min_usage
    """)
    updated = []
    async with async_session() as db:
        for r in (await db.execute(rows_sql, {"min_usage": min_usage})).mappings():
            usage = float(r["usage"] or 0)
            if usage <= 0:
                continue
            # Gross cost, before credits: the free tier is a monthly allowance
            # applied at read time, not a property of the call's price.
            rate = float(r["cost"] or 0) / usage
            res = await db.execute(text("""
                UPDATE api_sku_rates
                SET unit_cost_usd = :rate, currency = :cur,
                    source = 'billing', calibrated_at = now(),
                    notes = COALESCE(notes,'') || ' [calibrated from billing]'
                WHERE sku IN (
                    SELECT sku FROM api_sku_rates
                    WHERE :op = ANY(string_to_array(sku, '_')) OR sku LIKE :like
                )
            """), {"rate": rate, "cur": r["currency"] or "USD",
                   "op": r["mapped_operation"], "like": f"%{r['mapped_operation']}%"})
            if res.rowcount:
                updated.append({"operation": r["mapped_operation"],
                                "rate": round(rate, 8), "usage": usage,
                                "currency": r["currency"]})
        await db.commit()

    from app.services import telemetry
    await telemetry.refresh_rates()
    return {"calibrated": updated}
