"""Subscriptions: the app's plan status, and RevenueCat's store events.

Payment happens in the app through Apple / Google in-app purchase, managed by
RevenueCat. RevenueCat tells us about every purchase, renewal, cancellation and
expiry through `POST /billing/revenuecat`; the app also calls `/billing/sync`
right after a purchase so the plan unlocks without waiting for the webhook.
Either way the plan is read from RevenueCat's own record of the customer when
a secret API key is configured, so an event arriving late or out of order can
never leave a user on the wrong plan.

Admin (`/admin/billing/*`): subscribers, revenue, hand-granted plans, and the
plan settings (enforce switch, test accounts, limits, minimum app version).
"""
from __future__ import annotations

import hmac
import json
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.admin import require_admin, verify_admin_token
from app.core.database import get_db
from app.models.subscription import Subscription, SubscriptionEvent
from app.models.user import User
from app.services import plan_service
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/billing", tags=["Billing"])
admin_router = APIRouter(prefix="/admin/billing", tags=["Admin - Billing"])

K_WEBHOOK_SECRET = "revenuecat_webhook_secret"
K_API_KEY = "revenuecat_api_key"
K_IOS_KEY = "revenuecat_ios_key"          # public SDK key, served by /config/keys
K_ANDROID_KEY = "revenuecat_android_key"  # public SDK key, served by /config/keys
RC_API = "https://api.revenuecat.com/v1"

# Display prices (USD) for the revenue estimate when an event carries none.
CATALOG_PRICES = {
    ("voyager", "monthly"): 4.59, ("voyager", "yearly"): 45.99,
    ("globetrotter", "monthly"): 6.89, ("globetrotter", "yearly"): 68.99,
}
_REVENUE_EVENTS = ("INITIAL_PURCHASE", "RENEWAL", "NON_RENEWING_PURCHASE", "PRODUCT_CHANGE")


# ── RevenueCat record → our row (pure, unit-tested) ─────────────────────────

def _dt(value) -> Optional[datetime]:
    """RevenueCat dates: ISO strings in the REST API, epoch ms in webhooks."""
    if value in (None, ""):
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value / 1000, tz=timezone.utc)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def plan_from_ids(*ids: Optional[str]) -> Optional[str]:
    """Which plan an entitlement or product id stands for."""
    joined = " ".join(i.lower() for i in ids if i)
    if "globetrotter" in joined:
        return plan_service.GLOBETROTTER
    if "voyager" in joined:
        return plan_service.VOYAGER
    return None


def period_from_product(product_id: Optional[str]) -> Optional[str]:
    """`voyager_yearly` (App Store) or `voyager:yearly` (Play base plan)."""
    p = (product_id or "").lower()
    if "year" in p or "annual" in p:
        return "yearly"
    if "month" in p:
        return "monthly"
    return None


def state_from_subscriber(subscriber: dict, now: Optional[datetime] = None) -> Optional[dict]:
    """The best plan in a RevenueCat `subscriber` object, as row values.

    Returns None when the customer has never had a plan entitlement. A plan
    that has run out comes back with status 'expired' and its old end date, so
    the row stays for the record but no longer unlocks anything.
    """
    now = now or datetime.now(timezone.utc)
    entitlements = subscriber.get("entitlements") or {}
    subscriptions = subscriber.get("subscriptions") or {}
    candidates = []
    for ent_id, ent in entitlements.items():
        product = ent.get("product_identifier") or ""
        plan = plan_from_ids(ent_id, product)
        if not plan:
            continue
        expires = _dt(ent.get("grace_period_expires_date")) or _dt(ent.get("expires_date"))
        # Play's subscriptions are keyed by subscription id, its products by
        # "subscription:base-plan"; the App Store keys both by product id.
        sub = subscriptions.get(product) or subscriptions.get(product.split(":")[0]) or {}
        candidates.append((plan, product, expires, ent, sub))
    if not candidates:
        return None

    def _alive(c) -> bool:
        return c[2] is None or c[2] > now

    far = datetime.max.replace(tzinfo=timezone.utc)
    live = [c for c in candidates if _alive(c)]
    pool = live or candidates
    plan, product, expires, ent, sub = max(
        pool, key=lambda c: (plan_service.PLAN_RANK[c[0]], c[2] or far),
    )

    if not _alive((plan, product, expires)) or sub.get("refunded_at"):
        status = "expired"
    elif sub.get("billing_issues_detected_at"):
        status = "billing_issue"
    elif sub.get("unsubscribe_detected_at"):
        status = "cancelled"
    else:
        status = "active"
    return {
        "plan": plan,
        "period": period_from_product(product),
        "store": (sub.get("store") or "").lower() or None,
        "status": status,
        "product_id": product or None,
        "period_start": _dt(ent.get("purchase_date")) or _dt(sub.get("purchase_date")),
        "period_end": expires if not sub.get("refunded_at") else min(expires or now, now),
        "auto_renew": status == "active",
        "environment": "SANDBOX" if sub.get("is_sandbox") else "PRODUCTION",
    }


