"""Trip Wallet: a shared expense ledger for a group trip.

One person makes a trip and shares its invite link; friends join. Anyone in
the trip records what they paid and who it was for; the app shows each
person's balance and the fewest payments that settle everyone up. A payment
made to settle up is recorded too, so balances move towards zero.

Money is whole minor units of the trip's one currency (paise, cents), so a
split always adds up to the expense. See app/services/trip_wallet.py.
"""
import uuid
from datetime import date, datetime, timezone

from sqlalchemy import BigInteger, Date, DateTime, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class WalletTrip(Base):
    __tablename__ = "wallet_trips"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    # ISO 4217 code. One per trip: nothing is converted.
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    # What the invite link carries (nexaround.com/w/<code>). The owner can
    # reset it, which stops the old link working.
    invite_code: Mapped[str] = mapped_column(String(8), nullable=False, unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now, nullable=False,
    )
    deleted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)


class WalletMember(Base):
    """Someone in a trip. `user_id` is NULL for a name-only member the owner
    added (a friend without the app); they still count in splits. A member who
    leaves keeps their row (`left_at`) so past expenses still name them."""
    __tablename__ = "wallet_members"
    __table_args__ = (
        UniqueConstraint("trip_id", "user_id", name="uq_wallet_members_trip_user"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_trips.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True,
    )
    display_name: Mapped[str] = mapped_column(String(100), nullable=False)
    role: Mapped[str] = mapped_column(String(10), nullable=False, default="member")  # owner|member
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)
    left_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)


class WalletExpense(Base):
    __tablename__ = "wallet_expenses"
    __table_args__ = (
        Index("ix_wallet_expenses_trip", "trip_id", "spent_on"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_trips.id", ondelete="CASCADE"), nullable=False,
    )
    paid_by_member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_members.id", ondelete="CASCADE"), nullable=False,
    )
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    category: Mapped[str] = mapped_column(String(20), nullable=False, default="other")
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    spent_on: Mapped[date] = mapped_column(Date, nullable=False)
    receipt_url: Mapped[str] = mapped_column(String(500), nullable=True)
    split_mode: Mapped[str] = mapped_column(String(10), nullable=False, default="equal")  # equal|exact
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now, nullable=False,
    )
    deleted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)


class WalletExpenseShare(Base):
    """One person's part of an expense. The parts add up to the expense."""
    __tablename__ = "wallet_expense_shares"

    expense_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_expenses.id", ondelete="CASCADE"), primary_key=True,
    )
    member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_members.id", ondelete="CASCADE"), primary_key=True,
    )
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)


class WalletSettlement(Base):
    """A payment one member made to another to settle up.

    The trip owner approves each one: a payment marked by anyone else waits
    (`pending`) and counts in no balance until the owner approves it
    (`confirmed`); one the owner marks is confirmed at once. Rejecting
    deletes it."""
    __tablename__ = "wallet_settlements"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_trips.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    from_member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_members.id", ondelete="CASCADE"), nullable=False,
    )
    to_member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("wallet_members.id", ondelete="CASCADE"), nullable=False,
    )
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)
    status: Mapped[str] = mapped_column(
        String(10), nullable=False, default="confirmed", server_default="confirmed",
    )  # pending|confirmed
    approved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
