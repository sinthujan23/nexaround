import asyncio
import uuid
from sqlalchemy import select
from app.core.database import async_session
from app.models.attraction import Attraction
from app.models.category import Category
from app.utils.geo_utils import create_point

# Attractions near Trincomalee, Sri Lanka (lat ~8.57, lng ~81.23)
# and also Colombo area for broader coverage
ATTRACTIONS = [
    # --- Trincomalee Area ---
    {
        "name": "Koneswaram Temple",
        "description": "An ancient Hindu temple perched on Swami Rock cliff overlooking the Indian Ocean. One of the five Ishwarams of Lord Shiva in Sri Lanka.",
        "latitude": 8.5764,
        "longitude": 81.2330,
        "address": "Fort Frederick, Trincomalee",
        "rating": 4.7,
        "review_count": 1250,
        "category_name": "Attractions",
        "photo_urls": ["https://upload.wikimedia.org/wikipedia/commons/thumb/a/a3/Koneswaram_Temple.jpg/1200px-Koneswaram_Temple.jpg"],
        "tags": ["temple", "hindu", "heritage", "viewpoint"],
        "entry_fee": 0.0,
    },
    {
        "name": "Fort Frederick",
        "description": "A Portuguese-built fort from the 17th century, later expanded by the Dutch and British. Houses the Koneswaram Temple within its walls.",
        "latitude": 8.5751,
        "longitude": 81.2318,
        "address": "Fort Frederick Road, Trincomalee",
        "rating": 4.3,
        "review_count": 820,
        "category_name": "Attractions",
        "photo_urls": ["https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Fort_Frederick_Trincomalee.jpg/800px-Fort_Frederick_Trincomalee.jpg"],
        "tags": ["fort", "history", "colonial", "architecture"],
        "entry_fee": 0.0,
    },
    {
        "name": "Nilaveli Beach",
        "description": "A pristine white sand beach stretching for miles along the northeast coast. Perfect for swimming, snorkeling, and whale watching.",
        "latitude": 8.6816,
        "longitude": 81.1954,
        "address": "Nilaveli, Trincomalee District",
        "rating": 4.8,
        "review_count": 2100,
        "category_name": "Attractions",
        "photo_urls": ["https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/Nilaveli_Beach.jpg/800px-Nilaveli_Beach.jpg"],
        "tags": ["beach", "swimming", "snorkeling", "nature"],
        "entry_fee": 0.0,
    },
    {
        "name": "Marble Beach",
        "description": "A beautiful beach with calm waters, ideal for families. Named for the smooth marble-like pebbles found along the shore.",
        "latitude": 8.5420,
        "longitude": 81.2280,
        "address": "Marble Beach Road, Trincomalee",
        "rating": 4.4,
        "review_count": 650,
        "category_name": "Attractions",
        "photo_urls": ["https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Marble_Beach_Trincomalee.jpg/800px-Marble_Beach_Trincomalee.jpg"],
        "tags": ["beach", "family", "swimming", "relaxation"],
        "entry_fee": 200.0,
        "currency": "LKR",
    },
    {
        "name": "Pigeon Island",
        "description": "A national park and coral reef sanctuary just off Nilaveli Beach. Home to rock pigeons, sea turtles, and vibrant coral reefs.",
        "latitude": 8.7055,
        "longitude": 81.1970,
        "address": "Off Nilaveli Beach, Trincomalee",
        "rating": 4.6,
        "review_count": 1800,
        "category_name": "Attractions",
        "photo_urls": ["https://upload.wikimedia.org/wikipedia/commons/thumb/c/c7/Pigeon_Island_Sri_Lanka.jpg/800px-Pigeon_Island_Sri_Lanka.jpg"],
        "tags": ["island", "snorkeling", "wildlife", "coral reef"],
        "entry_fee": 2000.0,
        "currency": "LKR",
    },
    {
        "name": "Trinco Blu by Cinnamon",
        "description": "A premium beachfront resort offering luxurious rooms, an infinity pool, and direct access to Uppuveli Beach.",
        "latitude": 8.6040,
        "longitude": 81.2170,
        "address": "Uppuveli Beach, Trincomalee",
        "rating": 4.5,
        "review_count": 900,
        "category_name": "Hotels",
        "photo_urls": ["https://images.unsplash.com/photo-1566073771259-6a8506099945?q=80&w=600"],
        "tags": ["resort", "luxury", "beachfront", "pool"],
        "entry_fee": 0.0,
    },
    {
        "name": "Amaranthe Bay Resort",
        "description": "A boutique resort nestled along the shores of Trincomalee offering a serene tropical getaway with modern amenities.",
        "latitude": 8.6200,
        "longitude": 81.2110,
        "address": "Uppuveli, Trincomalee",
        "rating": 4.4,
        "review_count": 560,
        "category_name": "Hotels",
        "photo_urls": ["https://images.unsplash.com/photo-1582719508461-905c673771fd?q=80&w=600"],
        "tags": ["resort", "boutique", "beachside", "spa"],
        "entry_fee": 0.0,
    },
    {
        "name": "Crab Restaurant Trincomalee",
        "description": "A local favorite serving fresh seafood and traditional Sri Lankan cuisine right by the harbor.",
        "latitude": 8.5680,
        "longitude": 81.2290,
        "address": "Harbour Road, Trincomalee",
        "rating": 4.2,
        "review_count": 340,
        "category_name": "Food & Drink",
        "photo_urls": ["https://images.unsplash.com/photo-1559339352-11d035aa65de?q=80&w=600"],
        "tags": ["seafood", "local cuisine", "restaurant", "harbor"],
        "entry_fee": 0.0,
    },
    {
        "name": "Dutch Bay Beach Cafe",
        "description": "A relaxed beachside cafe serving fresh juices, Sri Lankan rice & curry, and Western comfort food with ocean views.",
        "latitude": 8.5710,
        "longitude": 81.2250,
        "address": "Dutch Bay, Trincomalee",
        "rating": 4.1,
        "review_count": 210,
        "category_name": "Food & Drink",
        "photo_urls": ["https://images.unsplash.com/photo-1551218808-94e220e084d2?q=80&w=600"],
        "tags": ["cafe", "beachside", "sri lankan food", "juices"],
        "entry_fee": 0.0,
    },
    {
        "name": "Whale Watching Trincomalee",
        "description": "Experience the thrill of watching blue whales and sperm whales in their natural habitat off the coast of Trincomalee.",
        "latitude": 8.5900,
        "longitude": 81.2350,
        "address": "Trincomalee Harbor",
        "rating": 4.7,
        "review_count": 1100,
        "category_name": "Experiences",
        "photo_urls": ["https://images.unsplash.com/photo-1559827260-dc66d52bef19?q=80&w=600"],
        "tags": ["whale watching", "adventure", "ocean", "wildlife"],
        "entry_fee": 5000.0,
        "currency": "LKR",
    },
    {
        "name": "Trincomalee War Cemetery",
        "description": "A beautifully maintained Commonwealth War Cemetery honoring soldiers from WWII. A quiet and reflective space.",
        "latitude": 8.5580,
        "longitude": 81.2130,
        "address": "Trincomalee",
        "rating": 4.3,
        "review_count": 420,
        "category_name": "Attractions",
        "photo_urls": ["https://images.unsplash.com/photo-1596401057633-54a921f09871?q=80&w=600"],
        "tags": ["history", "memorial", "WWII", "peaceful"],
        "entry_fee": 0.0,
    },
    {
        "name": "Uppuveli Beach",
        "description": "A beautiful golden-sand beach with gentle waves, popular for both tourists and locals. Excellent for surfing and sunbathing.",
        "latitude": 8.6110,
        "longitude": 81.2190,
        "address": "Uppuveli, Trincomalee",
        "rating": 4.5,
        "review_count": 1500,
        "category_name": "Attractions",
        "photo_urls": ["https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=600"],
        "tags": ["beach", "surfing", "sunset", "swimming"],
        "entry_fee": 0.0,
    },
    # --- Batticaloa Area (nearby) ---
    {
        "name": "Batticaloa Lagoon",
        "description": "A vast coastal lagoon known for its singing fish phenomenon and stunning sunset views.",
        "latitude": 7.7310,
        "longitude": 81.6930,
        "address": "Batticaloa",
        "rating": 4.2,
        "review_count": 380,
        "category_name": "Attractions",
        "photo_urls": ["https://images.unsplash.com/photo-1468581264429-2548ef9eb732?q=80&w=600"],
        "tags": ["lagoon", "sunset", "nature", "singing fish"],
        "entry_fee": 0.0,
    },
    {
        "name": "Passikudah Beach",
        "description": "One of the most stunning beaches in Sri Lanka with shallow, crystal-clear waters stretching over a kilometer.",
        "latitude": 7.9320,
        "longitude": 81.5600,
        "address": "Passikudah, Batticaloa District",
        "rating": 4.7,
        "review_count": 1600,
        "category_name": "Attractions",
        "photo_urls": ["https://images.unsplash.com/photo-1519046904884-53103b34b206?q=80&w=600"],
        "tags": ["beach", "swimming", "crystal clear", "family"],
        "entry_fee": 0.0,
    },
    # --- Nearby Trincomalee Dining ---
    {
        "name": "Fernando's Restaurant",
        "description": "Popular family restaurant in inner Trincomalee serving Sri Lankan rice and curry, kottu roti, and fresh seafood.",
        "latitude": 8.5720,
        "longitude": 81.2190,
        "address": "Main Street, Trincomalee",
        "rating": 4.0,
        "review_count": 280,
        "category_name": "Food & Drink",
        "photo_urls": ["https://images.unsplash.com/photo-1555396273-367ea4eb4db5?q=80&w=600"],
        "tags": ["sri lankan food", "family", "rice and curry", "kottu"],
        "entry_fee": 0.0,
    },
]