def state_from_event(event: dict, now: Optional[datetime] = None) -> Optional[dict]:
    """Fallback when no RevenueCat API key is set: read the plan off the event."""
    now = now or datetime.now(timezone.utc)
    etype = (event.get("type") or "").upper()
    product = event.get("new_product_id") if etype == "PRODUCT_CHANGE" else None
    product = product or event.get("product_id") or ""
    plan = plan_from_ids(*(event.get("entitlement_ids") or []), event.get("entitlement_id"), product)
    if not plan:
        return None
    expires = (_dt(event.get("grace_period_expiration_at_ms"))
               or _dt(event.get("expiration_at_ms")))
    status = {
        "CANCELLATION": "cancelled",
        "BILLING_ISSUE": "billing_issue",
        "EXPIRATION": "expired",
    }.get(etype, "active")
    if status == "expired":
        expires = min(expires or now, now)
    return {
        "plan": plan,
        "period": period_from_product(product),
        "store": (event.get("store") or "").lower() or None,
        "status": status,
        "product_id": product or None,
        "period_start": _dt(event.get("purchased_at_ms")),
        "period_end": expires,
        "auto_renew": status == "active",
        "environment": (event.get("environment") or "").upper() or None,
    }


def _as_uuid(value) -> Optional[uuid.UUID]:
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError):
        return None


def event_user_ids(event: dict) -> list[uuid.UUID]:
    """Our user ids an event is about. The app logs in to RevenueCat with our
    user id; an anonymous purchase made before login carries it as an alias."""
    ids: list = [event.get("app_user_id"), event.get("original_app_user_id")]
    ids += list(event.get("aliases") or [])
    if (event.get("type") or "").upper() == "TRANSFER":
        ids += list(event.get("transferred_from") or []) + list(event.get("transferred_to") or [])
    out: list[uuid.UUID] = []
    for raw in ids:
        u = _as_uuid(raw)
        if u and u not in out:
            out.append(u)
    return out


# ── Storage ─────────────────────────────────────────────────────────────────

async def _store_state(db: AsyncSession, user_id: uuid.UUID, state: Optional[dict]) -> None:
    row = (await db.execute(select(Subscription).where(
        Subscription.user_id == user_id, Subscription.source == "revenuecat",
    ))).scalar_one_or_none()
    if state is None:
        if row is not None and (row.period_end is None or row.period_end > datetime.now(timezone.utc)):
            row.status = "expired"
            row.period_end = datetime.now(timezone.utc)
            row.auto_renew = False
    else:
        if row is None:
            row = Subscription(user_id=user_id, source="revenuecat", **state)
            db.add(row)
        else:
            for k, v in state.items():
                setattr(row, k, v)
    await db.commit()
    await plan_service.invalidate(user_id)


async def _settings(db: AsyncSession) -> SettingsService:
    return SettingsService(db)


async def fetch_subscriber(api_key: str, app_user_id: str) -> Optional[dict]:
    """RevenueCat's current record of one customer, or None if unreachable."""
    if not api_key:
        return None
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                f"{RC_API}/subscribers/{app_user_id}",
                headers={"Authorization": f"Bearer {api_key}"},
            )
        if resp.status_code != 200:
            logger.warning("RevenueCat subscriber %s: HTTP %s", app_user_id, resp.status_code)
            return None
        return (resp.json() or {}).get("subscriber") or {}
    except Exception as e:
        logger.warning("RevenueCat subscriber %s failed: %s", app_user_id, e)
        return None


async def refresh_user(db: AsyncSession, user_id: uuid.UUID, api_key: str) -> bool:
    """Re-read one user's plan from RevenueCat. False if RevenueCat could not
    be asked, so the caller can fall back to the event."""
    subscriber = await fetch_subscriber(api_key, str(user_id))
    if subscriber is None:
        return False
    await _store_state(db, user_id, state_from_subscriber(subscriber))
    return True


# ── App endpoints ───────────────────────────────────────────────────────────

