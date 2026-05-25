import uuid
from typing import Dict
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.system_setting import SystemSetting, ApiRequestLog

class SettingsService:
    # Class-level cache to share across all service instances
    _cache: Dict[str, str] = {}

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_setting(self, key: str, default: str = "") -> str:
        """Get a setting by key, loading cache if empty."""
        if not SettingsService._cache:
            await self.load_settings()
        return SettingsService._cache.get(key, default)

    async def load_settings(self) -> Dict[str, str]:
        """Fetch all settings from DB and update the class cache."""
        result = await self.db.execute(select(SystemSetting))
        settings = result.scalars().all()
        SettingsService._cache = {s.key: s.value for s in settings}
        return SettingsService._cache

    async def set_setting(self, key: str, value: str, description: str = None) -> SystemSetting:
        """Create or update a system setting."""
        stmt = select(SystemSetting).where(SystemSetting.key == key)
        result = await self.db.execute(stmt)
        setting = result.scalar_one_or_none()

        if not setting:
            setting = SystemSetting(key=key, value=value, description=description)
            self.db.add(setting)
        else:
            setting.value = value
            if description is not None:
                setting.description = description
            setting.updated_at = datetime.now(timezone.utc)

        await self.db.commit()
        SettingsService._cache[key] = value
        return setting

    async def log_api_request(self, api_name: str, endpoint: str, user_id: uuid.UUID = None):
        """Log a request to a third-party API."""
        log = ApiRequestLog(api_name=api_name, endpoint=endpoint, user_id=user_id)
        self.db.add(log)
        await self.db.commit()
