"""
Seed script to load the list of 63 Top World Museums.
This populates the `museums` table with the basic data provided by the client.
"""

import asyncio
import os
import sys
import uuid

# ── Bootstrap the app so models / settings are importable ────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.core.database import engine, async_session, Base  # noqa: E402
from app.models.museum import Museum  # noqa: E402
from sqlalchemy import select

MUSEUMS_DATA = [
    {"rank": 1, "name": "Louvre", "visitors": 9046000, "city": "Paris", "country": "France", "slug": "louvre"},
    {"rank": 2, "name": "National Museum of China", "visitors": 6956800, "city": "Beijing", "country": "China", "slug": "national-museum-of-china"},
    {"rank": 3, "name": "Vatican Museums", "visitors": 6933822, "city": "Vatican City", "country": "Vatican", "slug": "vatican-museums"},
    {"rank": 4, "name": "Grand Egyptian Museum", "visitors": 6805000, "city": "Giza", "country": "Egypt", "slug": "grand-egyptian-museum"},
    {"rank": 5, "name": "National Museum of Korea", "visitors": 6505483, "city": "Seoul", "country": "South Korea", "slug": "national-museum-of-korea"},
    {"rank": 6, "name": "British Museum", "visitors": 6440120, "city": "London", "country": "United Kingdom", "slug": "british-museum"},
    {"rank": 7, "name": "China Science and Technology Museum", "visitors": 6421000, "city": "Beijing", "country": "China", "slug": "china-science-and-technology-museum"},
    {"rank": 8, "name": "Natural History Museum, South Kensington", "visitors": 7116929, "city": "London", "country": "United Kingdom", "slug": "natural-history-museum-south-kensington"},
    {"rank": 9, "name": "Metropolitan Museum of Art", "visitors": 5984091, "city": "New York City", "country": "United States", "slug": "metropolitan-museum-of-art"},
    {"rank": 10, "name": "Nanjing Museum", "visitors": 5680000, "city": "Nanjing", "country": "China", "slug": "nanjing-museum"},
    {"rank": 11, "name": "American Museum of Natural History", "visitors": 5400000, "city": "New York City", "country": "United States", "slug": "american-museum-of-natural-history"},
    {"rank": 12, "name": "Tate Modern", "visitors": 4514266, "city": "London", "country": "United Kingdom", "slug": "tate-modern"},
    {"rank": 13, "name": "Hubei Provincial Museum", "visitors": 4356943, "city": "Wuhan", "country": "China", "slug": "hubei-provincial-museum"},
    {"rank": 15, "name": "National Gallery of Art", "visitors": 3936543, "city": "Washington, D.C.", "country": "United States", "slug": "national-gallery-of-art"},
    {"rank": 16, "name": "Musée d'Orsay", "visitors": 3751000, "city": "Paris", "country": "France", "slug": "musee-dorsay", "image_url": "/static/photo_cache/musee_dorsay.jpg"},
    {"rank": 17, "name": "National Museum of Anthropology", "visitors": 3700000, "city": "Mexico City", "country": "Mexico", "slug": "national-museum-of-anthropology"},
    {"rank": 18, "name": "State Russian Museum", "visitors": 5087276, "city": "Saint Petersburg", "country": "Russia", "slug": "state-russian-museum"},
    # Skip 19 (State Hermitage Museum) as it is already seeded with full details
    {"rank": 20, "name": "Victoria and Albert Museum", "visitors": 3332300, "city": "London", "country": "United Kingdom", "slug": "victoria-and-albert-museum"},
    {"rank": 21, "name": "Prado Museum", "visitors": 3457057, "city": "Madrid", "country": "Spain", "slug": "prado-museum"},
    {"rank": 22, "name": "Centre Pompidou", "visitors": 3204369, "city": "Paris", "country": "France", "slug": "centre-pompidou"},
    {"rank": 23, "name": "National Gallery", "visitors": 3203451, "city": "London", "country": "United Kingdom", "slug": "national-gallery"},
    {"rank": 24, "name": "Musée National d'Histoire Naturelle", "visitors": 3200000, "city": "Paris", "country": "France", "slug": "musee-national-dhistoire-naturelle"},
    {"rank": 25, "name": "National Air and Space Museum", "visitors": 3100000, "city": "Washington, D.C.", "country": "United States", "slug": "national-air-and-space-museum"},
    {"rank": 26, "name": "Mevlana Museum", "visitors": 3048000, "city": "Konya", "country": "Türkiye", "slug": "mevlana-museum"},
    {"rank": 27, "name": "National Museum of Natural History", "visitors": 3000000, "city": "Washington, D.C.", "country": "United States", "slug": "national-museum-of-natural-history"},
    {"rank": 28, "name": "Galleria degli Uffizi", "visitors": 2908828, "city": "Florence", "country": "Italy", "slug": "galleria-degli-uffizi"},
    {"rank": 29, "name": "National Museum of Natural Science", "visitors": 2854455, "city": "Taichung", "country": "Taiwan", "slug": "national-museum-of-natural-science"},
    {"rank": 30, "name": "Science Museum", "visitors": 2827242, "city": "London", "country": "United Kingdom", "slug": "science-museum"},
    {"rank": 31, "name": "Museum of Modern Art (MoMA)", "visitors": 2657377, "city": "New York City", "country": "United States", "slug": "museum-of-modern-art"},
    {"rank": 32, "name": "National Museum of Nature and Science", "visitors": 2634997, "city": "Tokyo", "country": "Japan", "slug": "national-museum-of-nature-and-science"},
    {"rank": 33, "name": "M+", "visitors": 2610000, "city": "Hong Kong", "country": "Hong Kong", "slug": "m-plus"},
    {"rank": 34, "name": "State Tretyakov Gallery", "visitors": 3075976, "city": "Moscow", "country": "Russia", "slug": "state-tretyakov-gallery"},
    {"rank": 35, "name": "Rijksmuseum", "visitors": 2500000, "city": "Amsterdam", "country": "Netherlands", "slug": "rijksmuseum"},
    {"rank": 36, "name": "Tokyo National Museum", "visitors": 2600000, "city": "Tokyo", "country": "Japan", "slug": "tokyo-national-museum"},
    {"rank": 37, "name": "Art Gallery of New South Wales", "visitors": 2400000, "city": "Sydney", "country": "Australia", "slug": "art-gallery-of-new-south-wales"},
    {"rank": 38, "name": "National Museum of Scotland", "visitors": 2314974, "city": "Edinburgh", "country": "United Kingdom", "slug": "national-museum-of-scotland"},
    {"rank": 39, "name": "Royal Museums Greenwich", "visitors": 2255753, "city": "London", "country": "United Kingdom", "slug": "royal-museums-greenwich"},
    {"rank": 40, "name": "Galleria dell'Accademia", "visitors": 2189103, "city": "Florence", "country": "Italy", "slug": "galleria-dellaccademia"},
    {"rank": 41, "name": "Smithsonian Museum of American History", "visitors": 2100000, "city": "Washington, D.C.", "country": "United States", "slug": "smithsonian-museum-of-american-history"},
    {"rank": 42, "name": "National Gallery Singapore", "visitors": 2040481, "city": "Singapore", "country": "Singapore", "slug": "national-gallery-singapore"},
    {"rank": 45, "name": "National Palace Museum", "visitors": 1874994, "city": "Taipei", "country": "Taiwan", "slug": "national-palace-museum"},
    {"rank": 47, "name": "Van Gogh Museum", "visitors": 1840000, "city": "Amsterdam", "country": "Netherlands", "slug": "van-gogh-museum"},
    {"rank": 48, "name": "The National Art Center, Tokyo", "visitors": 1755036, "city": "Tokyo", "country": "Japan", "slug": "the-national-art-center-tokyo"},
    {"rank": 49, "name": "California Science Center", "visitors": 1694000, "city": "Los Angeles", "country": "United States", "slug": "california-science-center"},
    {"rank": 51, "name": "Kunsthistorisches Museum", "visitors": 1688509, "city": "Vienna", "country": "Austria", "slug": "kunsthistorisches-museum"},
    {"rank": 54, "name": "National Gallery of Victoria", "visitors": 1580303, "city": "Melbourne", "country": "Australia", "slug": "national-gallery-of-victoria"},
    {"rank": 55, "name": "National Museum in Warsaw", "visitors": 1500655, "city": "Warsaw", "country": "Poland", "slug": "national-museum-in-warsaw"},
    {"rank": 58, "name": "Acropolis Museum", "visitors": 1451727, "city": "Athens", "country": "Greece", "slug": "acropolis-museum"},
    {"rank": 59, "name": "Centro Cultural Banco do Brasil", "visitors": 1364208, "city": "São Paulo", "country": "Brazil", "slug": "centro-cultural-banco-do-brasil"},
    {"rank": 61, "name": "Guggenheim Museum Bilbao", "visitors": 1301343, "city": "Bilbao", "country": "Spain", "slug": "guggenheim-museum-bilbao"},
    {"rank": 63, "name": "Moscow Kremlin Museum", "visitors": 1240113, "city": "Moscow", "country": "Russia", "slug": "moscow-kremlin-museum"}
]

async def seed():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as session:
        count = 0
        for m_data in MUSEUMS_DATA:
            result = await session.execute(
                select(Museum).where(Museum.slug == m_data["slug"])
            )
            museum = result.scalar_one_or_none()
            
            if museum is None:
                museum = Museum(
                    id=uuid.uuid4(),
                    slug=m_data["slug"],
                    name=m_data["name"],
                    city=m_data["city"],
                    country=m_data["country"],
                    annual_visitors=m_data["visitors"],
                    rank=m_data["rank"],
                    image_url=m_data.get("image_url")
                )
                session.add(museum)
                count += 1
                print(f"Added: {museum.name}")
            elif m_data.get("image_url"):
                museum.image_url = m_data["image_url"]
        
        await session.commit()
        print(f"✅ Inserted {count} additional museums!")

if __name__ == "__main__":
    asyncio.run(seed())
