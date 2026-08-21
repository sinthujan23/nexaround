"""Load a museum's itinerary spreadsheet into the database.

    python -m app.scripts.import_museum_itinerary --slug acropolis-museum \
        --xlsx /path/to/Acropolis_Museum_Itineraries_with_Locations.xlsx

    # see what would change without touching anything
    python -m app.scripts.import_museum_itinerary --slug acropolis-museum \
        --xlsx ... --dry-run

Replaces that museum's masterpieces outright rather than updating in place, so
the result matches the spreadsheet exactly and nothing survives from an earlier
run. The museum row itself — photo bytes, opening hours, ticket link — is left
alone, and other museums are never touched.

Every import verifies itself: each tour is read back out of the database and
compared to the sheet it came from, and a mismatch fails the run rather than
leaving a plausible-looking but wrong itinerary in place.
"""
import argparse
import asyncio
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from sqlalchemy import delete, select

from app.core.database import async_session
from app.models.museum import Museum, MuseumMasterpiece
from app.repositories.museum_repository import MuseumRepository
from app.services.museum_itinerary_import import (
    DURATIONS,
    ItineraryImportError,
    parse_sheets,
    read_workbook,
    summarise,
)


async def import_itinerary(slug: str, xlsx: str, dry_run: bool = False) -> int:
    if not os.path.exists(xlsx):
        print(f"❌ spreadsheet not found: {xlsx}")
        return 1

    sheets = read_workbook(xlsx)
    try:
        rows, warnings = parse_sheets(sheets)
    except ItineraryImportError as e:
        print(f"❌ {e}")
        return 1

    print(f"📖 {os.path.basename(xlsx)}")
    print(f"   sheets: {', '.join(sheets)}")
    print(f"   parsed: {summarise(rows)}")
    for warning in warnings:
        print(f"   ⚠️  {warning}")

    async with async_session() as session:
        museum = (
            await session.execute(select(Museum).where(Museum.slug == slug))
        ).scalar_one_or_none()
        if museum is None:
            print(f"❌ no museum with slug '{slug}'. Seed the museum first.")
            return 1

        existing = (
            await session.execute(
                select(MuseumMasterpiece).where(
                    MuseumMasterpiece.museum_id == museum.id
                )
            )
        ).scalars().all()
        print(f"🏛  {museum.name}: {len(existing)} rows in the database, "
              f"{len(rows)} in the spreadsheet")

        if dry_run:
            print("🔎 dry run — nothing written")
            _preview(rows)
            return 0

        await session.execute(
            delete(MuseumMasterpiece).where(
                MuseumMasterpiece.museum_id == museum.id
            )
        )
        for row in rows:
            session.add(MuseumMasterpiece(museum_id=museum.id, **row))
        await session.commit()
        print(f"✅ wrote {len(rows)} masterpieces")

    return await _verify(slug, sheets)


def _preview(rows: list[dict], count: int = 5) -> None:
    for row in rows[:count]:
        tours = ",".join(d for d in DURATIONS if row.get(f"included_{d}"))
        print(f"   rank {row['rank']:>3}  {row['must_see_item'][:40]:42s} [{tours}]")


async def _verify(slug: str, sheets: dict) -> int:
    """Read each tour back and compare it to the sheet it came from."""
    from app.services.museum_itinerary_import import duration_for_sheet

    problems = 0
    async with async_session() as session:
        for sheet_name, df in sheets.items():
            duration = duration_for_sheet(sheet_name)
            if duration is None:
                continue
            _, stored = await MuseumRepository.get_itinerary(session, slug, duration)
            got = [m.must_see_item.strip().lower() for m in stored]
            want = [" ".join(str(x).split()).strip().lower() for x in df["Exhibit"]]
            if got == want:
                print(f"   ✓ {duration}: {len(got)} stops, order matches '{sheet_name}'")
                continue
            problems += 1
            print(f"   ✗ {duration}: does NOT match '{sheet_name}' "
                  f"({len(got)} stored vs {len(want)} in sheet)")
            for i, (a, b) in enumerate(zip(got, want)):
                if a != b:
                    print(f"      first difference at stop {i + 1}: "
                          f"stored {a!r}, sheet says {b!r}")
                    break
    if problems:
        print(f"❌ {problems} tour(s) do not match the spreadsheet")
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slug", required=True, help="museum slug, e.g. acropolis-museum")
    parser.add_argument("--xlsx", required=True, help="path to the itinerary workbook")
    parser.add_argument("--dry-run", action="store_true",
                        help="parse and report without writing")
    args = parser.parse_args()
    return asyncio.run(import_itinerary(args.slug, args.xlsx, args.dry_run))


if __name__ == "__main__":
    raise SystemExit(main())
