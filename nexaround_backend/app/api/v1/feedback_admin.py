"""Admin panel: the Feedback page (messages, quick ratings, quarterly survey).

For the admin and team members given the "feedback" area. Every change is a
POST/PATCH/DELETE under /admin, so the audit middleware records who did it.
"""
import uuid
from datetime import datetime
from typing import List, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import PanelUser, allow_team
from app.core.database import get_db
from app.models.feedback import Feedback, SurveyRound
from app.models.user import User
from app.services import feedback_service as fb
from app.services.creator_auth import FEEDBACK

router = APIRouter(prefix="/admin", tags=["Admin Feedback"])

allow_feedback = allow_team(FEEDBACK)

PAGE_SIZE = 40


def _row(f: Feedback, u: Optional[User]) -> dict:
    return {
        "id": str(f.id), "kind": f.kind, "type": f.type, "status": f.status,
        "text": f.text, "reasons": f.reasons or [], "screenshots": len(f.screenshots or []),
        "can_reply": f.can_reply, "feature": f.feature, "ref_id": f.ref_id, "ref_label": f.ref_label,
        "source_screen": f.source_screen, "app_version": f.app_version, "platform": f.platform,
        "os_version": f.os_version, "country": f.country, "replies": f.replies or [],
        "created_at": f.created_at.isoformat(),
        "explorer": {
            "id": str(u.id), "name": u.display_name, "email": u.email,
            "avatar_url": getattr(u, "avatar_url", None),
            "joined": u.created_at.isoformat() if u.created_at else None,
        } if u else None,
    }


async def _get(db: AsyncSession, feedback_id: uuid.UUID) -> Feedback:
    item = await db.get(Feedback, feedback_id)
    if not item:
        raise HTTPException(status_code=404, detail="This feedback no longer exists.")
    return item


# ── Messages and quick ratings ─────────────────────────────────────────────

@router.get("/feedback/counts")
async def counts(_: PanelUser = Depends(allow_feedback), db: AsyncSession = Depends(get_db)):
    """New items, for the sidebar badge and the tab."""
    rows = (await db.execute(
        select(Feedback.kind, func.count(Feedback.id)).where(Feedback.status == "new").group_by(Feedback.kind)
    )).all()
    by_kind = {k: c for k, c in rows}
    return {"new": sum(by_kind.values()), "new_messages": by_kind.get("message", 0),
            "new_quick": by_kind.get("quick", 0)}