@router.get("/plan")
async def my_plan(current_user: User = Depends(get_current_user)):
    """The signed-in user's plan, limits, what is used and when it resets, and
    every plan's limits for the plans screen."""
    return await plan_service.plan_summary(current_user.id)


@router.post("/sync")
async def sync_my_plan(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Called by the app right after a purchase or restore: the plan unlocks
    now, not whenever the store's webhook arrives."""
    api_key = (await SettingsService(db).get_setting_fresh(K_API_KEY, "")).strip()
    if api_key:
        await refresh_user(db, current_user.id, api_key)
    return await plan_service.plan_summary(current_user.id)


@router.post("/revenuecat", include_in_schema=False)
async def revenuecat_webhook(request: Request, db: AsyncSession = Depends(get_db)):
    """RevenueCat → us. Authenticated by the Authorization header value set in
    RevenueCat's webhook settings; idempotent on the event id."""
    svc = SettingsService(db)
    secret = (await svc.get_setting_fresh(K_WEBHOOK_SECRET, "")).strip()
    if not secret:
        raise HTTPException(status_code=503, detail="Webhook not configured")
    sent = (request.headers.get("Authorization") or "").strip()
    if sent.lower().startswith("bearer "):
        sent = sent[7:].strip()
    if not hmac.compare_digest(sent.encode(), secret.encode()):
        raise HTTPException(status_code=401, detail="Bad authorization")

    try:
        body = await request.json()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid JSON")
    event = (body or {}).get("event") or {}
    event_id = str(event.get("id") or "")
    etype = str(event.get("type") or "").upper()
    if not event_id or not etype:
        raise HTTPException(status_code=400, detail="Missing event id or type")

    if (await db.execute(select(SubscriptionEvent.id).where(
        SubscriptionEvent.event_id == event_id,
    ))).first():
        return {"ok": True, "duplicate": True}

    user_ids = event_user_ids(event)
    known = set()
    if user_ids:
        known = {r[0] for r in (await db.execute(
            select(User.id).where(User.id.in_(user_ids))
        )).all()}
    users = [u for u in user_ids if u in known]

    def _num(v):
        try:
            return round(float(v), 2) if v is not None else None
        except (TypeError, ValueError):
            return None

    db.add(SubscriptionEvent(
        event_id=event_id[:100],
        user_id=users[0] if users else None,
        type=etype[:40],
        product_id=(event.get("new_product_id") or event.get("product_id") or None),
        store=((event.get("store") or "").lower() or None),
        environment=((event.get("environment") or "").upper() or None),
        price_usd=_num(event.get("price")),
        currency=(event.get("currency") or None),
        price_local=_num(event.get("price_in_purchased_currency")),
        event_at=_dt(event.get("event_timestamp_ms")),
        payload=event,
    ))
    await db.commit()

    if etype == "TEST" or not users:
        if not users and etype != "TEST":
            logger.warning("RevenueCat %s %s: no matching user (%s)", etype, event_id,
                           event.get("app_user_id"))
        return {"ok": True}

    api_key = (await svc.get_setting_fresh(K_API_KEY, "")).strip()
    for user_id in users:
        if not await refresh_user(db, user_id, api_key):
            if etype == "TRANSFER":
                continue  # nothing in the event says which side holds the plan
            await _store_state(db, user_id, state_from_event(event))
    return {"ok": True}


# ── Admin ───────────────────────────────────────────────────────────────────

def _active_clause(now: datetime):
    return or_(Subscription.period_end.is_(None), Subscription.period_end > now)


@admin_router.get("/overview")
async def billing_overview(db: AsyncSession = Depends(get_db), _=Depends(verify_admin_token)):
    """Subscribers per plan, revenue, and churn, for the Payments page.
    Sandbox (test) purchases are left out of every number."""
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last30 = now - timedelta(days=30)

    rows = (await db.execute(select(Subscription).where(
        _active_clause(now),
        or_(Subscription.environment.is_(None), Subscription.environment != "SANDBOX"),
    ))).scalars().all()
    paid = [r for r in rows if r.source == "revenuecat"]
    by_plan: dict[str, dict] = {}
    mrr = 0.0
    for r in paid:
        b = by_plan.setdefault(r.plan, {"monthly": 0, "yearly": 0, "total": 0})
        b[r.period or "monthly"] = b.get(r.period or "monthly", 0) + 1
        b["total"] += 1
        price = CATALOG_PRICES.get((r.plan, r.period or "monthly"), 0.0)
        mrr += price / 12 if r.period == "yearly" else price

    def _sum_since(since):
        return select(func.coalesce(func.sum(SubscriptionEvent.price_usd), 0)).where(
            SubscriptionEvent.type.in_(_REVENUE_EVENTS),
            SubscriptionEvent.environment == "PRODUCTION",
            SubscriptionEvent.event_at >= since,
        )

    revenue_month = float((await db.execute(_sum_since(month_start))).scalar() or 0)
    revenue_30d = float((await db.execute(_sum_since(last30))).scalar() or 0)
    revenue_all = float((await db.execute(_sum_since(datetime(2000, 1, 1, tzinfo=timezone.utc)))).scalar() or 0)

    async def _count(types, since):
        return int((await db.execute(select(func.count()).select_from(SubscriptionEvent).where(
            SubscriptionEvent.type.in_(types),
            SubscriptionEvent.environment == "PRODUCTION",
            SubscriptionEvent.event_at >= since,
        ))).scalar() or 0)

    return {
        "enforcing": await plan_service.is_enforcing(),
        "subscribers": len(paid),
        "admin_grants": len([r for r in rows if r.source == "admin"]),
        "by_plan": by_plan,
        "mrr_usd": round(mrr, 2),
        "revenue_month_usd": round(revenue_month, 2),
        "revenue_30d_usd": round(revenue_30d, 2),
        "revenue_all_usd": round(revenue_all, 2),
        "new_30d": await _count(("INITIAL_PURCHASE",), last30),
        "renewals_30d": await _count(("RENEWAL",), last30),
        "cancellations_30d": await _count(("CANCELLATION",), last30),
        "expirations_30d": await _count(("EXPIRATION",), last30),
        "billing_issues_30d": await _count(("BILLING_ISSUE",), last30),
        "note": "Revenue is what the stores charged (USD, before their ~15% fee and taxes).",
    }


@admin_router.get("/subscriptions")
async def list_subscriptions(
    status: str = Query("active", description="active | ended | all"),
    plan: Optional[str] = Query(None),
    search: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    now = datetime.now(timezone.utc)
    q = select(Subscription, User).join(User, User.id == Subscription.user_id)
    if status == "active":
        q = q.where(_active_clause(now))
    elif status == "ended":
        q = q.where(Subscription.period_end.is_not(None), Subscription.period_end <= now)
    if plan:
        q = q.where(Subscription.plan == plan)
    if search:
        like = f"%{search.strip()}%"
        q = q.where(or_(User.email.ilike(like), User.display_name.ilike(like)))
    total = int((await db.execute(select(func.count()).select_from(q.subquery()))).scalar() or 0)
    rows = (await db.execute(
        q.order_by(Subscription.updated_at.desc()).offset((page - 1) * page_size).limit(page_size)
    )).all()
    return {
        "total": total,
        "items": [{
            "user_id": str(u.id), "email": u.email, "name": u.display_name,
            "source": s.source, "plan": s.plan, "period": s.period, "store": s.store,
            "status": s.status, "environment": s.environment, "product_id": s.product_id,
            "period_start": s.period_start.isoformat() if s.period_start else None,
            "period_end": s.period_end.isoformat() if s.period_end else None,
            "auto_renew": s.auto_renew, "note": s.note, "granted_by": s.granted_by,
            "updated_at": s.updated_at.isoformat() if s.updated_at else None,
        } for s, u in rows],
    }


@admin_router.get("/events")
async def list_events(
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    rows = (await db.execute(
        select(SubscriptionEvent, User.email)
        .join(User, User.id == SubscriptionEvent.user_id, isouter=True)
        .order_by(SubscriptionEvent.created_at.desc()).limit(limit)
    )).all()
    return [{
        "event_id": e.event_id, "type": e.type, "email": email, "product_id": e.product_id,
        "store": e.store, "environment": e.environment,
        "price_usd": float(e.price_usd) if e.price_usd is not None else None,
        "currency": e.currency,
        "price_local": float(e.price_local) if e.price_local is not None else None,
        "event_at": e.event_at.isoformat() if e.event_at else None,
    } for e, email in rows]


class GrantRequest(BaseModel):
    email: str = Field(..., max_length=255)
    plan: str = Field(..., pattern="^(voyager|globetrotter)$")
    days: Optional[int] = Field(None, ge=1, le=3650, description="Empty = no end date")
    note: Optional[str] = Field(None, max_length=255)


@admin_router.post("/grant")
async def grant_plan(
    data: GrantRequest,
    db: AsyncSession = Depends(get_db),
    admin: str = Depends(require_admin),
):
    """Give a user a plan by hand (testers, support, goodwill). A store
    subscription is never touched; the better of the two applies."""
    user = (await db.execute(select(User).where(
        func.lower(User.email) == data.email.strip().lower()
    ))).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="No user with that email")
    now = datetime.now(timezone.utc)
    row = (await db.execute(select(Subscription).where(
        Subscription.user_id == user.id, Subscription.source == "admin",
    ))).scalar_one_or_none()
    values = dict(
        plan=data.plan, period=None, store="admin", status="active",
        period_start=now, period_end=(now + timedelta(days=data.days)) if data.days else None,
        auto_renew=False, environment=None, note=data.note, granted_by=admin,
    )
    if row is None:
        db.add(Subscription(user_id=user.id, source="admin", **values))
    else:
        for k, v in values.items():
            setattr(row, k, v)
    await db.commit()
    await plan_service.invalidate(user.id)
    return {"ok": True, "user_id": str(user.id), **{k: (v.isoformat() if isinstance(v, datetime) else v)
                                                    for k, v in values.items()}}


@admin_router.delete("/grant/{user_id}")
async def revoke_grant(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    row = (await db.execute(select(Subscription).where(
        Subscription.user_id == user_id, Subscription.source == "admin",
    ))).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="No admin grant for this user")
    await db.delete(row)
    await db.commit()
    await plan_service.invalidate(user_id)
    return {"ok": True}


class PlanSettings(BaseModel):
    plans_enforce: bool = False
    plans_enforce_users: str = ""
    plan_limits: dict[str, dict[str, Any]] = {}
    min_app_version: str = ""
    revenuecat_webhook_secret_set: bool = False
    revenuecat_api_key_set: bool = False
    revenuecat_ios_key: str = ""
    revenuecat_android_key: str = ""
    # Free map data for free users: off | test | on, and the oldest app build
    # that gets it (older builds show "0.0" for places without ratings).
    free_data_layer: str = "off"
    free_data_min_app_version: str = ""


class PlanSettingsUpdate(BaseModel):
    plans_enforce: Optional[bool] = None
    plans_enforce_users: Optional[str] = Field(None, max_length=2000)
    plan_limits: Optional[dict[str, dict[str, Any]]] = None
    min_app_version: Optional[str] = Field(None, max_length=20, pattern=r"^(\d+(\.\d+){0,3})?$")
    revenuecat_webhook_secret: Optional[str] = Field(None, max_length=200)
    revenuecat_api_key: Optional[str] = Field(None, max_length=200)
    revenuecat_ios_key: Optional[str] = Field(None, max_length=200)
    revenuecat_android_key: Optional[str] = Field(None, max_length=200)
    free_data_layer: Optional[str] = Field(None, pattern=r"^(off|test|on)$")
    free_data_min_app_version: Optional[str] = Field(None, max_length=20, pattern=r"^(\d+(\.\d+){0,3})?$")


async def _read_settings(svc: SettingsService) -> PlanSettings:
    cfg = await plan_service.refresh_config()
    return PlanSettings(
        plans_enforce=cfg["enforce"],
        plans_enforce_users=await svc.get_setting_fresh(plan_service.K_ENFORCE_USERS, ""),
        plan_limits=cfg["limits"],
        min_app_version=cfg["min_app_version"],
        revenuecat_webhook_secret_set=bool((await svc.get_setting_fresh(K_WEBHOOK_SECRET, "")).strip()),
        revenuecat_api_key_set=bool((await svc.get_setting_fresh(K_API_KEY, "")).strip()),
        revenuecat_ios_key=await svc.get_setting_fresh(K_IOS_KEY, ""),
        revenuecat_android_key=await svc.get_setting_fresh(K_ANDROID_KEY, ""),
        free_data_layer=cfg.get("free_data", "off"),
        free_data_min_app_version=cfg.get("free_data_min_version", ""),
    )


@admin_router.get("/settings", response_model=PlanSettings)
async def get_plan_settings(db: AsyncSession = Depends(get_db), _=Depends(verify_admin_token)):
    return await _read_settings(SettingsService(db))


@admin_router.put("/settings", response_model=PlanSettings)
async def update_plan_settings(
    data: PlanSettingsUpdate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    # Which settings changed, never the secrets' values.
    request.state.audit_detail = {
        "fields": sorted(k for k, v in data.model_dump().items() if v is not None)
    }
    svc = SettingsService(db)
    if data.plans_enforce is not None:
        await svc.set_setting(plan_service.K_ENFORCE, "true" if data.plans_enforce else "false",
                              "Subscription plan limits switched on for everyone")
    if data.plans_enforce_users is not None:
        await svc.set_setting(plan_service.K_ENFORCE_USERS, data.plans_enforce_users.strip(),
                              "Emails that get plan limits before they are on for everyone")
    if data.plan_limits is not None:
        await svc.set_setting(plan_service.K_LIMITS, plan_service.overrides_json(data.plan_limits),
                              "Per-plan limits (JSON over the defaults)")
    if data.min_app_version is not None:
        await svc.set_setting(plan_service.K_MIN_APP_VERSION, data.min_app_version.strip(),
                              "Oldest app version allowed; older builds are asked to update")
    if data.free_data_layer is not None:
        await svc.set_setting(plan_service.K_FREE_DATA, data.free_data_layer,
                              "Free map data for free users: off / test / on")
    if data.free_data_min_app_version is not None:
        await svc.set_setting(plan_service.K_FREE_DATA_MIN_VERSION,
                              data.free_data_min_app_version.strip(),
                              "Oldest app build that gets free map data")
    if data.revenuecat_webhook_secret is not None:
        await svc.set_setting(K_WEBHOOK_SECRET, data.revenuecat_webhook_secret.strip(),
                              "RevenueCat webhook Authorization header value")
    if data.revenuecat_api_key is not None:
        await svc.set_setting(K_API_KEY, data.revenuecat_api_key.strip(),
                              "RevenueCat secret API key (v1)")
    if data.revenuecat_ios_key is not None:
        await svc.set_setting(K_IOS_KEY, data.revenuecat_ios_key.strip(),
                              "RevenueCat public App Store SDK key (appl_…)")
    if data.revenuecat_android_key is not None:
        await svc.set_setting(K_ANDROID_KEY, data.revenuecat_android_key.strip(),
                              "RevenueCat public Google Play SDK key (goog_…)")
    return await _read_settings(svc)


@admin_router.get("/free-data")
async def free_data_status(db: AsyncSession = Depends(get_db), _=Depends(verify_admin_token)):
    """Where the free map data stands: areas, places, size, Geoapify use."""
    from sqlalchemy import text as _text
    from app.services.open_data import geoapify_places

    areas = {r[0]: int(r[1]) for r in (await db.execute(_text(
        "SELECT status, count(*) FROM open_areas GROUP BY status"
    ))).all()}
    places = int((await db.execute(_text("SELECT count(*) FROM open_places"))).scalar() or 0)
    size = int((await db.execute(_text("SELECT pg_total_relation_size('open_places')"))).scalar() or 0)
    by_section = {r[0]: int(r[1]) for r in (await db.execute(_text(
        "SELECT section, count(*) FROM open_places GROUP BY section"
    ))).all()}
    recent = [
        {"tile": r[0], "status": r[1], "places": int(r[2] or 0), "seconds": r[3],
         "error": r[4], "at": (r[5] or r[6]).isoformat() if (r[5] or r[6]) else None}
        for r in (await db.execute(_text(
            "SELECT tile, status, places_count, seconds, error, imported_at, requested_at "
            "FROM open_areas ORDER BY coalesce(imported_at, requested_at) DESC LIMIT 8"
        ))).all()
    ]
    return {
        "mode": await plan_service.free_data_mode(),
        "areas": {k: areas.get(k, 0) for k in ("queued", "importing", "done", "failed")},
        "places": places,
        "by_section": by_section,
        "size_mb": round(size / 1024 ** 2, 1),
        "geoapify_credits_today": await geoapify_places.credits_used_today(),
        "geoapify_daily_cap": geoapify_places.GEOAPIFY_DAILY_CAP,
        "recent": recent,
    }


async def plans_for_users(db: AsyncSession, user_ids: list) -> dict:
    """{user_id: plan} for the admin Users list (Explorer users are left out)."""
    if not user_ids:
        return {}
    rows = (await db.execute(select(Subscription).where(
        Subscription.user_id.in_(user_ids)
    ))).scalars().all()
    grouped: dict = {}
    for r in rows:
        grouped.setdefault(r.user_id, []).append(r)
    out = {}
    for uid, subs in grouped.items():
        info = plan_service.best_plan(subs)
        if info.plan != plan_service.EXPLORER:
            out[uid] = {"plan": info.plan, "source": info.source,
                        "period_end": info.period_end.isoformat() if info.period_end else None}
    return out
