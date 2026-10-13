"""Google seeding never brings back a place an admin rejected or hid."""
import asyncio
from types import SimpleNamespace

from app.services import places_service
from app.utils.geo_utils import create_point


class _Session:
    def __init__(self):
        self.added = []

    def add(self, row):
        self.added.append(row)


def _row(status, *, gid=None, name="Fake Waterfall", lat=7.0, lng=80.0):
    return SimpleNamespace(
        status=status, google_place_id=gid, name=name,
        location=create_point(lat, lng),
        review_count=0, rating=0.0, photo_urls=[], tags=[], address="",
        opening_hours={},
    )


def _upsert(place, index, name="Fake Waterfall", lat=7.0, lng=80.0):
    session = _Session()
    asyncio.run(places_service.upsert_seeded_place(
        session, None, place,
        name=name, latitude=lat, longitude=lng, category_id=None,
        existing_index=index,
    ))
    return session


def test_rejected_row_matched_by_google_id_stays_rejected():
    row = _row("rejected", gid="ChIJx")
    s = _upsert({"id": "ChIJx", "review_count": 12}, ({"ChIJx": row}, {}, []))
    assert s.added == []
    assert row.status == "rejected"
    assert row.review_count == 12  # refreshed, still out of the app


def test_rejected_row_matched_by_coordinates():
    row = _row("rejected")
    s = _upsert({"id": "ChIJnew"}, ({}, {(7.0, 80.0): row}, []))
    assert s.added == [] and row.status == "rejected"


def test_drifted_google_result_matches_tombstone():
    row = _row("rejected")
    index = ({}, {}, [(7.0, 80.0, "Fake Waterfall", row)])
    s = _upsert({"id": "ChIJdrift"}, index, name="Fake Waterfall Viewpoint",
                lat=7.00008, lng=80.00008)
    assert s.added == []
    # the Google id is remembered, so the next match is exact
    assert row.google_place_id == "ChIJdrift"


def test_unrelated_nearby_place_is_inserted_live():
    row = _row("rejected")
    index = ({}, {}, [(7.0, 80.0, "Fake Waterfall", row)])
    s = _upsert({"id": "ChIJtea"}, index, name="Tea Shop", lat=7.00008, lng=80.00008)
    assert len(s.added) == 1
    new = s.added[0]
    assert new.status == "live" and new.source == "google"
    assert new.google_place_id == "ChIJtea"
