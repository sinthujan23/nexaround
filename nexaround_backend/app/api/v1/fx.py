"""Currency exchange rates: the app's daily table, and the admin's monitor."""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import verify_admin_token
from app.core.database import get_db
from app.services import fx_service

router = APIRouter(prefix="/fx", tags=["Currency"])
admin_router = APIRouter(prefix="/admin/fx", tags=["Admin - Currency"])

# The samples the admin card shows, to eyeball that the numbers are sane.
SAMPLE_CURRENCIES = ("QAR", "INR", "LKR", "AED", "EUR", "GBP")


class FxRatesResponse(BaseModel):
    base: str
    # Units of each currency per one `base`.
    rates: dict[str, float]
    provider_updated_at: Optional[datetime] = None
    next_update_at: Optional[datetime] = None
    fetched_at: Optional[datetime] = None


class FxQuota(BaseModel):
    plan_quota: Optional[int] = None
    requests_remaining: Optional[int] = None
    requests_used: Optional[int] = None
    refresh_day_of_month: Optional[int] = None


class FxStatusResponse(BaseModel):
    # "ok" | "stale" | "error"
    status: str
    source: Optional[str] = None
    has_key: bool = False
    key_hint: str = ""
    provider_updated_at: Optional[datetime] = None
    next_update_at: Optional[datetime] = None
    fetched_at: Optional[datetime] = None
    last_attempt_at: Optional[datetime] = None
    last_error: Optional[str] = None
    currency_count: int = 0
    samples: dict[str, float] = {}
    quota: Optional[FxQuota] = None


@router.get("/rates", response_model=FxRatesResponse)
async def get_rates(response: Response, db: AsyncSession = Depends(get_db)):
    """Today's rates for converting prices in the app. Open, like the prices
    themselves; they change once a day, so clients may cache them for an hour."""
    row = await fx_service.get_row(db)
    if row is None or not row.rates:
        raise HTTPException(status_code=503, detail="Exchange rates are not available yet.")
    response.headers["Cache-Control"] = "public, max-age=3600"
    return FxRatesResponse(
        base=row.base,
        rates=row.rates,
        provider_updated_at=row.provider_updated_at,
        next_update_at=row.provider_next_update_at,
        fetched_at=row.fetched_at,
    )


async def _status(db: AsyncSession, with_quota: bool = True) -> FxStatusResponse:
    from app.services.settings_service import SettingsService

    key = (await SettingsService(db).get_setting_fresh(fx_service.KEY_SETTING, "")).strip()
    row = await fx_service.get_row(db)
    now = datetime.now(timezone.utc)
    quota = await fx_service.quota(db) if with_quota else None
    rates = (row.rates if row else None) or {}
    return FxStatusResponse(
        status=fx_service.health(
            row.fetched_at if row else None, row.last_error if row else None, now
        ),
        source=row.source if row else None,
        has_key=bool(key),
        key_hint=fx_service.mask_key(key),
        provider_updated_at=row.provider_updated_at if row else None,
        next_update_at=row.provider_next_update_at if row else None,
        fetched_at=row.fetched_at if row else None,
        last_attempt_at=row.last_attempt_at if row else None,
        last_error=row.last_error if row else None,
        currency_count=len(rates),
        samples={c: rates[c] for c in SAMPLE_CURRENCIES if c in rates},
        quota=FxQuota(**quota) if quota else None,
    )


@admin_router.get("/status", response_model=FxStatusResponse)
async def fx_status(db: AsyncSession = Depends(get_db), _=Depends(verify_admin_token)):
    """When the rates were last updated, whether the last try worked, and how
    much of the month's request allowance is left."""
    return await _status(db)


@admin_router.post("/refresh", response_model=FxStatusResponse)
async def fx_refresh(db: AsyncSession = Depends(get_db), _=Depends(verify_admin_token)):
    """Fetch now (one request from the monthly allowance)."""
    await fx_service.refresh(db)
    return await _status(db)
