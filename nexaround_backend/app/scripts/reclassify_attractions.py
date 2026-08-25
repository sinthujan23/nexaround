"""One-off backfill: correct attractions.category_id where it disagrees with
the place's own Google tags.

Targets exactly the bug behind the mosque-under-Nature / district-name-as-
Nature symptoms: a row whose category was stamped as whatever section a
search happened to be fetching (see google_places_client.to_place_dict's
prior behaviour), rather than derived from the place's own types. The live
read path (place_bands.is_relevant) already re-derives category membership
from tags on every request and would not resurface a row like this under the
wrong section — but the Flutter client's place_sections.dart mirror used to
trust the stored category name as a fallback signal, which is what let these
rows actually show up in the wrong tab. That fallback is now gated behind
"no informative tags" (place_sections.dart), so this script is what actually
gets the wrong labels out of the database rather than just working around
them at render time.

Scope: only rows whose CURRENT category is exactly one of the six canonical
section names (POI, Nature, Shopping, Medical, Hospital, Food & Drink) are
considered. Rows filed under a legacy alias (Attractions, Experiences, Point
of Interest, Beach) are left untouched — those already feed into a shared
pool via place_bands.CATEGORY_DB_ALIASES and are re-derived by tags at read
time regardless of that name, so touching them isn't part of this fix and
would just be a large, unnecessary rewrite of long-settled data.
Rows with no informative tags (nothing but generic placeholders, or none at
all) are also left untouched — there is nothing to judge them by besides the
name they already have, same principle as the client-side fix.

Usage:
    python -m app.scripts.reclassify_attractions            # dry run (default)
    python -m app.scripts.reclassify_attractions --apply    # write the changes
"""
import argparse
import asyncio

from sqlalchemy import select

from app.core.database import async_session
from app.models.attraction import Attraction
from app.models.category import Category
from app.services import place_bands

# The six sections the app actually shows today. A row filed under a legacy
# alias (Attractions, Experiences, Point of Interest, Beach) is out of scope —
# see module docstring.
_CANONICAL_SECTIONS = ["Hospital", "Medical", "POI", "Nature", "Shopping", "Food & Drink"]

_GENERIC_TAGS = {"point_of_interest", "establishment", "premise", "geocode"}


def _informative_tags(tags: list) -> list:
    return [t for t in (tags or []) if str(t).lower() not in _GENERIC_TAGS]


def _best_canonical_category(tags: list, name: str) -> str | None:
    """Which canonical section (if any) this place's own tags support.

    Checked in a fixed order so a place matching more than one — rare, given
    place_bands' exclusive-pair logic already resolves POI/Nature and
    Hospital/Medical against each other — is assigned deterministically
    rather than arbitrarily.
    """
    for candidate in _CANONICAL_SECTIONS:
        if place_bands.is_relevant(candidate, tags, name):
            return candidate
    return None


async def main(apply: bool) -> int:
    async with async_session() as session:
        categories = {
            c.id: c.name
            for c in (await session.execute(select(Category))).scalars().all()
        }
        name_to_id = {name: cid for cid, name in categories.items()}

        attractions = (
            (await session.execute(select(Attraction))).scalars().all()
        )

        changes = []
        for attr in attractions:
            current_name = categories.get(attr.category_id)
            if current_name not in _CANONICAL_SECTIONS:
                continue  # legacy alias or uncategorized — out of scope

            if not _informative_tags(attr.tags):
                continue  # nothing to judge by besides the name it already has

            if place_bands.is_relevant(current_name, attr.tags, attr.name):
                continue  # still a legitimate fit for its own stored category

            new_name = _best_canonical_category(attr.tags, attr.name)
            if not new_name or new_name == current_name:
                continue  # nothing confidently better to move it to

            changes.append((attr, current_name, new_name))

        print(
            f"Scanned {len(attractions)} attractions; "
            f"{len(changes)} disagree with their stored category.\n"
        )
        for attr, old, new in changes:
            print(f"  {attr.name!r:50s} {old:12s} -> {new:12s}  tags={attr.tags}")

        if not changes:
            print("\nNothing to change.")
            return 0

        if not apply:
            print(
                f"\nDry run — {len(changes)} row(s) would change. "
                "Re-run with --apply to write them."
            )
            return 0

        for attr, old, new in changes:
            new_id = name_to_id.get(new)
            if new_id is None:
                new_cat = Category(name=new, icon="place", color="#607D8B")
                session.add(new_cat)
                await session.flush()
                name_to_id[new] = new_cat.id
                new_id = new_cat.id
            attr.category_id = new_id

        await session.commit()
        print(f"\nApplied {len(changes)} change(s).")
        return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true",
        help="Write the corrected category_id values (default: dry run, log only)",
    )
    args = parser.parse_args()
    asyncio.run(main(args.apply))
