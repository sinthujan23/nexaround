"""Admin panel: the support@nexaround.com mailbox (Support inbox page).

For the admin and team members given the "support_inbox" area. Reads and
changes the Hostinger mailbox live; see app/services/support_mailbox.py.
Every send and move is a POST under /admin, so the audit middleware records
who did it; `audit_detail` adds the recipients and subject of each send.
"""
import asyncio
from typing import Literal, Optional
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import BaseModel, EmailStr, Field, field_validator

from app.api.v1.admin import PanelUser, allow_team
from app.services import support_mailbox as mailbox
from app.services.creator_auth import SUPPORT_INBOX

router = APIRouter(prefix="/admin/support-mail", tags=["Admin Support inbox"])

allow_support = allow_team(SUPPORT_INBOX)

Folder = Literal["inbox", "sent", "junk", "system", "trash"]
Show = Literal["all", "unread", "replied", "files"]


async def _run(fn, *args, **kwargs):
    try:
        return await asyncio.to_thread(fn, *args, **kwargs)
    except mailbox.NotFound as e:
        raise HTTPException(status_code=404, detail=str(e))
    except mailbox.MailboxError as e:
        # 502, never 401: the panel signs out on any 401.
        raise HTTPException(status_code=502, detail=str(e))


@router.get("/unread")
async def unread(_: PanelUser = Depends(allow_support)):
    """Unread mails in the Inbox, for the sidebar badge."""
    return {"unread": await _run(mailbox.unread_count)}


@router.get("/counts")
async def counts(_: PanelUser = Depends(allow_support)):
    """Mails and unread mails per folder, for the folder column."""
    return await _run(mailbox.folder_counts)


@router.get("/folders/{folder}")
async def list_folder(
    folder: Folder,
    page: int = Query(1, ge=1, le=1000),
    q: str = Query("", max_length=200),
    show: Show = "all",
    _: PanelUser = Depends(allow_support),
):
    return await _run(mailbox.list_messages, folder, page, q, show)


@router.get("/folders/{folder}/{uid}")
async def read(folder: Folder, uid: int, _: PanelUser = Depends(allow_support)):
    """One mail. Opening it marks it read, in webmail too."""
    return await _run(mailbox.read_message, folder, str(uid))


@router.get("/folders/{folder}/{uid}/attachments/{index}")
async def download(folder: Folder, uid: int, index: int, _: PanelUser = Depends(allow_support)):
    data, content_type, filename = await _run(mailbox.attachment, folder, str(uid), index)
    safe = filename.replace('"', "").replace("\r", "").replace("\n", "")
    return Response(
        content=data,
        media_type=content_type or "application/octet-stream",
        headers={
            "Content-Disposition": f"attachment; filename=\"{safe.encode('ascii', 'replace').decode()}\"; "
                                   f"filename*=UTF-8''{quote(filename)}",
            "X-Content-Type-Options": "nosniff",
        },
    )


class MoveRequest(BaseModel):
    to: Literal["trash", "inbox"]


@router.post("/folders/{folder}/{uid}/move")
async def move(
    folder: Folder, uid: int, body: MoveRequest, request: Request,
    _: PanelUser = Depends(allow_support),
):
    """Delete (to Trash), Not spam (Junk to Inbox) or back from Trash."""
    if (folder, body.to) not in mailbox.MOVES:
        raise HTTPException(status_code=400, detail="That move isn't allowed.")
    request.state.audit_detail = {"from_folder": folder, "to_folder": body.to, "uid": uid}
    await _run(mailbox.move, folder, str(uid), body.to)
    return {"ok": True}


class ReplyTo(BaseModel):
    folder: Folder
    uid: int


class SendRequest(BaseModel):
    to: list[EmailStr] = Field(min_length=1, max_length=20)
    cc: list[EmailStr] = Field(default_factory=list, max_length=20)
    subject: str = Field(min_length=1, max_length=300)
    body: str = Field(min_length=1, max_length=50000)
    reply: Optional[ReplyTo] = None

    @field_validator("subject")
    @classmethod
    def one_line(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("Add a subject.")
        return v


@router.post("/send")
async def send(body: SendRequest, request: Request, user: PanelUser = Depends(allow_support)):
    """Send from support@ (a reply when `reply` is set) and keep a copy in Sent."""
    request.state.audit_detail = {
        "to": [str(a) for a in body.to],
        "cc": [str(a) for a in body.cc],
        "subject": body.subject,
        "reply_to_uid": body.reply.uid if body.reply else None,
        "sent_by": user.name,
    }
    return await _run(
        mailbox.send,
        to=[str(a) for a in body.to],
        cc=[str(a) for a in body.cc],
        subject=body.subject,
        body=body.body,
        reply_folder=body.reply.folder if body.reply else None,
        reply_uid=str(body.reply.uid) if body.reply else None,
    )
