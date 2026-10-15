"""Schemas for the audit trail and the device-session lists.

The partner variants are separate classes, not the admin ones with fields
hidden: a vendor sees their own sign-ins and changes, never the raw
User-Agent, request ids or the route templates of the admin API.
"""
import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class AuditEventOut(BaseModel):
    id: uuid.UUID
    occurred_at: datetime
    actor_type: str
    actor_id: Optional[str] = None
    actor_label: Optional[str] = None
    vendor_id: Optional[uuid.UUID] = None
    vendor_name: Optional[str] = None
    session_id: Optional[uuid.UUID] = None
    category: str
    action: str
    summary: str
    method: Optional[str] = None
    route: Optional[str] = None
    path: Optional[str] = None
    target_id: Optional[str] = None
    status_code: Optional[int] = None
    success: bool
    ip: Optional[str] = None
    browser: Optional[str] = None
    os: Optional[str] = None
    device_type: Optional[str] = None
    detail: Optional[dict] = None


class AuditStats(BaseModel):
    events_24h: int
    failed_sign_ins_24h: int
    changes_24h: int
    active_sessions: int


class AuditListResponse(BaseModel):
    items: List[AuditEventOut]
    total: int
    page: int
    page_size: int
    stats: Optional[AuditStats] = None


class SessionOut(BaseModel):
    id: uuid.UUID
    actor_type: str
    actor_label: str
    vendor_id: Optional[uuid.UUID] = None
    vendor_name: Optional[str] = None
    ip: Optional[str] = None
    last_ip: Optional[str] = None
    browser: Optional[str] = None
    os: Optional[str] = None
    device_type: Optional[str] = None
    created_at: datetime
    last_seen_at: datetime
    expires_at: datetime
    # "active", "ended" (token ran out) or "revoked".
    status: str
    revoked_at: Optional[datetime] = None
    revoked_reason: Optional[str] = None
    revoked_by: Optional[str] = None
    is_current: bool = False


class SessionListResponse(BaseModel):
    items: List[SessionOut]
    total: int
    page: int
    page_size: int


class PartnerAuditEventOut(BaseModel):
    id: uuid.UUID
    occurred_at: datetime
    actor_label: Optional[str] = None
    # True when the row belongs to the viewer's own login.
    is_you: bool = False
    category: str
    summary: str
    success: bool
    ip: Optional[str] = None
    browser: Optional[str] = None
    os: Optional[str] = None
    device_type: Optional[str] = None


class PartnerAuditListResponse(BaseModel):
    items: List[PartnerAuditEventOut]
    total: int
    page: int
    page_size: int


class PartnerSessionOut(BaseModel):
    id: uuid.UUID
    actor_label: str
    is_you: bool
    ip: Optional[str] = None
    last_ip: Optional[str] = None
    browser: Optional[str] = None
    os: Optional[str] = None
    device_type: Optional[str] = None
    created_at: datetime
    last_seen_at: datetime
    status: str
    is_current: bool = False


class PartnerSessionListResponse(BaseModel):
    items: List[PartnerSessionOut]
