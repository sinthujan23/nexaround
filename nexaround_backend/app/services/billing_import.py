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
    # Gemini is split by direction, and the split is the whole story: reasoning
    # tokens bill at the output rate, so output and input must not be merged.
    (r"output token.*gemini|gemini.*output token",  "generate_content_output"),
    (r"input token.*gemini|gemini.*input token",    "generate_content_input"),
    (r"gemini|generative language",                 "generate_content"),
    # Places bills the lookup and its returned field groups as separate SKUs.
    # Atmosphere Data is what `rating` and `user_ratings_total` cost on top of
    # a Find Place call, which is why it appears without a call of its own.
    (r"atmosphere data",                "find_place_atmosphere_addon"),
    (r"contact data",                   "find_place_contact_addon"),
    (r"basic data",                     "find_place_basic_addon"),
    (r"find place",                     "findplacefromtext"),
    (r"place details|places details",   "place_details"),
    (r"place photo|places photo",       "place_photo"),
    (r"nearby search",                  "nearby_search"),
    (r"text search",                    "text_search"),
    (r"autocomplete",                   "autocomplete"),
    (r"\bdirections\b",                 "directions"),
    (r"geocoding|geocode",              "geocode"),
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


async def import_csv(content: bytes, default_currency: str = "INR",
                     period_start: date = None, period_end: date = None) -> dict:
    """Load a Billing → Reports or Cost table CSV export.

    Two shapes exist. A per-day export carries a usage date; a grouped-by-SKU
    export is a summary over the whole reporting period and carries none. The
    second is more useful for calibration — cost divided by usage is a rate
    regardless of how the period is sliced — so a missing date is not an error,
    it just needs the period supplied and is marked so the daily chart can
    exclude it rather than draw a spike on one arbitrary day.
    """
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
            sku = _find(row, "skudescription", "skuname", "sku")
            # Trailing Subtotal / Tax / Total rows have no SKU. Skip them
            # silently; counting them as failures would misreport the import.
            if not sku or not sku.strip():
                skipped += 1
                continue

            raw_date = _find(row, "usagedate", "usagestartdate", "date", "day")
            parsed = None
            if raw_date:
                for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%b %d, %Y", "%d %b %Y"):
                    try:
                        parsed = datetime.strptime(raw_date.strip()[:11], fmt).date()
                        break
                    except (ValueError, AttributeError):
                        continue
            row_source = "csv"
            if parsed is None:
                if period_end is None:
                    skipped += 1
                    continue
                parsed = period_end
                row_source = "csv-period"

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
                # List cost is the gross charge before credits; subtotal is
                # after. Storing gross plus credits separately is what lets the
                # dashboard show that Places was used heavily and still cost
                # nothing, rather than reporting it as unused.
                "cost": _dec(_find(row, "listcost", "usagecost", "cost", "charges")),
                "credits": _dec(_find(row, "othersavings", "credits",
                                      "promotionsandothers", "savingsprograms")),
                "currency": (_find(row, "currency") or default_currency)[:8],
                "mapped_operation": operation,
                "source": row_source,
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


# Which rate row each billed operation feeds. Explicit, because fuzzy matching
# between Google's SKU names and our internal ones silently matched nothing —
# "findplacefromtext" shares no token with "find_place_atmosphere".
OPERATION_TO_SKU = {
    "generate_content_output": ("gemini_flash_generate", "output_per_1k_usd", 1000),
    "generate_content_input":  ("gemini_flash_generate", "input_per_1k_usd", 1000),
    "findplacefromtext":       ("find_place_basic", "unit_cost_usd", 1),
    "find_place_atmosphere_addon": ("find_place_atmosphere", "unit_cost_usd", 1),
    "directions":              ("directions", "unit_cost_usd", 1),
    "geocode":                 ("geocoding", "unit_cost_usd", 1),
    "place_details":           ("place_details", "unit_cost_usd", 1),
    "place_photo":             ("place_photo", "unit_cost_usd", 1),
    "autocomplete":            ("autocomplete_per_request", "unit_cost_usd", 1),
    "nearby_search":           ("nearby_search_new", "unit_cost_usd", 1),
    "text_search":             ("text_search_new", "unit_cost_usd", 1),
}


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
    updated, unmatched = [], []
    async with async_session() as db:
        fx = float((await db.execute(text(
            "SELECT value FROM system_settings WHERE key='billing_fx_to_usd'"
        ))).scalar() or 1.0) or 1.0

        for r in (await db.execute(rows_sql, {"min_usage": min_usage})).mappings():
            usage = float(r["usage"] or 0)
            op = r["mapped_operation"]
            if usage <= 0 or op not in OPERATION_TO_SKU:
                if op:
                    unmatched.append(op)
                continue
            sku, column, per = OPERATION_TO_SKU[op]

            # List cost, not the post-credit subtotal. Credits are a monthly
            # allowance, not a property of what a call costs — pricing off the
            # net would say Find Place is free right up until the allowance
            # runs out, and then be wrong by the whole amount.
            native = float(r["cost"] or 0) / usage * per
            rate_usd = native / fx

            res = await db.execute(text(f"""
                UPDATE api_sku_rates
                SET {column} = :rate, source = 'billing', calibrated_at = now()
                WHERE sku = :sku
            """), {"rate": rate_usd, "sku": sku})
            if res.rowcount:
                updated.append({
                    "operation": op, "sku": sku, "field": column,
                    "usage": usage, "rate_usd": round(rate_usd, 10),
                    "native_per_unit": round(native / per, 8),
                    "currency": r["currency"],
                })
        await db.commit()

    from app.services import telemetry
    await telemetry.refresh_rates()
    return {"calibrated": updated, "unmatched": sorted(set(unmatched))}
