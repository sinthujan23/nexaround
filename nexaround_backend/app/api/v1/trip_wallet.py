"""Trip Wallet: a group's shared expense ledger (app/services/trip_wallet.py).

Only members see a trip; anyone else gets 404, the same as a trip that does
not exist. Any member adds expenses; the person who added one, or the owner,
can change or delete it. Any member can mark a payment made, but it counts
only once the owner approves it (one the owner marks counts at once). Only
the owner renames the trip, resets its invite code, removes members and
deletes it.

Money goes out as whole minor units with the trip's `decimals`; it comes in
as typed ("4000", "12.50").
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.share import absolute_image_url
from app.core.config import settings
from app.core.database import get_db
from app.models.trip_wallet import (
    WalletExpense, WalletExpenseShare, WalletMember, WalletSettlement, WalletTrip,
)
from app.models.user import User
from app.schemas.trip_wallet import (
    ExpenseIn, MemberAddIn, SettlementIn, TripCreateIn, TripUpdateIn,
)
from app.services import trip_wallet as tw
from app.services.experience_upload import save_experience_images

router = APIRouter(prefix="/trip-wallet", tags=["Trip Wallet"])

MAX_MEMBERS = 50
RECEIPT_PREFIX = "/static/uploads/wallet/"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def invite_url(code: str) -> str:
    return f"{settings.PUBLIC_SITE_URL.rstrip('/')}/w/{code}"


def _bad(msg: str) -> HTTPException:
    return HTTPException(status_code=400, detail=msg)


# ── Loading ────────────────────────────────────────────────────────────────

async def _members(db: AsyncSession, trip_id: uuid.UUID) -> list[WalletMember]:
    return list((await db.execute(
        select(WalletMember)
        .where(WalletMember.trip_id == trip_id)
        .order_by(WalletMember.joined_at, WalletMember.id)
    )).scalars())


async def _load(db: AsyncSession, trip_id: uuid.UUID, user: User):
    """The trip, its members and the caller's member row; 404 unless the
    caller is in it."""
    trip = await db.get(WalletTrip, trip_id)
    if trip is None or trip.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Trip not found")
    members = await _members(db, trip.id)
    me = next((m for m in members if m.user_id == user.id and m.left_at is None), None)
    if me is None:
        raise HTTPException(status_code=404, detail="Trip not found")
    return trip, members, me


async def _ledger(db: AsyncSession, trip_id: uuid.UUID):
    """(expenses, {expense id: {member id: share}}, settlements), oldest first."""
    expenses = list((await db.execute(
        select(WalletExpense)
        .where(WalletExpense.trip_id == trip_id, WalletExpense.deleted_at.is_(None))
        .order_by(WalletExpense.spent_on, WalletExpense.created_at)
    )).scalars())
    shares: dict = {e.id: {} for e in expenses}
    if expenses:
        rows = (await db.execute(
            select(WalletExpenseShare).where(WalletExpenseShare.expense_id.in_(list(shares)))
        )).scalars()
        for s in rows:
            shares[s.expense_id][s.member_id] = s.amount_minor
    settlements = list((await db.execute(
        select(WalletSettlement)
        .where(WalletSettlement.trip_id == trip_id)
        .order_by(WalletSettlement.created_at)
    )).scalars())
    return expenses, shares, settlements


def _balances(members, expenses, shares, settlements) -> dict:
    """Payments waiting for the owner's approval count in nothing yet."""
    return tw.balances(
        [m.id for m in members],
        [(e.paid_by_member_id, e.amount_minor, shares[e.id]) for e in expenses],
        [
            (s.from_member_id, s.to_member_id, s.amount_minor)
            for s in settlements if s.status == "confirmed"
        ],
    )


