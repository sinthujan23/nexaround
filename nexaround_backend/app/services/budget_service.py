from typing import List
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.repositories.budget_repository import BudgetRepository
from app.schemas.budget import (
    BudgetCreate, ExpenseCreate,
    Budget as BudgetSchema, Expense as ExpenseSchema,
    BudgetSummary,
)
from app.core.exceptions import NotFoundException

class BudgetService:
    def __init__(self, db: AsyncSession):
        self.repo = BudgetRepository(db)

    async def get_user_budget(self, user_id: UUID) -> BudgetSchema:
        """Get the user's active budget with expenses."""
        budget = await self.repo.get_active_budget_by_user(user_id)
        if not budget:
            raise NotFoundException(detail="No active budget found for this user")
        return BudgetSchema.model_validate(budget)

    async def get_budget_by_id(self, budget_id: UUID, user_id: UUID) -> BudgetSchema:
        """Get a specific budget by ID (for viewing past budgets)."""
        budget = await self.repo.get_budget_by_id(budget_id)
        if not budget or budget.user_id != user_id:
            raise NotFoundException(detail="Budget not found")
        return BudgetSchema.model_validate(budget)

    async def get_all_budgets(self, user_id: UUID) -> List[BudgetSummary]:
        """Get all budgets (active + closed) for history view."""
        budgets = await self.repo.get_all_budgets_by_user(user_id)
        summaries = []
        for b in budgets:
            total_spent = sum(e.amount for e in b.expenses)
            summary = BudgetSummary(
                id=b.id,
                user_id=b.user_id,
                name=b.name,
                total_amount=b.total_amount,
                currency=b.currency,
                start_date=b.start_date,
                end_date=b.end_date,
                is_active=b.is_active,
                created_at=b.created_at,
                total_spent=total_spent,
            )
            summaries.append(summary)
        return summaries

    async def setup_budget(self, user_id: UUID, budget_in: BudgetCreate) -> BudgetSchema:
        """Create a new active budget. Closes any existing active budget first."""
        existing = await self.repo.get_active_budget_by_user(user_id)
        if existing:
            await self.repo.close_budget(existing.id)

        budget = await self.repo.create_budget(user_id, budget_in)
        return BudgetSchema.model_validate(budget)

    async def close_budget(self, user_id: UUID) -> BudgetSchema:
        """Close the user's active budget."""
        budget = await self.repo.get_active_budget_by_user(user_id)
        if not budget:
            raise NotFoundException(detail="No active budget to close")

        closed = await self.repo.close_budget(budget.id)
        return BudgetSchema.model_validate(closed)

    async def add_expense(self, user_id: UUID, expense_in: ExpenseCreate) -> ExpenseSchema:
        budget = await self.repo.get_active_budget_by_user(user_id)
        if not budget:
            raise NotFoundException(detail="No active budget found. Please setup a budget first.")

        expense = await self.repo.add_expense(budget.id, expense_in)
        return ExpenseSchema.model_validate(expense)
