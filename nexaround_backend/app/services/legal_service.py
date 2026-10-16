"""The rules around the Experience Booking Terms and the Provider Agreement.

Two grace periods, both measured from a publish date so they restart with
every new version and need no admin to remember them:

* **Providers** get `PROVIDER_GRACE` to accept a new Provider Agreement. After
  that, the experiences of a vendor who has not accepted it are hidden from the
  app (not deleted, and back as soon as they accept).
* **Older apps**, which cannot show the terms, may keep sending requests for
  `APP_UPGRADE_GRACE` after the booking terms first went live. Those requests
  are stored with no terms version, so they are not mistaken for accepted ones.
"""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import async_session
from app.models.experience import ExperienceVendor
from app.models.legal import LegalAcceptance, LegalDocument
from app.services import legal_texts

CUSTOMER = "experience_customer"
PROVIDER = "experience_provider"
KINDS = (CUSTOMER, PROVIDER)

PROVIDER_GRACE = timedelta(days=14)
APP_UPGRADE_GRACE = timedelta(days=30)

# HTTP statuses the app keys on. 409: the terms changed under the traveller,
# so show them again. 426: an app too old to show terms at all.
TERMS_CHANGED = 409
APP_TOO_OLD = 426

_DEFAULTS = {
    CUSTOMER: (
        legal_texts.CUSTOMER_TITLE,
        legal_texts.CUSTOMER_BODY,
        legal_texts.CUSTOMER_HIGHLIGHTS,
    ),
    PROVIDER: (
        legal_texts.PROVIDER_TITLE,
        legal_texts.PROVIDER_BODY,
        legal_texts.PROVIDER_HIGHLIGHTS,
    ),
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ── Pure rules ──────────────────────────────────────────────────────────────

def provider_grace_ends(published_at: datetime) -> datetime:
    return published_at + PROVIDER_GRACE


def vendor_is_listed(
    accepted_version: Optional[int],
    current_version: int,
    published_at: datetime,
    now: datetime,
) -> bool:
    """Whether a vendor's experiences may appear in the app.

    Accepting the current version, or any later one, always lists them.
    Otherwise they stay listed only until the current version's grace ends,
    which is also what keeps every vendor listed on the day this ships.
    """
    if accepted_version is not None and accepted_version >= current_version:
        return True
    return now < provider_grace_ends(published_at)


def customer_terms_error(
    sent_version: Optional[int],
    current_version: int,
    first_published_at: datetime,
    now: datetime,
) -> Optional[tuple[int, str]]:
    """None if a request may be sent with `sent_version`, else (status, message).

    The messages are shown to the traveller verbatim by the app.
    """
    if sent_version is None:
        if now < first_published_at + APP_UPGRADE_GRACE:
            return None
        return (
            APP_TOO_OLD,
            "Please update the Nexaround app to send requests.",
        )
    if sent_version != current_version:
        return (
            TERMS_CHANGED,
            "The Experience Booking Terms have been updated. "
            "Please review and accept them to continue.",
        )
    return None


# ── Documents ───────────────────────────────────────────────────────────────

async def _latest(db: AsyncSession, kind: str) -> Optional[LegalDocument]:
    query = (
        select(LegalDocument)
        .where(LegalDocument.kind == kind)
        .order_by(LegalDocument.version.desc())
        .limit(1)
    )
    return (await db.execute(query)).scalar_one_or_none()


async def _seed(kind: str) -> None:
    """Write version 1 from legal_texts, in its own session.

    Its own session so a failed insert cannot roll back the caller's work. Two
    workers seeding at once collide on (kind, version); the loser's insert is
    simply dropped and it reads the winner's row.
    """
    title, body, highlights = _DEFAULTS[kind]
    now = _utcnow()
    try:
        async with async_session() as session:
            session.add(LegalDocument(
                kind=kind, version=1, title=title, body=body,
                highlights=list(highlights), published_at=now, updated_at=now,
                updated_by="system",
            ))
            await session.commit()
    except IntegrityError:
        pass


async def get_current(db: AsyncSession, kind: str) -> LegalDocument:
    """The current version of a document, writing version 1 if there is none."""
    document = await _latest(db, kind)
    if document is None:
        await _seed(kind)
        document = await _latest(db, kind)
    return document


async def first_published_at(db: AsyncSession, kind: str) -> datetime:
    value = (
        await db.execute(
            select(func.min(LegalDocument.published_at)).where(LegalDocument.kind == kind)
        )
    ).scalar()
    return value or _utcnow()


async def list_versions(db: AsyncSession, kind: str) -> list[LegalDocument]:
    query = (
        select(LegalDocument)
        .where(LegalDocument.kind == kind)
        .order_by(LegalDocument.version.desc())
    )
    return list((await db.execute(query)).scalars().all())


async def save_document(
    db: AsyncSession,
    kind: str,
    *,
    title: str,
    body: str,
    highlights: list[str],
    new_version: bool,
    admin: str,
) -> LegalDocument:
    """Publish a new version, or correct the current one in place.

    In-place saves are for typos only: whoever accepted the current version
    accepted the old wording, so a change of meaning must be a new version.
    """
    current = await get_current(db, kind)
    now = _utcnow()
    if new_version:
        document = LegalDocument(
            kind=kind, version=current.version + 1, title=title, body=body,
            highlights=highlights, published_at=now, updated_at=now,
            updated_by=admin,
        )
        db.add(document)
    else:
        current.title = title
        current.body = body
        current.highlights = highlights
        current.updated_at = now
        current.updated_by = admin
        document = current
    await db.commit()
    await db.refresh(document)
    return document


# ── Acceptances ─────────────────────────────────────────────────────────────

def record_acceptance(
    db: AsyncSession,
    *,
    kind: str,
    version: int,
    method: str,
    meta: Optional[dict] = None,
    accepted_at: Optional[datetime] = None,
    user_id: Optional[uuid.UUID] = None,
    enquiry_id: Optional[uuid.UUID] = None,
    vendor_id: Optional[uuid.UUID] = None,
    vendor_user_id: Optional[uuid.UUID] = None,
    party_label: Optional[str] = None,
    recorded_by: Optional[str] = None,
    note: Optional[str] = None,
) -> LegalAcceptance:
    """Add one acceptance row to the session; the caller commits."""
    meta = meta or {}
    row = LegalAcceptance(
        kind=kind, version=version, method=method,
        accepted_at=accepted_at or _utcnow(),
        user_id=user_id, enquiry_id=enquiry_id,
        vendor_id=vendor_id, vendor_user_id=vendor_user_id,
        party_label=(party_label or None) and party_label[:255],
        recorded_by=recorded_by, note=note,
        ip=(meta.get("ip") or None) and str(meta["ip"])[:64],
        user_agent=(meta.get("user_agent") or None) and meta["user_agent"][:512],
    )
    db.add(row)
    return row


async def user_has_accepted(db: AsyncSession, user_id: uuid.UUID, version: int) -> bool:
    query = select(func.count()).select_from(LegalAcceptance).where(
        LegalAcceptance.kind == CUSTOMER,
        LegalAcceptance.user_id == user_id,
        LegalAcceptance.version >= version,
    )
    return bool((await db.execute(query)).scalar())


async def latest_vendor_acceptance(
    db: AsyncSession, vendor_id: uuid.UUID
) -> Optional[LegalAcceptance]:
    """The vendor's acceptance of the highest version, most recent first."""
    query = (
        select(LegalAcceptance)
        .where(LegalAcceptance.kind == PROVIDER, LegalAcceptance.vendor_id == vendor_id)
        .order_by(LegalAcceptance.version.desc(), LegalAcceptance.accepted_at.desc())
        .limit(1)
    )
    return (await db.execute(query)).scalar_one_or_none()


async def latest_acceptance_by_vendor(db: AsyncSession) -> dict[uuid.UUID, LegalAcceptance]:
    """Every vendor's best Provider Agreement acceptance, for the admin list."""
    query = (
        select(LegalAcceptance)
        .where(LegalAcceptance.kind == PROVIDER, LegalAcceptance.vendor_id.isnot(None))
        .order_by(LegalAcceptance.version.desc(), LegalAcceptance.accepted_at.desc())
    )
    best: dict[uuid.UUID, LegalAcceptance] = {}
    for row in (await db.execute(query)).scalars().all():
        best.setdefault(row.vendor_id, row)
    return best


async def hidden_vendor_ids(
    db: AsyncSession, now: Optional[datetime] = None
) -> list[uuid.UUID]:
    """Vendors whose experiences the app must not show right now.

    Empty for the whole grace period, so a normal request costs one indexed
    read. After it, a plain id list rather than a join, so the nearest-first
    query keeps its single-table KNN plan (see ExperienceRepository).
    """
    document = await get_current(db, PROVIDER)
    if (now or _utcnow()) < provider_grace_ends(document.published_at):
        return []
    accepted = select(LegalAcceptance.vendor_id).where(
        LegalAcceptance.kind == PROVIDER,
        LegalAcceptance.version >= document.version,
        LegalAcceptance.vendor_id.isnot(None),
    )
    query = select(ExperienceVendor.id).where(ExperienceVendor.id.notin_(accepted))
    return list((await db.execute(query)).scalars().all())
