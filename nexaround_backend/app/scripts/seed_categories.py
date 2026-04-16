import asyncio
import uuid
from sqlalchemy import select
from app.core.database import async_session
from app.models.category import Category

CATEGORIES = [
    {"name": "Attractions", "icon": "place", "color": "#FF5722", "sort_order": 1},
    {"name": "Food & Drink", "icon": "restaurant", "color": "#4CAF50", "sort_order": 2},
    {"name": "Hotels", "icon": "hotel", "color": "#2196F3", "sort_order": 3},
    {"name": "Shopping", "icon": "shopping_bag", "color": "#E91E63", "sort_order": 4},
    {"name": "Experiences", "icon": "explore", "color": "#9C27B0", "sort_order": 5},
    {"name": "Transport", "icon": "directions_bus", "color": "#607D8B", "sort_order": 6},
]

async def seed_categories():
    print("Seeding categories...")
    async with async_session() as session:
        for cat_data in CATEGORIES:
            # Check if exists
            result = await session.execute(
                select(Category).where(Category.name == cat_data["name"])
            )
            existing = result.scalar_one_or_none()
            
            if not existing:
                category = Category(**cat_data)
                session.add(category)
                print(f"Added category: {cat_data['name']}")
            else:
                print(f"Category already exists: {cat_data['name']}")
        
        await session.commit()
    print("Seeding complete.")

if __name__ == "__main__":
    asyncio.run(seed_categories())
