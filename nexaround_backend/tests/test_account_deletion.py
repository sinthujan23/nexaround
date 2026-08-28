import pytest
import uuid
from unittest.mock import AsyncMock, patch, MagicMock
from app.services.auth_service import AuthService
from app.models.user import User


@pytest.mark.asyncio
async def test_delete_account_removes_user_and_cascades():
    mock_db = AsyncMock()
    mock_db.execute = AsyncMock()
    mock_scalars = MagicMock()
    mock_scalars.scalars.return_value.all.return_value = []
    mock_db.execute.return_value = mock_scalars
    mock_db.commit = AsyncMock()

    service = AuthService(mock_db)
    user_id = uuid.uuid4()
    dummy_user = User(
        id=user_id,
        email="test_delete@example.com",
        display_name="Test User",
    )
    service.repo.get_by_id = AsyncMock(return_value=dummy_user)
    service.repo.delete = AsyncMock()

    with patch("app.services.auth_service.get_redis_client", AsyncMock(return_value=AsyncMock())):
        result = await service.delete_account(user_id)

    assert "permanently deleted" in result["message"]
    service.repo.delete.assert_called_once_with(dummy_user)
    mock_db.commit.assert_called_once()
