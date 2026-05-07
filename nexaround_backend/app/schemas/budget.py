from pydantic import BaseModel, ConfigDict
from datetime import datetime, date
from uuid import UUID
from typing import List, Optional

class ExpenseBase(BaseModel):
    amount: float
    category: str
    description: Optional[str] = None
    spent_at: Optional[datetime] = None

class ExpenseCreate(ExpenseBase):
    pass

class Expense(ExpenseBase):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    budget_id: UUID

class BudgetBase(BaseModel):
    name: str = "My Budget"
    total_amount: float
    currency: str = "LKR"
    start_date: date
    end_date: date

class BudgetCreate(BudgetBase):
    pass

class BudgetUpdate(BaseModel):
    name: Optional[str] = None
    total_amount: Optional[float] = None
    currency: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None

class Budget(BudgetBase):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    is_active: bool = True
    created_at: datetime
    expenses: List[Expense] = []

class BudgetSummary(BaseModel):
    """Lightweight budget info for history list (no expenses)."""
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    name: str
    total_amount: float
    currency: str
    start_date: date
    end_date: date
    is_active: bool
    created_at: datetime
    total_spent: float = 0.0
