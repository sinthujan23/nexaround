"""Trip Wallet: splitting expenses and settling up (app/models/trip_wallet.py).

Every amount is whole minor units of the trip's currency (paise, cents; a
yen is its own minor unit), so a split always adds up to the expense: an
equal split gives the leftover units one each to the first people in it.

A member's balance is what they paid, less their shares, plus what they paid
others to settle up, less what others paid them. Positive: they get money
back. Negative: they owe. Balances add up to zero.

Settling up matches the person who owes most with the one owed most, pays the
smaller of the two, and repeats. That is at most (people − 1) payments, the
same as the usual split apps.

The functions above the "Notifications" section are pure, so they can be
tested on their own (tests/test_trip_wallet.py).
"""
import logging
import secrets
import uuid
from decimal import Decimal, InvalidOperation
from typing import Hashable, Iterable, Optional, Sequence

logger = logging.getLogger(__name__)

CATEGORIES = ("hotel", "transport", "food", "activities", "shopping", "other")
SPLIT_MODES = ("equal", "exact")

# No 0/O or 1/I/L: the code is read out loud and typed by hand.
INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
INVITE_LENGTH = 6

# ISO 4217 minor units that are not 2.
_ZERO_DECIMALS = {
    "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF",
    "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
}
_THREE_DECIMALS = {"BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"}

MAX_AMOUNT_MINOR = 10**13  # far above any trip; keeps a typo from overflowing


def currency_decimals(code: str) -> int:
    code = (code or "").upper()
    if code in _ZERO_DECIMALS:
        return 0
    if code in _THREE_DECIMALS:
        return 3
    return 2


def to_minor(amount, currency: str) -> int:
    """"4000.5" in INR → 400050. Raises ValueError for anything that is not a
    positive amount with at most the currency's decimals."""
    try:
        value = Decimal(str(amount).replace(",", "").strip())
    except (InvalidOperation, ValueError):
        raise ValueError("Not an amount")
    if not value.is_finite():
        raise ValueError("Not an amount")
    places = currency_decimals(currency)
    scaled = value * (Decimal(10) ** places)
    if scaled != scaled.to_integral_value():
        raise ValueError(f"At most {places} decimals for {currency.upper()}")
    minor = int(scaled)
    if minor <= 0:
        raise ValueError("Amount must be more than zero")
    if minor > MAX_AMOUNT_MINOR:
        raise ValueError("Amount is too large")
    return minor


def format_amount(minor: int, currency: str) -> str:
    """400050, INR → "INR 4,000.50"; 400000 → "INR 4,000"."""
    places = currency_decimals(currency)
    value = Decimal(minor) / (Decimal(10) ** places)
    text = f"{value:,.{places}f}"
    if places and text.endswith("." + "0" * places):
        text = text[: -(places + 1)]
    return f"{currency.upper()} {text}"


def make_invite_code() -> str:
    return "".join(secrets.choice(INVITE_ALPHABET) for _ in range(INVITE_LENGTH))


def normalise_code(code: str) -> str:
    return "".join(ch for ch in (code or "").upper() if ch.isalnum())


def split_equal(total_minor: int, member_ids: Sequence[Hashable]) -> dict:
    """Equal parts, in the order given; the leftover units go one each to the
    first people. 100 between 3 → 34, 33, 33."""
    if not member_ids:
        raise ValueError("Pick at least one person to split with")
    if len(set(member_ids)) != len(member_ids):
        raise ValueError("A person is in the split twice")
    base, extra = divmod(total_minor, len(member_ids))
    return {m: base + (1 if i < extra else 0) for i, m in enumerate(member_ids)}


def check_exact(total_minor: int, shares: dict) -> dict:
    """Exact parts typed in by hand: none negative, at least one person, and
    they must add up to the expense."""
    shares = {m: int(v) for m, v in shares.items() if int(v) != 0}
    if not shares:
        raise ValueError("Pick at least one person to split with")
    if any(v < 0 for v in shares.values()):
        raise ValueError("A share cannot be negative")
    if sum(shares.values()) != total_minor:
        raise ValueError("The shares must add up to the amount")
    return shares


def balances(
    member_ids: Iterable[Hashable],
    expenses: Iterable[tuple],
    settlements: Iterable[tuple] = (),
) -> dict:
    """Member → {paid, share, sent, received, net}.

    `expenses`: (payer, amount, {member: share}).
    `settlements`: (from, to, amount): `from` paid `to`.
    """
    out = {m: {"paid": 0, "share": 0, "sent": 0, "received": 0} for m in member_ids}

    def row(m):
        return out.setdefault(m, {"paid": 0, "share": 0, "sent": 0, "received": 0})

    for payer, amount, shares in expenses:
        row(payer)["paid"] += amount
        for m, part in shares.items():
            row(m)["share"] += part
    for frm, to, amount in settlements:
        row(frm)["sent"] += amount
        row(to)["received"] += amount
    for r in out.values():
        r["net"] = r["paid"] - r["share"] + r["sent"] - r["received"]
    return out


def settle_up(nets: dict, order: Optional[Sequence[Hashable]] = None) -> list:
    """The payments that bring every balance to zero: [(from, to, amount)].

    Biggest debtor pays biggest creditor the smaller of the two, repeat. Ties
    go by `order` (the members' order), so the list is the same every time.
    """
    order = list(order) if order is not None else list(nets)
    rank = {m: i for i, m in enumerate(order)}
    owe = {m: -v for m, v in nets.items() if v < 0}
    get = {m: v for m, v in nets.items() if v > 0}
    payments = []
    while owe and get:
        debtor = min(owe, key=lambda m: (-owe[m], rank.get(m, len(rank))))
        creditor = min(get, key=lambda m: (-get[m], rank.get(m, len(rank))))
        amount = min(owe[debtor], get[creditor])
        payments.append((debtor, creditor, amount))
        owe[debtor] -= amount
        get[creditor] -= amount
        if owe[debtor] == 0:
            del owe[debtor]
        if get[creditor] == 0:
            del get[creditor]
    return payments


# ── Notifications ──────────────────────────────────────────────────────────

PUSH_TYPE = "trip_wallet"


async def notify_members(
    trip_id: uuid.UUID,
    user_ids: Iterable[uuid.UUID],
    title: str,
    body: str,
) -> None:
    """A bell line and a push to each member's devices. Runs after the
    response as a background task, in its own session, and never raises."""
    from app.core.database import async_session
    from app.models.notification import Notification
    from app.services.enquiry_notifications import _push_data

    user_ids = list(dict.fromkeys(u for u in user_ids if u))
    if not user_ids:
        return
    try:
        async with async_session() as db:
            for uid in user_ids:
                db.add(Notification(user_id=uid, title=title, body=body, type=PUSH_TYPE))
            await db.commit()
            data = {"type": PUSH_TYPE, "trip_id": str(trip_id)}
            for uid in user_ids:
                try:
                    await _push_data(db, uid, title, body, data)
                except Exception as e:  # one bad device must not stop the rest
                    logger.warning(f"Trip Wallet push to {uid} failed: {e}")
    except Exception as e:
        logger.error(f"Trip Wallet notification for trip {trip_id} failed: {e}")