async def _view(db: AsyncSession, trip: WalletTrip, members, me: WalletMember, user: User) -> dict:
    expenses, shares, settlements = await _ledger(db, trip.id)
    rows = _balances(members, expenses, shares, settlements)
    order = [m.id for m in members]
    payments = tw.settle_up({m: r["net"] for m, r in rows.items()}, order)

    users = {}
    uids = [m.user_id for m in members if m.user_id]
    if uids:
        users = {u.id: u for u in (await db.execute(select(User).where(User.id.in_(uids)))).scalars()}

    is_owner = me.role == "owner"

    def member_view(m: WalletMember) -> dict:
        u = users.get(m.user_id) if m.user_id else None
        return {
            "id": str(m.id),
            "display_name": m.display_name,
            "avatar_url": absolute_image_url(u.avatar_url) if u else None,
            "role": m.role,
            "is_me": m.id == me.id,
            "has_app": m.user_id is not None,
            "left": m.left_at is not None,
        }

    return {
        "id": str(trip.id),
        "name": trip.name,
        "currency": trip.currency,
        "decimals": tw.currency_decimals(trip.currency),
        "invite_code": trip.invite_code,
        "invite_url": invite_url(trip.invite_code),
        "is_owner": is_owner,
        "my_member_id": str(me.id),
        "created_at": trip.created_at.isoformat(),
        "total_spent": sum(e.amount_minor for e in expenses),
        "members": [member_view(m) for m in members],
        "expenses": [
            {
                "id": str(e.id),
                "title": e.title,
                "category": e.category,
                "amount_minor": e.amount_minor,
                "spent_on": e.spent_on.isoformat(),
                "paid_by_member_id": str(e.paid_by_member_id),
                "split_mode": e.split_mode,
                "shares": [
                    {"member_id": str(mid), "amount_minor": amt}
                    for mid, amt in shares[e.id].items()
                ],
                "receipt_url": absolute_image_url(e.receipt_url),
                "can_edit": is_owner or e.created_by_user_id == user.id,
                "created_at": e.created_at.isoformat(),
            }
            # Newest first, as the app lists them.
            for e in reversed(expenses)
        ],
        "balances": [
            {"member_id": str(m.id), **rows[m.id]} for m in members
        ],
        "settle_up": [
            {"from_member_id": str(f), "to_member_id": str(t), "amount_minor": a}
            for f, t, a in payments
        ],
        # Newest first; `pending` ones wait for the owner and count in no
        # balance. The owner approves or rejects a pending one; whoever marked
        # it can withdraw it; only the owner can undo a confirmed one.
        "settlements": [
            {
                "id": str(s.id),
                "from_member_id": str(s.from_member_id),
                "to_member_id": str(s.to_member_id),
                "amount_minor": s.amount_minor,
                "status": s.status,
                "created_at": s.created_at.isoformat(),
                "marked_by_me": s.created_by_user_id == user.id,
                "can_approve": is_owner and s.status == "pending",
                "can_delete": is_owner or (s.status == "pending" and s.created_by_user_id == user.id),
            }
            for s in reversed(settlements)
        ],
        "pending_count": sum(1 for s in settlements if s.status == "pending"),
    }


async def _answer(db: AsyncSession, trip_id: uuid.UUID, user: User) -> dict:
    trip, members, me = await _load(db, trip_id, user)
    return await _view(db, trip, members, me, user)


def _others(members, me: WalletMember) -> list:
    """The app users to tell about something `me` did."""
    return [m.user_id for m in members if m.user_id and m.left_at is None and m.id != me.id]


def _owner_only(me: WalletMember) -> None:
    if me.role != "owner":
        raise HTTPException(status_code=403, detail="Only the trip owner can do that")


async def _new_code(db: AsyncSession) -> str:
    for _ in range(20):
        code = tw.make_invite_code()
        taken = (await db.execute(
            select(WalletTrip.id).where(WalletTrip.invite_code == code)
        )).first()
        if not taken:
            return code
    raise HTTPException(status_code=500, detail="Could not make an invite code, try again")


async def _net_of(db: AsyncSession, trip_id: uuid.UUID, members, member_id: uuid.UUID) -> int:
    expenses, shares, settlements = await _ledger(db, trip_id)
    return _balances(members, expenses, shares, settlements).get(member_id, {}).get("net", 0)


# ── Trips ──────────────────────────────────────────────────────────────────

