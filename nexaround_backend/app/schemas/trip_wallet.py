"""Trip Wallet request bodies (app/api/v1/trip_wallet.py).

Amounts come in as the traveller typed them ("4000", "12.50") and are turned
into minor units by the service, which knows the trip's currency.
"""
import uuid
from datetime import date
from typing import List, Optional, Union

from pydantic import BaseModel, Field, field_validator


def _currency(v: str) -> str:
    v = (v or "").strip().upper()
    if len(v) != 3 or not v.isalpha():
        raise ValueError("Currency must be a 3-letter code, e.g. INR")
    return v


class TripCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    currency: str

    @field_validator("currency")
    @classmethod
    def _cur(cls, v):
        return _currency(v)


class TripUpdateIn(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=80)
    # Only while the trip has no expenses or payments yet.
    currency: Optional[str] = None

    @field_validator("currency")
    @classmethod
    def _cur(cls, v):
        return _currency(v) if v is not None else v


class MemberAddIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=100)


class ShareIn(BaseModel):
    member_id: uuid.UUID
    amount: Union[str, float, int]


class ExpenseIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    category: str = "other"
    amount: Union[str, float, int]
    spent_on: date
    paid_by_member_id: uuid.UUID
    split_mode: str = "equal"
    # equal: who it is split between, in any order.
    member_ids: List[uuid.UUID] = []
    # exact: each person's part; they must add up to `amount`.
    shares: List[ShareIn] = []
    receipt_url: Optional[str] = Field(default=None, max_length=500)


class SettlementIn(BaseModel):
    from_member_id: uuid.UUID
    to_member_id: uuid.UUID
    amount: Union[str, float, int]
