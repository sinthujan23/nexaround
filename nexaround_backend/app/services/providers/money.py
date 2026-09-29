"""Provider prices arrive in USD; a plan speaks the traveller's currency.

Providers are always asked in USD, so one cached answer serves every
traveller, and the figure is converted here with the same live rates the
flight and hotel prices use (`serpapi_service._live_fx_rates`), falling back
to the static table when the live source is down.
"""
from __future__ import annotations

import asyncio


async def usd_rate(currency: str) -> float | None:
    """Units of `currency` per US dollar, or None when no rate is known."""
    code = (currency or "USD").strip().upper()
    if code == "USD":
        return 1.0
    from app.services import serpapi_service
    from app.services.trip_cost_floor import FX_PER_USD

    # The live refresh is a blocking urllib call once every six hours; off the
    # event loop, it cannot stall the other plans the worker is building.
    rates = await asyncio.to_thread(serpapi_service._live_fx_rates)
    rate = rates.get(code) or FX_PER_USD.get(code)
    return float(rate) if rate else None


def format_amount(currency: str, amount: float) -> str:
    """"LKR 10,500", "USD 35", and "USD 4.50" where the cents are real money."""
    code = (currency or "USD").strip().upper()
    if amount < 20 and round(amount, 2) != round(amount):
        return f"{code} {amount:,.2f}"
    return f"{code} {amount:,.0f}"


def format_range(currency: str, low: float, high: float) -> str:
    """"USD 17–24": one currency code, two amounts, or one amount when equal."""
    lo, hi = format_amount(currency, low), format_amount(currency, high)
    if lo == hi:
        return lo
    return f"{lo}–{hi.split(' ', 1)[1]}"
