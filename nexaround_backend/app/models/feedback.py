"""Explorer feedback and the quarterly survey (client request, 2026-11-26).

The client wants to "know the user pulse": what explorers want, what bothers
them, and whether they would pay. Three kinds of input, all read in the admin
panel's Feedback page:

- `Feedback` kind "message": the "Tell us what you want" form (Home card,
  Profile row): an idea, a problem, praise or anything else, with optional
  screenshots. The team can answer when the explorer allowed it.
- `Feedback` kind "quick": one tap after finishing something (an Odyssey plan,
  a City Guide trip, a Walking Challenge): good or bad, plus optional reasons.
  One per explorer per finished thing.
- `SurveyResponse`: the quarterly survey. The questions never change, so
  quarters compare; only each round's "build next" options are the team's.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, CheckConstraint, DateTime, ForeignKey, Index, Integer, SmallInteger, String,
    Text, UniqueConstraint, text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Feedback(Base):
    __tablename__ = "feedback"
    __table_args__ = (
        # The admin list: newest first, optionally one status or kind.
        Index("ix_feedback_status_created", "status", "created_at"),
        Index("ix_feedback_kind_created", "kind", "created_at"),
        # One quick rating per explorer per finished plan / trip / challenge.
        Index(
            "uq_feedback_quick_ref", "user_id", "feature", "ref_id", unique=True,
            postgresql_where=text("kind = 'quick'"),
        ),
        CheckConstraint("kind IN ('message', 'quick')", name="ck_feedback_kind"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Deleting an account deletes what it sent.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    kind: Mapped[str] = mapped_column(String(10), nullable=False, default="message")
    # message: idea | problem | love | other.  quick: good | bad.
    type: Mapped[str] = mapped_column(String(12), nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=True)
    # Quick "bad" reasons, e.g. ["too_far", "clues_hard"].
    reasons: Mapped[list] = mapped_column(ARRAY(String(32)), nullable=False, default=list)
    # File names inside FEEDBACK_UPLOAD_DIR/<user id>/ — private, never served
    # statically (screenshots can show personal details).
    screenshots: Mapped[list] = mapped_column(ARRAY(String(64)), nullable=False, default=list)
    can_reply: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    # What it is about, when sent from a finished thing: odyssey | city_guides
    # | walking_challenge, the thing's id and a readable name.
    feature: Mapped[str] = mapped_column(String(32), nullable=True)
    ref_id: Mapped[str] = mapped_column(String(64), nullable=True)
    ref_label: Mapped[str] = mapped_column(String(200), nullable=True)
    # Where the form was opened: home | profile | odyssey | city_guides | ...
    source_screen: Mapped[str] = mapped_column(String(40), nullable=True)

    app_version: Mapped[str] = mapped_column(String(32), nullable=True)
    platform: Mapped[str] = mapped_column(String(16), nullable=True)
    os_version: Mapped[str] = mapped_column(String(80), nullable=True)
    country: Mapped[str] = mapped_column(String(2), nullable=True)

    # new | seen | planned | done | replied | closed
    status: Mapped[str] = mapped_column(String(12), nullable=False, default="new")
    # [{text, by, at, sent: {bell, push, email}}]
    replies: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow, onupdate=_utcnow,
    )


class SurveyRound(Base):
    """One quarter's survey. At most one is open at a time."""
    __tablename__ = "survey_rounds"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(60), nullable=False)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    is_open: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    # [{key, label, icon}] — "What should we build next?" choices, in order.
    build_next_options: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_utcnow)


class SurveyResponse(Base):
    __tablename__ = "survey_responses"
    __table_args__ = (
        UniqueConstraint("round_id", "user_id", name="uq_survey_responses_round_user"),
        CheckConstraint("nps BETWEEN 0 AND 10", name="ck_survey_responses_nps"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    round_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("survey_rounds.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    nps: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    features: Mapped[list] = mapped_column(ARRAY(String(32)), nullable=False, default=list)
    # Option keys in the order picked: the first is the explorer's top wish.
    build_next: Mapped[list] = mapped_column(ARRAY(String(40)), nullable=False, default=list)
    build_next_other: Mapped[str] = mapped_column(String(300), nullable=True)
    would_pay: Mapped[str] = mapped_column(String(6), nullable=False)  # yes | maybe | no
    price_range: Mapped[str] = mapped_column(String(8), nullable=True)  # lt2 | 2to5 | 5to8 | 8to12 | gt12
    why_not: Mapped[list] = mapped_column(ARRAY(String(16)), nullable=False, default=list)
    comment: Mapped[str] = mapped_column(Text, nullable=True)
    app_version: Mapped[str] = mapped_column(String(32), nullable=True)
    platform: Mapped[str] = mapped_column(String(16), nullable=True)
    country: Mapped[str] = mapped_column(String(2), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_utcnow)


class SurveyPrompt(Base):
    """How often a round popped up for an explorer, and when "Later" lets it
    come back. Kept on the server so a reinstall doesn't reset it."""
    __tablename__ = "survey_prompts"

    round_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("survey_rounds.id", ondelete="CASCADE"), primary_key=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True,
    )
    shown_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    snoozed_until: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
