from typing import List, Optional
from uuid import UUID
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.budget import Budget, Expense
from app.schemas.budget import BudgetCreate, ExpenseCreate

class BudgetRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_active_budget_by_user(self, user_id: UUID) -> Optional[Budget]:
        """Get the user's currently active budget."""
        result = await self.db.execute(
            select(Budget)
            .where(Budget.user_id == user_id, Budget.is_active == True)
            .order_by(Budget.created_at.desc())
        )
        return result.scalars().first()

    async def get_budget_by_user(self, user_id: UUID) -> Optional[Budget]:
        """Fallback: get latest budget regardless of status."""
        result = await self.db.execute(
            select(Budget).where(Budget.user_id == user_id).order_by(Budget.created_at.desc())
        )
        return result.scalars().first()

    async def get_budget_by_id(self, budget_id: UUID) -> Optional[Budget]:
        result = await self.db.execute(
            select(Budget).where(Budget.id == budget_id)
        )
        return result.scalars().first()

    async def get_all_budgets_by_user(self, user_id: UUID) -> List[Budget]:
        """Get all budgets (active + closed) for history."""
        result = await self.db.execute(
            select(Budget)
            .where(Budget.user_id == user_id)
            .order_by(Budget.created_at.desc())
        )
        return list(result.scalars().all())

    async def create_budget(self, user_id: UUID, budget_in: BudgetCreate) -> Budget:
        db_budget = Budget(
            user_id=user_id,
            **budget_in.model_dump()
        )
        self.db.add(db_budget)
        await self.db.commit()
        await self.db.refresh(db_budget)
        return db_budget

    async def close_budget(self, budget_id: UUID) -> Budget:
        await self.db.execute(
            update(Budget).where(Budget.id == budget_id).values(is_active=False)
        )
        await self.db.commit()
        budget = await self.get_budget_by_id(budget_id)
        return budget

    async def add_expense(self, budget_id: UUID, expense_in: ExpenseCreate) -> Expense:
        db_expense = Expense(
            budget_id=budget_id,
            **expense_in.model_dump()
        )
        self.db.add(db_expense)
        await self.db.commit()
        await self.db.refresh(db_expense)
        return db_expense

    async def get_expenses_by_budget(self, budget_id: UUID) -> List[Expense]:
        result = await self.db.execute(
            select(Expense).where(Expense.budget_id == budget_id).order_by(Expense.spent_at.desc())
        )
        return list(result.scalars().all())
