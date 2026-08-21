"""Turn a museum itinerary spreadsheet into masterpiece rows.

The sheets look like this — one tab per tour length, one row per stop:

    Stop | Location                             | Exhibit
    1    | Level -1 – Archaeological Excavation | House Θ
    2    | Level -1 – Archaeological Excavation | Houses Η and Γ

Two things about that shape caused the bugs this module exists to avoid.

The same exhibit appears in several tours at a *different stop number* each
time — 41 of the Acropolis's 50 five-hour exhibits are numbered differently in
the one-day tour. One `rank` column cannot hold three orders, so each tour now
gets its own stop column and nothing has to be re-sorted afterwards.

And a tour is not always a superset of a shorter one: "East, North, South & West
Metopes" is in the Acropolis five-hour tour but absent from the two-day tour.
Merging cannot assume nesting, so every sheet contributes rows and the flags are
set independently.

Parsing is kept free of the database so it can be tested against a spreadsheet
without one.
"""
from typing import Iterable, Optional

import pandas as pd


# Sheet name → the itinerary it describes. Matched loosely because the tabs are
# named by hand: "5 Hour Itinerary", "5-Hour", "5h Itinerary" all mean the same.
DURATIONS = ("3h", "5h", "1d", "2d")

_SHEET_PATTERNS: dict[str, tuple[str, ...]] = {
    "3h": ("3 hour", "3-hour", "3hour", "3h"),
    "5h": ("5 hour", "5-hour", "5hour", "5h"),
    "1d": ("1 day", "1-day", "1day", "one day", "full day", "1d"),
    "2d": ("2 day", "2-day", "2day", "two day", "2d"),
}

REQUIRED_COLUMNS = ("Stop", "Location", "Exhibit")


class ItineraryImportError(ValueError):
    """The spreadsheet is not in a shape we can read."""


def duration_for_sheet(sheet_name: str) -> Optional[str]:
    """Which itinerary a tab describes, or None if it is not one.

    Longest pattern first so "1 day" is not claimed by a stray "1d" rule.
    """
    text = " ".join(str(sheet_name).lower().split())
    best: Optional[str] = None
    best_len = 0
    for duration, patterns in _SHEET_PATTERNS.items():
        for pattern in patterns:
            if pattern in text and len(pattern) > best_len:
                best, best_len = duration, len(pattern)
    return best


def _clean(value) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    return " ".join(str(value).split())


def _key(exhibit: str, location: str) -> tuple[str, str]:
    return (exhibit.strip().lower(), location.strip().lower())


