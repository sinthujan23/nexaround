import asyncio
import uuid
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.core.config import settings
from app.models.user import User
from app.core.security import get_password_hash

async def seed_user():
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # User list
        users_to_seed = [
            {
                "email": "test@nexaround.com",
                "password": "password123",
                "display_name": "Nex Explorer"
            },
            {
                "email": "explorer@nexaround.com",
                "password": "nexaround2024",
                "display_name": "World Traveler"
            }
        ]

        for u in users_to_seed:
            # Check if exists
            result = await session.execute(select(User).where(User.email == u["email"]))
            existing_user = result.scalar_one_or_none()
            
            if existing_user:
                # Update password to ensure it matches what we expect
                existing_user.password_hash = get_password_hash(u["password"])
                existing_user.display_name = u["display_name"]
                print(f"Updated existing user: {u['email']}")
            else:
                new_user = User(
                    email=u["email"],
                    password_hash=get_password_hash(u["password"]),
                    display_name=u["display_name"],
                    is_active=True
                )
                session.add(new_user)
                print(f"Created new user: {u['email']}")
            
        await session.commit()
        print("Done!")

if __name__ == "__main__":
    asyncio.run(seed_user())
