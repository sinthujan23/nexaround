import asyncio
import uuid
from sqlalchemy import select
from app.core.database import async_session
from app.models.category import Category

# The first six are the sections Around You and Discovery show, in the order
# they appear there. The rest are older vocabulary that rows are still filed
# under and that other surfaces (AR mode, Hotels) still request by name.
CATEGORIES = [
    {"name": "POI", "icon": "place", "color": "#00BFA5", "sort_order": 1},
    {"name": "Nature", "icon": "park", "color": "#2E7D32", "sort_order": 2},
    {"name": "Food & Drink", "icon": "restaurant", "color": "#4CAF50", "sort_order": 3},
    {"name": "Shopping", "icon": "shopping_bag", "color": "#E91E63", "sort_order": 4},
    {"name": "Medical", "icon": "local_pharmacy", "color": "#EF5350", "sort_order": 5},
    {"name": "Hospital", "icon": "local_hospital", "color": "#C62828", "sort_order": 6},
    {"name": "Attractions", "icon": "place", "color": "#FF5722", "sort_order": 7},
    {"name": "Beach", "icon": "beach_access", "color": "#0097A7", "sort_order": 8},
    {"name": "Hotels", "icon": "hotel", "color": "#2196F3", "sort_order": 9},
    {"name": "Experiences", "icon": "explore", "color": "#9C27B0", "sort_order": 10},
    {"name": "Transport", "icon": "directions_bus", "color": "#607D8B", "sort_order": 11},
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