def parse_sheets(
    sheets: dict[str, pd.DataFrame],
    *,
    building_for=None,
    category_for=None,
) -> tuple[list[dict], list[str]]:
    """Build one row per exhibit from every recognised tab.

    Returns the rows and a list of warnings — things worth a human's attention
    that are not errors, such as an exhibit listed twice inside one tour.

    `building_for(location)` and `category_for(exhibit, location)` let a caller
    supply museum-specific grouping; both fall back to something sensible.
    """
    building_for = building_for or default_building_for
    category_for = category_for or default_category_for

    rows: dict[tuple, dict] = {}
    warnings: list[str] = []
    recognised = 0

    for sheet_name, df in sheets.items():
        duration = duration_for_sheet(sheet_name)
        if duration is None:
            warnings.append(f"sheet '{sheet_name}' is not an itinerary — skipped")
            continue
        recognised += 1

        missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
        if missing:
            raise ItineraryImportError(
                f"sheet '{sheet_name}' is missing column(s): {', '.join(missing)}"
            )

        seen_in_sheet: dict[tuple[str, str], int] = {}
        for position, (_, raw) in enumerate(df.iterrows(), start=1):
            exhibit = _clean(raw["Exhibit"])
            location = _clean(raw["Location"])
            if not exhibit:
                warnings.append(f"{sheet_name}: row {position} has no exhibit — skipped")
                continue

            base = _key(exhibit, location)
            # An exhibit listed twice in one tour is two stops, not one. The
            # Acropolis lists Poseidon at stops 71 and 110 in the same gallery;
            # keying on name alone silently threw one away.
            occurrence = seen_in_sheet.get(base, 0)
            seen_in_sheet[base] = occurrence + 1
            if occurrence:
                warnings.append(
                    f"{sheet_name}: '{exhibit}' appears {occurrence + 1}x in "
                    f"{location or 'the same place'} — kept as separate stops"
                )
            key = (*base, occurrence)

            try:
                stop = int(raw["Stop"])
            except (TypeError, ValueError):
                stop = position
                warnings.append(
                    f"{sheet_name}: '{exhibit}' has no usable Stop number — "
                    f"using its row position ({position})"
                )

            row = rows.get(key)
            if row is None:
                row = {
                    "building": building_for(location),
                    "room_gallery": location,
                    "must_see_item": exhibit,
                    "artist": None,
                    "category": category_for(exhibit, location),
                    "description": None,
                    **{f"included_{d}": False for d in DURATIONS},
                    **{f"stop_{d}": None for d in DURATIONS},
                }
                rows[key] = row

            row[f"included_{duration}"] = True
            row[f"stop_{duration}"] = stop

    if not recognised:
        raise ItineraryImportError(
            "no itinerary sheets found — expected tab names like "
            "'5 Hour Itinerary' or '2 Day Itinerary'"
        )

    ordered = _apply_rank(list(rows.values()))
    return ordered, warnings


def _apply_rank(rows: list[dict]) -> list[dict]:
    """Give every row a `rank`, using the fullest tour that contains it.

    `rank` is NOT NULL and predates the per-tour columns, so it still has to
    hold something. The longest tour is the closest thing to a canonical order,
    and exhibits missing from it keep their position relative to the tour they
    do appear in. Nothing is re-sorted by inclusion flags — doing that is what
    scrambled the order before.
    """
    def sort_key(row: dict):
        for duration in ("2d", "1d", "5h", "3h"):
            stop = row.get(f"stop_{duration}")
            if stop is not None:
                # Sort by the tour first so exhibits absent from the long tour
                # cluster with the tour they belong to, then by stop.
                return (("2d", "1d", "5h", "3h").index(duration), stop)
        return (99, 0)

    rows.sort(key=sort_key)
    for index, row in enumerate(rows, start=1):
        row["rank"] = index
    return rows


def default_building_for(location: str) -> str:
    """Floor or wing, taken from the front of the location string."""
    text = (location or "").lower()
    for needle, label in (
        ("level -1", "Level -1 (Excavation)"),
        ("ground floor", "Ground Floor"),
        ("first floor", "First Floor"),
        ("second floor", "Second Floor"),
        ("third floor", "Third Floor"),
        ("fourth floor", "Fourth Floor"),
        ("basement", "Basement"),
        ("mezzanine", "Mezzanine"),
    ):
        if needle in text:
            return label
    # "Third Floor – Parthenon Gallery" → "Third Floor" when the dash is there.
    for dash in ("–", "—", "-"):
        if dash in (location or ""):
            head = location.split(dash, 1)[0].strip()
            if head:
                return head
    return location or "Main Building"


def default_category_for(exhibit: str, location: str) -> str:
    """Gallery name, which is the part of the location after the floor."""
    for dash in ("–", "—", "-"):
        if dash in (location or ""):
            tail = location.split(dash, 1)[1].strip()
            if tail:
                return tail
    return location or "Highlights"


def read_workbook(path: str) -> dict[str, pd.DataFrame]:
    """Every sheet of a workbook, keyed by tab name."""
    workbook = pd.ExcelFile(path)
    return {name: workbook.parse(name) for name in workbook.sheet_names}


def summarise(rows: Iterable[dict]) -> dict[str, int]:
    rows = list(rows)
    return {
        "total": len(rows),
        **{d: sum(1 for r in rows if r.get(f"included_{d}")) for d in DURATIONS},
    }
