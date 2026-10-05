"""Direct test runner for Atlas unit and mock tests."""
import asyncio
import sys

from tests import test_atlas


async def run_all():
    print("Running Atlas Test Suite...")

    print("1. Testing Atlas signature generation...")
    test_atlas.test_atlas_signature_generation()
    print("   -> PASSED")

    print("2. Testing Atlas link recognition...")
    test_atlas.test_atlas_link_recognition()
    print("   -> PASSED")

    print("3. Testing Atlas plan item formatting (visa vs non-visa)...")
    test_atlas.test_atlas_plan_item_formatting()
    print("   -> PASSED")

    print("4. Testing Atlas quote and mint flow (mock HTTP transport)...")
    class MonkeyPatch:
        def setattr(self, target, name, value):
            setattr(target, name, value)

    mp = MonkeyPatch()
    await test_atlas.test_quote_and_mint_picks_cheapest_offer(mp)
    print("   -> PASSED")

    print("5. Testing Shadow mode (records audit, leaves plan untouched)...")
    test_atlas.test_shadow_mode_records_and_changes_nothing()
    print("   -> PASSED")

    print("6. Testing Live mode (injects priced row into booking_plan and safety pill)...")
    test_atlas.test_live_mode_applies_booking_row_and_safety_pill()
    print("   -> PASSED")

    print("\nALL 6 TEST SUITES PASSED SUCCESSFULLY!")


if __name__ == "__main__":
    asyncio.run(run_all())