@router.get("/trips")
async def list_trips(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    """The caller's trips, newest first, with their own balance in each."""
    mine = (await db.execute(
        select(WalletMember, WalletTrip)
        .join(WalletTrip, WalletTrip.id == WalletMember.trip_id)
        .where(
            WalletMember.user_id == user.id,
            WalletMember.left_at.is_(None),
            WalletTrip.deleted_at.is_(None),
        )
        .order_by(WalletTrip.created_at.desc())
    )).all()
    out = []
    for me, trip in mine:
        members = await _members(db, trip.id)
        expenses, shares, settlements = await _ledger(db, trip.id)
        rows = _balances(members, expenses, shares, settlements)
        out.append({
            "id": str(trip.id),
            "name": trip.name,
            "currency": trip.currency,
            "decimals": tw.currency_decimals(trip.currency),
            "is_owner": me.role == "owner",
            "member_count": sum(1 for m in members if m.left_at is None),
            "expense_count": len(expenses),
            "total_spent": sum(e.amount_minor for e in expenses),
            "my_net": rows.get(me.id, {}).get("net", 0),
            # Payments waiting for approval: the owner's to-do.
            "pending_count": sum(1 for x in settlements if x.status == "pending"),
            "created_at": trip.created_at.isoformat(),
        })
    return {"trips": out}


@router.post("/trips")
async def create_trip(body: TripCreateIn, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    trip = WalletTrip(
        owner_id=user.id, name=body.name.strip(), currency=body.currency,
        invite_code=await _new_code(db),
    )
    db.add(trip)
    await db.flush()
    db.add(WalletMember(
        trip_id=trip.id, user_id=user.id, display_name=user.display_name or "Me", role="owner",
    ))
    await db.commit()
    return await _answer(db, trip.id, user)


@router.get("/trips/{trip_id}")
async def get_trip(trip_id: uuid.UUID, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    return await _answer(db, trip_id, user)


@router.patch("/trips/{trip_id}")
async def update_trip(
    trip_id: uuid.UUID, body: TripUpdateIn,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    trip, members, me = await _load(db, trip_id, user)
    _owner_only(me)
    if body.name is not None:
        trip.name = body.name.strip()
    if body.currency is not None and body.currency != trip.currency:
        expenses, _, settlements = await _ledger(db, trip.id)
        if expenses or settlements:
            raise _bad("The currency can't change once expenses are added")
        trip.currency = body.currency
    await db.commit()
    return await _answer(db, trip.id, user)


@router.delete("/trips/{trip_id}")
async def delete_trip(trip_id: uuid.UUID, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    trip, members, me = await _load(db, trip_id, user)
    _owner_only(me)
    trip.deleted_at = _now()
    await db.commit()
    return {"ok": True}


@router.post("/trips/{trip_id}/invite/reset")
async def reset_invite(trip_id: uuid.UUID, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    """A new code; the old link stops working."""
    trip, members, me = await _load(db, trip_id, user)
    _owner_only(me)
    trip.invite_code = await _new_code(db)
    await db.commit()
    return await _answer(db, trip.id, user)


# ── Joining and members ────────────────────────────────────────────────────

async def _trip_by_code(db: AsyncSession, code: str) -> WalletTrip:
    code = tw.normalise_code(code)
    trip = (await db.execute(
        select(WalletTrip).where(WalletTrip.invite_code == code, WalletTrip.deleted_at.is_(None))
    )).scalar_one_or_none() if code else None
    if trip is None:
        raise HTTPException(status_code=404, detail="This invite link is not valid any more")
    return trip


@router.get("/join/{code}")
async def join_preview(code: str, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    """What the join screen shows before the traveller taps Join."""
    trip = await _trip_by_code(db, code)
    members = await _members(db, trip.id)
    active = [m for m in members if m.left_at is None]
    owner = next((m for m in members if m.role == "owner"), None)
    return {
        "trip_id": str(trip.id),
        "name": trip.name,
        "currency": trip.currency,
        "owner_name": owner.display_name if owner else None,
        "member_count": len(active),
        "member_names": [m.display_name for m in active][:8],
        "already_member": any(m.user_id == user.id for m in active),
    }


@router.post("/join/{code}")
async def join_trip(
    code: str, background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    trip = await _trip_by_code(db, code)
    members = await _members(db, trip.id)
    mine = next((m for m in members if m.user_id == user.id), None)
    if mine is not None and mine.left_at is None:
        return await _answer(db, trip.id, user)
    if sum(1 for m in members if m.left_at is None) >= MAX_MEMBERS:
        raise _bad(f"A trip can have up to {MAX_MEMBERS} people")
    if mine is not None:  # left before; back in with the same row
        mine.left_at = None
        mine.display_name = user.display_name or mine.display_name
    else:
        mine = WalletMember(trip_id=trip.id, user_id=user.id, display_name=user.display_name or "Traveller")
        db.add(mine)
    await db.commit()
    background_tasks.add_task(
        tw.notify_members, trip.id, _others(members, mine),
        trip.name, f"{mine.display_name} joined the trip",
    )
    return await _answer(db, trip.id, user)


@router.post("/trips/{trip_id}/members")
async def add_member(
    trip_id: uuid.UUID, body: MemberAddIn,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    """A name-only member: a friend without the app, who still counts in
    splits. Any member can add one (the person paying often knows best)."""
    trip, members, me = await _load(db, trip_id, user)
    if sum(1 for m in members if m.left_at is None) >= MAX_MEMBERS:
        raise _bad(f"A trip can have up to {MAX_MEMBERS} people")
    db.add(WalletMember(trip_id=trip.id, user_id=None, display_name=body.display_name.strip()))
    await db.commit()
    return await _answer(db, trip.id, user)


async def _take_out(db: AsyncSession, trip, members, member: WalletMember) -> None:
    if await _net_of(db, trip.id, members, member.id) != 0:
        raise _bad(f"{member.display_name} still owes or is owed money. Settle up first.")
    member.left_at = _now()
    await db.commit()


@router.delete("/trips/{trip_id}/members/{member_id}")
async def remove_member(
    trip_id: uuid.UUID, member_id: uuid.UUID,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    trip, members, me = await _load(db, trip_id, user)
    _owner_only(me)
    member = next((m for m in members if m.id == member_id and m.left_at is None), None)
    if member is None:
        raise HTTPException(status_code=404, detail="Member not found")
    if member.id == me.id:
        raise _bad("The owner can't be removed. Delete the trip instead.")
    await _take_out(db, trip, members, member)
    return await _answer(db, trip.id, user)


@router.post("/trips/{trip_id}/leave")
async def leave_trip(trip_id: uuid.UUID, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    trip, members, me = await _load(db, trip_id, user)
    if me.role == "owner":
        raise _bad("The owner can't leave the trip. Delete it instead.")
    await _take_out(db, trip, members, me)
    return {"ok": True}


# ── Expenses ───────────────────────────────────────────────────────────────

def _receipt(url: Optional[str]) -> Optional[str]:
    """Only a receipt uploaded here; the app may send back the full URL."""
    if not url:
        return None
    base = settings.PUBLIC_BASE_URL.rstrip("/")
    if url.startswith(base):
        url = url[len(base):]
    if not url.startswith(RECEIPT_PREFIX) or ".." in url:
        raise _bad("Upload the receipt photo first")
    return url


def _shape_expense(body: ExpenseIn, trip: WalletTrip, members, allowed: set) -> tuple[int, dict]:
    """(amount, {member id: share}) from the request, or 400."""
    if body.category not in tw.CATEGORIES:
        raise _bad("Unknown category")
    if body.split_mode not in tw.SPLIT_MODES:
        raise _bad("Unknown split")
    if body.paid_by_member_id not in allowed:
        raise _bad("Pick who paid from the trip's members")
    try:
        amount = tw.to_minor(body.amount, trip.currency)
        if body.split_mode == "equal":
            order = {m.id: i for i, m in enumerate(members)}
            ids = list(dict.fromkeys(body.member_ids))
            if any(i not in allowed for i in ids):
                raise ValueError("Split only between the trip's members")
            ids.sort(key=lambda i: order.get(i, 0))
            shares = tw.split_equal(amount, ids)
        else:
            parts = {}
            for s in body.shares:
                if s.member_id not in allowed:
                    raise ValueError("Split only between the trip's members")
                if s.member_id in parts:
                    raise ValueError("A person is in the split twice")
                text = str(s.amount).strip()
                parts[s.member_id] = 0 if text in ("", "0", "0.0", "0.00") else tw.to_minor(text, trip.currency)
            shares = tw.check_exact(amount, parts)
    except ValueError as e:
        raise _bad(str(e))
    return amount, shares


def _save_shares(db: AsyncSession, expense_id: uuid.UUID, shares: dict) -> None:
    for mid, amt in shares.items():
        db.add(WalletExpenseShare(expense_id=expense_id, member_id=mid, amount_minor=amt))


@router.post("/trips/{trip_id}/expenses")
async def add_expense(
    trip_id: uuid.UUID, body: ExpenseIn, background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    trip, members, me = await _load(db, trip_id, user)
    allowed = {m.id for m in members if m.left_at is None}
    amount, shares = _shape_expense(body, trip, members, allowed)
    expense = WalletExpense(
        trip_id=trip.id, paid_by_member_id=body.paid_by_member_id, title=body.title.strip(),
        category=body.category, amount_minor=amount, spent_on=body.spent_on,
        receipt_url=_receipt(body.receipt_url), split_mode=body.split_mode,
        created_by_user_id=user.id,
    )
    db.add(expense)
    await db.flush()
    _save_shares(db, expense.id, shares)
    await db.commit()
    background_tasks.add_task(
        tw.notify_members, trip.id, _others(members, me), trip.name,
        f"{me.display_name} added {expense.title} · {tw.format_amount(amount, trip.currency)}",
    )
    return await _answer(db, trip.id, user)


async def _own_expense(db: AsyncSession, trip, me, expense_id: uuid.UUID, user: User) -> WalletExpense:
    expense = await db.get(WalletExpense, expense_id)
    if expense is None or expense.trip_id != trip.id or expense.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Expense not found")
    if me.role != "owner" and expense.created_by_user_id != user.id:
        raise HTTPException(status_code=403, detail="Only the person who added it or the owner can change it")
    return expense


@router.patch("/trips/{trip_id}/expenses/{expense_id}")
async def update_expense(
    trip_id: uuid.UUID, expense_id: uuid.UUID, body: ExpenseIn,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    """The whole expense again, as the edit screen sends it."""
    trip, members, me = await _load(db, trip_id, user)
    expense = await _own_expense(db, trip, me, expense_id, user)
    old = (await db.execute(
        select(WalletExpenseShare).where(WalletExpenseShare.expense_id == expense.id)
    )).scalars().all()
    # People who have left stay allowed on an expense they were already on.
    allowed = {m.id for m in members if m.left_at is None}
    allowed |= {s.member_id for s in old} | {expense.paid_by_member_id}
    amount, shares = _shape_expense(body, trip, members, allowed)
    expense.title = body.title.strip()
    expense.category = body.category
    expense.amount_minor = amount
    expense.spent_on = body.spent_on
    expense.paid_by_member_id = body.paid_by_member_id
    expense.split_mode = body.split_mode
    expense.receipt_url = _receipt(body.receipt_url)
    for s in old:
        await db.delete(s)
    await db.flush()
    _save_shares(db, expense.id, shares)
    await db.commit()
    return await _answer(db, trip.id, user)


@router.delete("/trips/{trip_id}/expenses/{expense_id}")
async def delete_expense(
    trip_id: uuid.UUID, expense_id: uuid.UUID,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    trip, members, me = await _load(db, trip_id, user)
    expense = await _own_expense(db, trip, me, expense_id, user)
    expense.deleted_at = _now()
    await db.commit()
    return await _answer(db, trip.id, user)


@router.post("/trips/{trip_id}/receipt")
async def upload_receipt(
    trip_id: uuid.UUID, file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    """One receipt photo; the app puts the returned path on the expense."""
    await _load(db, trip_id, user)
    urls = await save_experience_images([file], subdir="wallet")
    return {"url": urls[0], "full_url": absolute_image_url(urls[0])}


# ── Settling up ────────────────────────────────────────────────────────────

def _owner(members) -> Optional[WalletMember]:
    return next((m for m in members if m.role == "owner"), None)


@router.post("/trips/{trip_id}/settlements")
async def add_settlement(
    trip_id: uuid.UUID, body: SettlementIn, background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    """"Mark paid": `from` paid `to` this much. Marked by the owner it counts
    at once; marked by anyone else it waits for the owner's approval."""
    trip, members, me = await _load(db, trip_id, user)
    by_id = {m.id: m for m in members if m.left_at is None}
    frm, to = by_id.get(body.from_member_id), by_id.get(body.to_member_id)
    if frm is None or to is None or frm.id == to.id:
        raise _bad("Pick two different people from the trip")
    try:
        amount = tw.to_minor(body.amount, trip.currency)
    except ValueError as e:
        raise _bad(str(e))
    is_owner = me.role == "owner"
    if not is_owner:
        waiting = (await db.execute(
            select(WalletSettlement.id).where(
                WalletSettlement.trip_id == trip.id,
                WalletSettlement.from_member_id == frm.id,
                WalletSettlement.to_member_id == to.id,
                WalletSettlement.status == "pending",
            )
        )).first()
        if waiting:
            raise _bad("This payment is already waiting for the owner's approval")
    db.add(WalletSettlement(
        trip_id=trip.id, from_member_id=frm.id, to_member_id=to.id,
        amount_minor=amount, created_by_user_id=user.id,
        status="confirmed" if is_owner else "pending",
        approved_at=_now() if is_owner else None,
    ))
    await db.commit()
    paid = f"{frm.display_name} paid {to.display_name} {tw.format_amount(amount, trip.currency)}"
    if is_owner:
        background_tasks.add_task(tw.notify_members, trip.id, _others(members, me), trip.name, paid)
    else:
        owner = _owner(members)
        background_tasks.add_task(
            tw.notify_members, trip.id, [owner.user_id] if owner else [], trip.name,
            f"{me.display_name} says {paid}. Tap to approve.",
        )
    return await _answer(db, trip.id, user)


@router.post("/trips/{trip_id}/settlements/{settlement_id}/approve")
async def approve_settlement(
    trip_id: uuid.UUID, settlement_id: uuid.UUID, background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    """The owner confirms a payment someone marked; now it counts."""
    trip, members, me = await _load(db, trip_id, user)
    _owner_only(me)
    s = await db.get(WalletSettlement, settlement_id)
    if s is None or s.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Payment not found")
    if s.status != "pending":
        return await _answer(db, trip.id, user)
    s.status = "confirmed"
    s.approved_at = _now()
    await db.commit()
    by_id = {m.id: m for m in members}
    frm, to = by_id.get(s.from_member_id), by_id.get(s.to_member_id)
    background_tasks.add_task(
        tw.notify_members, trip.id, _others(members, me), trip.name,
        f"Approved: {frm.display_name if frm else 'Someone'} paid "
        f"{to.display_name if to else 'someone'} {tw.format_amount(s.amount_minor, trip.currency)}",
    )
    return await _answer(db, trip.id, user)


@router.delete("/trips/{trip_id}/settlements/{settlement_id}")
async def delete_settlement(
    trip_id: uuid.UUID, settlement_id: uuid.UUID, background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db), user=Depends(get_current_user),
):
    """Undo a "Mark paid": the owner rejects a pending payment or undoes a
    confirmed one; whoever marked a pending one can withdraw it."""
    trip, members, me = await _load(db, trip_id, user)
    s = await db.get(WalletSettlement, settlement_id)
    if s is None or s.trip_id != trip.id:
        raise HTTPException(status_code=404, detail="Payment not found")
    is_owner = me.role == "owner"
    if not is_owner and not (s.status == "pending" and s.created_by_user_id == user.id):
        raise HTTPException(status_code=403, detail="Only the trip owner can undo an approved payment")
    rejected = is_owner and s.status == "pending" and s.created_by_user_id != user.id
    marker = s.created_by_user_id
    amount = s.amount_minor
    await db.delete(s)
    await db.commit()
    if rejected and marker:
        background_tasks.add_task(
            tw.notify_members, trip.id, [marker], trip.name,
            f"{me.display_name} did not approve the payment of "
            f"{tw.format_amount(amount, trip.currency)}. Check with them.",
        )
    return await _answer(db, trip.id, user)