@router.get("/feedback")
async def list_feedback(
    filter: Literal["all", "suggestion", "improvement", "problem", "love", "other", "quick", "new"] = "all",
    q: str = Query("", max_length=200),
    page: int = Query(1, ge=1, le=500),
    _: PanelUser = Depends(allow_feedback),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Feedback, User).join(User, User.id == Feedback.user_id, isouter=True)
    if filter == "quick":
        stmt = stmt.where(Feedback.kind == "quick")
    elif filter == "new":
        stmt = stmt.where(Feedback.status == "new")
    elif filter != "all":
        stmt = stmt.where(Feedback.kind == "message", Feedback.type == filter)
    else:
        # "All" leaves out plain "good" quick taps: they need no reading and
        # would bury the messages. They still count on the Survey results tab.
        stmt = stmt.where(or_(Feedback.kind == "message", Feedback.type == "bad"))
    q = q.strip()
    if q:
        like = f"%{q}%"
        stmt = stmt.where(or_(Feedback.text.ilike(like), Feedback.ref_label.ilike(like),
                              User.display_name.ilike(like), User.email.ilike(like)))
    total = (await db.execute(select(func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(
        stmt.order_by(Feedback.created_at.desc()).offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
    )).all()
    return {"items": [_row(f, u) for f, u in rows], "total": total, "page": page,
            "has_more": page * PAGE_SIZE < total}


@router.get("/feedback/{feedback_id}")
async def get_feedback(feedback_id: uuid.UUID, _: PanelUser = Depends(allow_feedback),
                       db: AsyncSession = Depends(get_db)):
    """One item. Opening a new one marks it seen."""
    item = await _get(db, feedback_id)
    if item.status == "new":
        item.status = "seen"
        await db.commit()
        await db.refresh(item)
    user = await db.get(User, item.user_id)
    return _row(item, user)


@router.get("/feedback/{feedback_id}/screenshots/{index}")
async def screenshot(feedback_id: uuid.UUID, index: int, _: PanelUser = Depends(allow_feedback),
                     db: AsyncSession = Depends(get_db)):
    item = await _get(db, feedback_id)
    names = item.screenshots or []
    if not 0 <= index < len(names):
        raise HTTPException(status_code=404, detail="No such picture.")
    path = fb.screenshot_path(item.user_id, names[index])
    if not path:
        raise HTTPException(status_code=404, detail="The picture is no longer stored.")
    return FileResponse(path, media_type="image/webp",
                        headers={"Cache-Control": "private, max-age=3600", "X-Content-Type-Options": "nosniff"})


class StatusIn(BaseModel):
    status: Literal["new", "seen", "planned", "done", "replied", "closed"]


@router.post("/feedback/{feedback_id}/status")
async def set_status(feedback_id: uuid.UUID, body: StatusIn, request: Request,
                     _: PanelUser = Depends(allow_feedback), db: AsyncSession = Depends(get_db)):
    item = await _get(db, feedback_id)
    request.state.audit_detail = {"feedback_id": str(item.id), "from": item.status, "to": body.status}
    item.status = body.status
    await db.commit()
    return {"ok": True, "status": item.status}


class ReplyIn(BaseModel):
    text: str = Field(min_length=2, max_length=4000)


@router.post("/feedback/{feedback_id}/reply")
async def reply(feedback_id: uuid.UUID, body: ReplyIn, request: Request,
                user: PanelUser = Depends(allow_feedback), db: AsyncSession = Depends(get_db)):
    """Bell + push in the app and an email from support@."""
    item = await _get(db, feedback_id)
    request.state.audit_detail = {"feedback_id": str(item.id), "sent_by": user.name}
    sent = await fb.reply(db, item, body.text, user.name)
    await db.refresh(item)
    explorer = await db.get(User, item.user_id)
    return {"sent": sent, "item": _row(item, explorer)}


# ── Survey rounds ──────────────────────────────────────────────────────────

class OptionIn(BaseModel):
    key: Optional[str] = Field(default=None, max_length=40)
    label: str = Field(max_length=60)
    icon: Optional[str] = Field(default=None, max_length=40)


class RoundIn(BaseModel):
    name: str = Field(min_length=2, max_length=60)
    starts_at: datetime
    ends_at: datetime
    build_next_options: List[OptionIn] = Field(default_factory=list, max_length=15)


class RoundPatch(BaseModel):
    name: Optional[str] = Field(default=None, min_length=2, max_length=60)
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    is_open: Optional[bool] = None
    build_next_options: Optional[List[OptionIn]] = Field(default=None, max_length=15)


def _check_dates(start: datetime, end: datetime) -> None:
    if start.tzinfo is None or end.tzinfo is None:
        raise HTTPException(status_code=400, detail="Dates need a time zone.")
    if end <= start:
        raise HTTPException(status_code=400, detail="The end must be after the start.")


@router.get("/survey/rounds")
async def rounds(_: PanelUser = Depends(allow_feedback), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(SurveyRound).order_by(SurveyRound.starts_at.desc()))).scalars().all()
    return {
        "rounds": [fb.round_admin(r, await fb.response_count(db, r.id)) for r in rows],
        "option_icons": list(fb.OPTION_ICONS),
    }


@router.post("/survey/rounds")
async def create_round(body: RoundIn, request: Request, _: PanelUser = Depends(allow_feedback),
                       db: AsyncSession = Depends(get_db)):
    _check_dates(body.starts_at, body.ends_at)
    r = SurveyRound(
        name=body.name.strip(), starts_at=body.starts_at, ends_at=body.ends_at, is_open=False,
        build_next_options=fb.normalise_options([o.model_dump() for o in body.build_next_options], [], False),
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    request.state.audit_detail = {"round": r.name}
    return fb.round_admin(r, 0)


@router.patch("/survey/rounds/{round_id}")
async def update_round(round_id: uuid.UUID, body: RoundPatch, request: Request,
                       _: PanelUser = Depends(allow_feedback), db: AsyncSession = Depends(get_db)):
    r = await db.get(SurveyRound, round_id)
    if not r:
        raise HTTPException(status_code=404, detail="Survey not found.")
    answers = await fb.response_count(db, r.id)
    if body.name is not None:
        r.name = body.name.strip()
    start = body.starts_at or r.starts_at
    end = body.ends_at or r.ends_at
    if body.starts_at or body.ends_at:
        _check_dates(start, end)
        r.starts_at, r.ends_at = start, end
    if body.build_next_options is not None:
        r.build_next_options = fb.normalise_options(
            [o.model_dump() for o in body.build_next_options], r.build_next_options or [], answers > 0)
    if body.is_open is not None:
        if body.is_open:
            if not r.build_next_options:
                raise HTTPException(status_code=400, detail='Add the "What should we build next?" options first.')
            await fb.close_other_rounds(db, r.id)
        r.is_open = body.is_open
    request.state.audit_detail = {"round": r.name, "changes": body.model_dump(exclude_none=True, mode="json")}
    await db.commit()
    await db.refresh(r)
    return fb.round_admin(r, answers)


@router.delete("/survey/rounds/{round_id}")
async def delete_round(round_id: uuid.UUID, request: Request, _: PanelUser = Depends(allow_feedback),
                       db: AsyncSession = Depends(get_db)):
    r = await db.get(SurveyRound, round_id)
    if not r:
        raise HTTPException(status_code=404, detail="Survey not found.")
    if await fb.response_count(db, r.id):
        raise HTTPException(status_code=400, detail="This survey has answers, so it can't be deleted. Close it instead.")
    request.state.audit_detail = {"round": r.name}
    await db.delete(r)
    await db.commit()
    return {"ok": True}


@router.get("/survey/rounds/{round_id}/results")
async def round_results(round_id: uuid.UUID, _: PanelUser = Depends(allow_feedback),
                        db: AsyncSession = Depends(get_db)):
    return await fb.results(db, round_id)
