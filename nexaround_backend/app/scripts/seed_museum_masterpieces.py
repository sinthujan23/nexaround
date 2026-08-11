"""
Master seed runner for all museum itineraries and masterpieces.
Runs all individual museum seeders in sequence.

Usage (from backend root or inside VPS Docker container):
    python -m app.scripts.seed_museum_masterpieces
"""

import asyncio
import os
import sys

# Bootstrap app
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.scripts.seed_anthropology import seed as seed_anthropology
from app.scripts.seed_van_gogh import seed as seed_van_gogh

async def main():
    print("==================================================")
    print("      NEXAROUND MUSEUM MASTERPIECE SEEDER        ")
    print("==================================================")

    print("\n--- [1/2] Seeding National Museum of Anthropology ---")
    try:
        await seed_anthropology()
    except Exception as e:
        print(f"[ERROR] Anthropology seeding failed: {e}")

    print("\n--- [2/2] Seeding Van Gogh Museum ---")
    try:
        await seed_van_gogh()
    except Exception as e:
        print(f"[ERROR] Van Gogh seeding failed: {e}")

    print("\n==================================================")
    print("           [SUCCESS] All Seeding Complete!        ")
    print("==================================================")

if __name__ == "__main__":
    asyncio.run(main())
