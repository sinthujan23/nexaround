"""Reading a museum itinerary spreadsheet.

Each case here is a bug that reached the database once. The Acropolis import
lost a stop, invented an exhibit count, and put 101 of 113 exhibits in the wrong
order — all silently, because nothing compared the result to the sheet.
"""
import pandas as pd
import pytest

from app.services.museum_itinerary_import import (
    ItineraryImportError,
    duration_for_sheet,
    parse_sheets,
    summarise,
)


def sheet(rows):
    """rows: list of (stop, location, exhibit)."""
    return pd.DataFrame(rows, columns=["Stop", "Location", "Exhibit"])


# ── Tab naming ──────────────────────────────────────────────────────────────

@pytest.mark.parametrize("name,expected", [
    ("5 Hour Itinerary", "5h"), ("5-Hour", "5h"), ("5h Itinerary", "5h"),
    ("1 Day Itinerary", "1d"), ("One Day", "1d"), ("Full Day Route", "1d"),
    ("2 Day Itinerary", "2d"), ("2-day", "2d"),
    ("3 Hour Itinerary", "3h"),
])
def test_tab_names_are_recognised(name, expected):
    assert duration_for_sheet(name) == expected


@pytest.mark.parametrize("name", ["Notes", "Sheet1", "Floor Plan", ""])
def test_non_itinerary_tabs_are_ignored(name):
    assert duration_for_sheet(name) is None


def test_one_day_is_not_claimed_by_the_shorter_pattern():
    """'1 Day' contains no '1d', but a loose matcher could still mis-file it."""
    assert duration_for_sheet("1 Day Itinerary") == "1d"
    assert duration_for_sheet("2 Day Itinerary") == "2d"


# ── Nothing may be lost ─────────────────────────────────────────────────────

def test_an_exhibit_listed_twice_in_one_tour_stays_two_stops():
    """The Acropolis lists Poseidon at stops 71 and 110 in the same gallery.
    Keying on the name alone threw one away."""
    rows, warnings = parse_sheets({"2 Day Itinerary": sheet([
        (1, "Third Floor – Parthenon Gallery", "Poseidon"),
        (2, "Third Floor – Parthenon Gallery", "Athena"),
        (3, "Third Floor – Parthenon Gallery", "Poseidon"),
    ])})
    assert len(rows) == 3
    assert [r["stop_2d"] for r in rows] == [1, 2, 3]
    assert any("appears 2x" in w for w in warnings)


def test_an_exhibit_only_in_the_short_tour_is_kept():
    """Tours are not nested: the Acropolis five-hour route includes the Metopes,
    which the two-day route omits entirely."""
    rows, _ = parse_sheets({
        "5 Hour Itinerary": sheet([(1, "Third Floor", "Metopes")]),
        "2 Day Itinerary": sheet([(1, "Third Floor", "Frieze")]),
    })
    names = {r["must_see_item"] for r in rows}
    assert names == {"Metopes", "Frieze"}
    metopes = next(r for r in rows if r["must_see_item"] == "Metopes")
    assert metopes["included_5h"] and not metopes["included_2d"]


def test_same_name_in_a_different_room_is_a_different_exhibit():
    rows, _ = parse_sheets({"1 Day Itinerary": sheet([
        (1, "Ground Floor – Gallery A", "Cup"),
        (2, "First Floor – Gallery B", "Cup"),
    ])})
    assert len(rows) == 2


# ── Order must survive ──────────────────────────────────────────────────────

def test_each_tour_keeps_its_own_stop_numbers():
    """The same exhibit sits at a different position in each tour — 41 of the
    Acropolis's 50 five-hour exhibits are numbered differently in the one-day
    route — so one rank column could never have held all three."""
    rows, _ = parse_sheets({
        "5 Hour Itinerary": sheet([(10, "Level -1", "Trade and Economy")]),
        "1 Day Itinerary": sheet([(18, "Level -1", "Trade and Economy")]),
        "2 Day Itinerary": sheet([(18, "Level -1", "Trade and Economy")]),
    })
    assert len(rows) == 1
    row = rows[0]
    assert (row["stop_5h"], row["stop_1d"], row["stop_2d"]) == (10, 18, 18)


def test_order_is_not_rearranged_by_which_tours_include_an_exhibit():
    """Sorting on the inclusion flags pulled every short-tour exhibit to the
    front and put 101 of 113 Acropolis exhibits out of place."""
    rows, _ = parse_sheets({
        "5 Hour Itinerary": sheet([(1, "Level -1", "A"), (2, "Level -1", "C")]),
        "2 Day Itinerary": sheet([
            (1, "Level -1", "A"), (2, "Level -1", "B"), (3, "Level -1", "C"),
        ]),
    })
    two_day = sorted(
        (r for r in rows if r["included_2d"]), key=lambda r: r["stop_2d"]
    )
    assert [r["must_see_item"] for r in two_day] == ["A", "B", "C"], (
        "B is only in the long tour and must stay between A and C"
    )


def test_rank_is_assigned_without_gaps_or_repeats():
    rows, _ = parse_sheets({"2 Day Itinerary": sheet(
        [(i, "Level -1", f"Exhibit {i}") for i in range(1, 11)]
    )})
    assert sorted(r["rank"] for r in rows) == list(range(1, 11))


# ── Counts ──────────────────────────────────────────────────────────────────

def test_counts_match_the_sheets():
    rows, _ = parse_sheets({
        "5 Hour Itinerary": sheet([(i, "L", f"E{i}") for i in range(1, 4)]),
        "2 Day Itinerary": sheet([(i, "L", f"E{i}") for i in range(1, 6)]),
    })
    assert summarise(rows) == {"total": 5, "3h": 0, "5h": 3, "1d": 0, "2d": 5}


# ── Bad input is refused, not guessed at ────────────────────────────────────

def test_a_missing_column_is_an_error():
    df = pd.DataFrame([[1, "House"]], columns=["Stop", "Exhibit"])
    with pytest.raises(ItineraryImportError, match="Location"):
        parse_sheets({"1 Day Itinerary": df})


def test_a_workbook_with_no_itinerary_tabs_is_an_error():
    with pytest.raises(ItineraryImportError, match="no itinerary sheets"):
        parse_sheets({"Notes": sheet([(1, "L", "E")])})


def test_a_blank_exhibit_is_skipped_with_a_warning():
    rows, warnings = parse_sheets({"1 Day Itinerary": sheet([
        (1, "L", "Real Exhibit"), (2, "L", ""),
    ])})
    assert len(rows) == 1
    assert any("no exhibit" in w for w in warnings)


def test_an_unreadable_stop_number_falls_back_to_row_position():
    rows, warnings = parse_sheets({"1 Day Itinerary": sheet([
        (1, "L", "First"), ("n/a", "L", "Second"),
    ])})
    second = next(r for r in rows if r["must_see_item"] == "Second")
    assert second["stop_1d"] == 2
    assert any("no usable Stop" in w for w in warnings)


# ── Grouping ────────────────────────────────────────────────────────────────

def test_building_and_gallery_are_split_on_the_dash():
    rows, _ = parse_sheets({"1 Day Itinerary": sheet([
        (1, "Third Floor – Parthenon Gallery", "Frieze"),
    ])})
    assert rows[0]["building"] == "Third Floor"
    assert rows[0]["category"] == "Parthenon Gallery"


def test_a_location_without_a_dash_still_yields_a_building():
    rows, _ = parse_sheets({"1 Day Itinerary": sheet([(1, "Main Hall", "Vase")])})
    assert rows[0]["building"] == "Main Hall"
