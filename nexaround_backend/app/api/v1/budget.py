import uuid
from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.services.auth_service import AuthService
from app.services.budget_service import BudgetService
from app.schemas.budget import Budget, BudgetCreate, BudgetSummary, Expense, ExpenseCreate

from typing import Optional, List
from fastapi import APIRouter, Depends, Header, HTTPException

router = APIRouter(prefix="/budget", tags=["Budget"])

async def get_current_user_id(authorization: Optional[str] = Header(None), db: AsyncSession = Depends(get_db)) -> uuid.UUID:
    if not authorization:
        raise HTTPException(status_code=401, detail="Authentication token missing")
    
    try:
        token = authorization.replace("Bearer ", "")
        auth_service = AuthService(db)
        user = await auth_service.get_current_user(token)
        if not user:
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        return user.id
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Auth error: {str(e)}")

@router.get("/", response_model=Budget)
async def get_my_budget(
    user_id: uuid.UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Get the current user's active budget and expenses."""
    service = BudgetService(db)
    return await service.get_user_budget(user_id)

@router.get("/history", response_model=List[BudgetSummary])
async def get_budget_history(
    user_id: uuid.UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Get all budgets (active + closed) for history view."""
    service = BudgetService(db)
    return await service.get_all_budgets(user_id)

@router.get("/{budget_id}", response_model=Budget)
async def get_budget_detail(
    budget_id: uuid.UUID,
    user_id: uuid.UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Get a specific budget by ID with all expenses."""
    service = BudgetService(db)
    return await service.get_budget_by_id(budget_id, user_id)

@router.post("/", response_model=Budget)
async def setup_budget(
    data: BudgetCreate,
    user_id: uuid.UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Setup a new budget. Automatically closes any existing active budget."""
    service = BudgetService(db)
    return await service.setup_budget(user_id, data)

@router.post("/close", response_model=Budget)
async def close_budget(
    user_id: uuid.UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Close the current active budget."""
    service = BudgetService(db)
    return await service.close_budget(user_id)

@router.post("/expense", response_model=Expense)
async def add_expense(
    data: ExpenseCreate,
    user_id: uuid.UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Add a new expense to the current active budget."""
    service = BudgetService(db)
    return await service.add_expense(user_id, data)