async def seed_attractions():
    print("Seeding attractions...")
    async with async_session() as session:
        # First, get category map
        result = await session.execute(select(Category))
        categories = result.scalars().all()
        category_map = {cat.name: cat.id for cat in categories}
        print(f"Found categories: {list(category_map.keys())}")

        for attr_data in ATTRACTIONS:
            # Check if exists
            result = await session.execute(
                select(Attraction).where(Attraction.name == attr_data["name"])
            )
            existing = result.scalar_one_or_none()

            if existing:
                print(f"  Already exists: {attr_data['name']}")
                continue

            cat_name = attr_data.pop("category_name", None)
            category_id = category_map.get(cat_name) if cat_name else None

            lat = attr_data.pop("latitude")
            lng = attr_data.pop("longitude")

            attraction = Attraction(
                name=attr_data["name"],
                description=attr_data.get("description"),
                location=create_point(lat, lng),
                category_id=category_id,
                address=attr_data.get("address"),
                rating=attr_data.get("rating", 0.0),
                review_count=attr_data.get("review_count", 0),
                photo_urls=attr_data.get("photo_urls", []),
                tags=attr_data.get("tags", []),
                entry_fee=attr_data.get("entry_fee", 0.0),
                currency=attr_data.get("currency", "USD"),
            )
            session.add(attraction)
            print(f"  [OK] Added: {attr_data['name']}")

        await session.commit()
    print("[DONE] Attraction seeding complete!")


if __name__ == "__main__":
    asyncio.run(seed_attractions())
