"""Test HelloSafe Atlas live sandbox API with real credentials and complete the 10-quote checklist."""
import asyncio
import sys
import time

from app.services.providers import atlas, config, base


async def main():
    print("Testing HelloSafe Atlas Sandbox Integration...")
    # Inject user's sandbox credentials into provider config
    key_id = "ak_test_470d1308358faebf04"
    secret = "sk_test_a8198328e4a05461967b3565aa7749ddc19ef0c3d3661fba"

    config._config[config.ATLAS_KEY_ID] = key_id
    config._config[config.ATLAS_SIGNING_SECRET] = secret
    config._config_at = time.time() + 999999

    base._circuit_open.pop("atlas", None)
    base._failure_streak["atlas"] = 0

    # 10 diverse test destinations
    destinations = [
        ("FR", "TH", "2026-10-10", "2026-10-20", False),
        ("US", "JP", "2026-11-01", "2026-11-15", False),
        ("AE", "IT", "2026-10-25", "2026-11-05", True),   # Schengen visa intent
        ("GB", "ES", "2026-12-10", "2026-12-22", False),
        ("CA", "FR", "2026-11-10", "2026-11-20", False),
        ("FR", "US", "2026-10-15", "2026-10-25", False),
        ("US", "MX", "2026-11-05", "2026-11-12", False),
        ("GB", "TH", "2026-10-18", "2026-10-28", False),
        ("DE", "US", "2026-12-01", "2026-12-14", False),
    ]

    successes = 0
    first_result = None

    for i, (orig, dest, s_date, e_date, visa) in enumerate(destinations, 1):
        print(f"\n[{i}/10] Quoting trip from {orig} to {dest} ({s_date} to {e_date}, visa={visa})...")
        try:
            res = await atlas.quote_and_mint(
                origin_country=orig,
                dest_country=dest,
                start_date=s_date,
                end_date=e_date,
                travelers=2,
                currency="USD",
                visa_needed=visa,
            )
            if res:
                successes += 1
                if not first_result:
                    first_result = res
                print(f"  -> SUCCESS! Offer ID: {res['offer_id']}, Insurer: {res['insurer']}, Price: {res['price']} {res['currency']}")
                print(f"  -> Tracked Link: {res['link']}")
            else:
                print("  -> FAILED: quote_and_mint returned None")
        except Exception as e:
            print(f"  -> EXCEPTION: {e}")

    print(f"\n==========================================")
    print(f"Total Successful Quotes & Links: {successes}/10")
    if first_result:
        print(f"Sample Live Result: {first_result}")
    print(f"==========================================")


if __name__ == "__main__":
    asyncio.run(main())
