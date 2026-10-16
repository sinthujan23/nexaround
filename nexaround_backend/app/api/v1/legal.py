"""Legal documents for Experiences: the booking terms and the provider agreement.

Three audiences, three routers:

* `/legal/{kind}`, public: the app's terms page and the website. Signed-in
  travellers also learn whether they have accepted the current version.
* `/partner/agreement`: the portal's gate, and accepting it.
* `/admin/legal`: editing documents and seeing who has accepted what.
"""

import uuid
from datetime import datetime, time, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import VendorPrincipal, get_current_user_optional, get_current_vendor
from app.api.v1.admin import require_admin
from app.core.database import get_db
from app.models.experience import ExperienceVendor
from app.models.user import User
from app.schemas.legal import (
    CustomerTermsOut, LegalDocumentAdminOut, LegalDocumentOut, LegalDocumentSave,
    LegalVersionSummary, OfflineAcceptanceCreate, PartnerAgreementAccept,
    PartnerAgreementOut, VendorAgreementListResponse, VendorAgreementStatus,
)
from app.services import audit, legal_service

router = APIRouter(prefix="/legal", tags=["Legal"])
partner_router = APIRouter(prefix="/partner/agreement", tags=["Partner Portal"])
admin_router = APIRouter(prefix="/admin/legal", tags=["Admin Legal"])


def _kind_or_404(kind: str) -> str:
    if kind not in legal_service.KINDS:
        raise HTTPException(status_code=404, detail="Document not found")
    return kind


# ── Public ──────────────────────────────────────────────────────────────────

@router.get("/{kind}", response_model=CustomerTermsOut)
async def get_document(
    kind: str,
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    document = await legal_service.get_current(db, _kind_or_404(kind))
    accepted = False
    if current_user and kind == legal_service.CUSTOMER:
        accepted = await legal_service.user_has_accepted(
            db, current_user.id, document.version
        )
    return CustomerTermsOut(
        **LegalDocumentOut.model_validate(document).model_dump(), accepted=accepted
    )


# ── Partner portal ──────────────────────────────────────────────────────────

async def _agreement_status(
    db: AsyncSession, principal: VendorPrincipal
) -> PartnerAgreementOut:
    document = await legal_service.get_current(db, legal_service.PROVIDER)
    latest = await legal_service.latest_vendor_acceptance(db, principal.vendor.id)
    accepted_version = latest.version if latest else None
    return PartnerAgreementOut(
        document=LegalDocumentOut.model_validate(document),
        accepted_version=accepted_version,
        accepted_at=latest.accepted_at if latest else None,
        required=accepted_version is None or accepted_version < document.version,
        grace_ends_at=legal_service.provider_grace_ends(document.published_at),
        listed=legal_service.vendor_is_listed(
            accepted_version, document.version, document.published_at,
            datetime.now(timezone.utc),
        ),
    )


@partner_router.get("", response_model=PartnerAgreementOut)
async def partner_agreement(
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    return await _agreement_status(db, principal)


@partner_router.post("/accept", response_model=PartnerAgreementOut)
async def accept_partner_agreement(
    data: PartnerAgreementAccept,
    request: Request,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    document = await legal_service.get_current(db, legal_service.PROVIDER)
    if data.version != document.version:
        # Published while the vendor was reading: they must see the new text.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The agreement was updated while you were reading it. "
                   "Please review the new version.",
        )
    legal_service.record_acceptance(
        db,
        kind=legal_service.PROVIDER,
        version=document.version,
        method="portal",
        meta=audit.client_meta(request),
        vendor_id=principal.vendor.id,
        vendor_user_id=principal.login.id,
        party_label=f"{principal.vendor.name} ({principal.login.email})",
    )
    await db.commit()
    return await _agreement_status(db, principal)


# ── Admin ───────────────────────────────────────────────────────────────────

async def _admin_document(db: AsyncSession, kind: str) -> LegalDocumentAdminOut:
    document = await legal_service.get_current(db, kind)
    versions = await legal_service.list_versions(db, kind)
    return LegalDocumentAdminOut(
        **LegalDocumentOut.model_validate(document).model_dump(),
        updated_by=document.updated_by,
        versions=[LegalVersionSummary.model_validate(v) for v in versions],
    )


@admin_router.get("", response_model=list[LegalDocumentAdminOut])
async def admin_list_documents(
    db: AsyncSession = Depends(get_db),
    _admin: str = Depends(require_admin),
):
    return [await _admin_document(db, kind) for kind in legal_service.KINDS]


@admin_router.put("/{kind}", response_model=LegalDocumentAdminOut)
async def admin_save_document(
    kind: str,
    data: LegalDocumentSave,
    db: AsyncSession = Depends(get_db),
    admin: str = Depends(require_admin),
):
    await legal_service.save_document(
        db, _kind_or_404(kind),
        title=data.title.strip(),
        body=data.body.strip(),
        highlights=data.highlights,
        new_version=data.new_version,
        admin=admin,
    )
    return await _admin_document(db, kind)


@admin_router.get("/vendors", response_model=VendorAgreementListResponse)
async def admin_vendor_agreements(
    db: AsyncSession = Depends(get_db),
    _admin: str = Depends(require_admin),
):
    document = await legal_service.get_current(db, legal_service.PROVIDER)
    best = await legal_service.latest_acceptance_by_vendor(db)
    vendors = (
        await db.execute(select(ExperienceVendor).order_by(ExperienceVendor.name))
    ).scalars().all()
    now = datetime.now(timezone.utc)

    rows = []
    for vendor in vendors:
        accepted = best.get(vendor.id)
        version = accepted.version if accepted else None
        rows.append(VendorAgreementStatus(
            vendor_id=vendor.id,
            vendor_name=vendor.name,
            vendor_is_active=bool(vendor.is_active),
            accepted_version=version,
            accepted_at=accepted.accepted_at if accepted else None,
            method=accepted.method if accepted else None,
            accepted_by=(
                (accepted.recorded_by if accepted.method == "offline" else accepted.party_label)
                if accepted else None
            ),
            note=accepted.note if accepted else None,
            is_current=version is not None and version >= document.version,
            listed=legal_service.vendor_is_listed(
                version, document.version, document.published_at, now
            ),
        ))
    return VendorAgreementListResponse(
        current_version=document.version,
        published_at=document.published_at,
        grace_ends_at=legal_service.provider_grace_ends(document.published_at),
        vendors=rows,
    )


@admin_router.post(
    "/vendors/{vendor_id}/offline-acceptance",
    response_model=VendorAgreementListResponse,
)
async def admin_record_offline_acceptance(
    vendor_id: uuid.UUID,
    data: OfflineAcceptanceCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    admin: str = Depends(require_admin),
):
    """For a vendor who signed on paper, or who has no portal login."""
    vendor = await db.get(ExperienceVendor, vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")
    document = await legal_service.get_current(db, legal_service.PROVIDER)
    legal_service.record_acceptance(
        db,
        kind=legal_service.PROVIDER,
        version=document.version,
        method="offline",
        meta=audit.client_meta(request),
        accepted_at=datetime.combine(data.accepted_on, time(12, 0), tzinfo=timezone.utc),
        vendor_id=vendor.id,
        party_label=vendor.name,
        recorded_by=admin,
        note=data.note.strip(),
    )
    await db.commit()
    return await admin_vendor_agreements(db=db, _admin=admin)
