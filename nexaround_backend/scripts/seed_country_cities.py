"""Seed common country main cities into the country_cities table.

Usage on VPS:
    python scripts/seed_country_cities.py
"""
import asyncio
import logging
from sqlalchemy import select
from app.core.database import async_session_maker
from app.models.country_city import CountryCity

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("seed_country_cities")

INITIAL_COUNTRIES = [
    {
        "country": "Angola",
        "country_code": "AO",
        "cities": [
            {"name": "Luanda", "place_id": "ChIJ2_yR9LrhPRkRZlQ6N1y8Fv4", "latitude": -8.839988, "longitude": 13.289437, "country_code": "AO"},
            {"name": "Benguela", "place_id": "ChIJq0N34XzXOBkRz9w-G4-k98U", "latitude": -12.576274, "longitude": 13.405471, "country_code": "AO"},
            {"name": "Lobito", "place_id": "ChIJ546FvW3LOBkRVXj7y3q85r0", "latitude": -12.364402, "longitude": 13.536014, "country_code": "AO"},
            {"name": "Huambo", "place_id": "ChIJj99v9y_LOhkR7WqGk3eY0wM", "latitude": -12.776111, "longitude": 15.739167, "country_code": "AO"},
            {"name": "Lubango", "place_id": "ChIJr384o6rSPBkRk9dZ7rE-Fmg", "latitude": -14.917169, "longitude": 13.492500, "country_code": "AO"},
            {"name": "Cabinda", "place_id": "ChIJQ0xL506jGBkR476gL1g64-g", "latitude": -5.556667, "longitude": 12.200000, "country_code": "AO"},
            {"name": "Malanje", "place_id": "ChIJb_l2z_zOOhkRc63p1g_bB5w", "latitude": -9.540181, "longitude": 16.340989, "country_code": "AO"},
            {"name": "Soyo", "place_id": "ChIJk5V78yqDGBkRMvG8p3oH6_8", "latitude": -6.133333, "longitude": 12.366667, "country_code": "AO"},
        ],
    },
    {
        "country": "Sri Lanka",
        "country_code": "LK",
        "cities": [
            {"name": "Colombo", "place_id": "ChIJA3B6Dzk-4joRjhL7NOCiocs", "latitude": 6.927079, "longitude": 79.861243, "country_code": "LK"},
            {"name": "Kandy", "place_id": "ChIJwZ9hU_K_4zoRBZlOec-3s-M", "latitude": 7.290572, "longitude": 80.633726, "country_code": "LK"},
            {"name": "Galle", "place_id": "ChIJl9uQ4K3q4ToR8jX_q4H700A", "latitude": 6.053519, "longitude": 80.220977, "country_code": "LK"},
            {"name": "Ella", "place_id": "ChIJj_tP3w244zoRh3BfUuQ4y8c", "latitude": 6.866699, "longitude": 81.046554, "country_code": "LK"},
            {"name": "Sigiriya", "place_id": "ChIJzWv4g9Gk5DoRkR3f56M6rW0", "latitude": 7.957022, "longitude": 80.760298, "country_code": "LK"},
            {"name": "Nuwara Eliya", "place_id": "ChIJ7Y0M_J654zoRo7T72V1h18E", "latitude": 6.949717, "longitude": 80.789107, "country_code": "LK"},
            {"name": "Mirissa", "place_id": "ChIJp29x3_Ln4ToRgXwA_R_Kq_8", "latitude": 5.948261, "longitude": 80.471587, "country_code": "LK"},
            {"name": "Jaffna", "place_id": "ChIJ5_qZpS769ToRNz4L5t3m08o", "latitude": 9.661498, "longitude": 80.025543, "country_code": "LK"},
        ],
    },
    {
        "country": "United Arab Emirates",
        "country_code": "AE",
        "cities": [
            {"name": "Dubai", "place_id": "ChIJRcbKdAKgXz4RtRPraxAvys8", "latitude": 25.204849, "longitude": 55.270783, "country_code": "AE"},
            {"name": "Abu Dhabi", "place_id": "ChIJ7cmZVdlnXj4R5EBqR9j5w_A", "latitude": 24.453884, "longitude": 54.377344, "country_code": "AE"},
            {"name": "Sharjah", "place_id": "ChIJy-T1N_zTXj4R0n_v87r8z5U", "latitude": 25.346255, "longitude": 55.420932, "country_code": "AE"},
            {"name": "Ras Al Khaimah", "place_id": "ChIJmZ9wJ-fIXj4RL5lC9V9f77c", "latitude": 25.674143, "longitude": 55.980415, "country_code": "AE"},
            {"name": "Fujairah", "place_id": "ChIJG72Zq4PXXj4R9Xg_G6q9_10", "latitude": 25.128810, "longitude": 56.326485, "country_code": "AE"},
            {"name": "Ajman", "place_id": "ChIJF8yZ6fnPXj4RhHk4A7L2z5Y", "latitude": 25.405217, "longitude": 55.513643, "country_code": "AE"},
            {"name": "Al Ain", "place_id": "ChIJY5M1Pqf_Xj4R-a5k1T1894U", "latitude": 24.207500, "longitude": 55.744722, "country_code": "AE"},
        ],
    },
]


async def seed() -> None:
    async with async_session_maker() as session:
        for item in INITIAL_COUNTRIES:
            cc = item["country_code"]
            stmt = select(CountryCity).where(CountryCity.country_code == cc)
            res = await session.execute(stmt)
            existing = res.scalars().first()
            if existing:
                existing.cities = item["cities"]
                existing.country = item["country"]
                logger.info(f"Updated {item['country']} ({cc}) with {len(item['cities'])} cities.")
            else:
                session.add(
                    CountryCity(
                        country=item["country"],
                        country_code=cc,
                        cities=item["cities"],
                    )
                )
                logger.info(f"Seeded {item['country']} ({cc}) with {len(item['cities'])} cities.")
        await session.commit()
    logger.info("Done seeding country cities!")


if __name__ == "__main__":
    asyncio.run(seed())
