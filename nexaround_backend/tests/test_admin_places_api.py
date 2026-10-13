"""Admin Map Database: edits never change status, and every refusal is explicit.

The service runs against a stub repository (there is no database here); the
point is the decisions it makes, not the SQL.
"""
import asyncio
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.schemas.attraction import (
    AdminPlaceCreate,
    AdminPlaceUpdate,
    AttractionSuggest,
    PlaceStatusChange,
)
from app.services.attraction_service import (
    MAX_PENDING_SUGGESTIONS_PER_USER,
    AttractionService,
)
from app.utils.geo_utils import create_point


def _place(**over):
    fields = dict(
        id=uuid.uuid4(), name="Old Fort", description="", history=None,
        location=create_point(6.93, 79.84), category_id=None, category=None,
        address="", opening_hours={}, entry_fee=0.0, currency="USD", rating=0.0,
        review_count=0, photo_urls=[], tags=[], geofence_radius_m=100,
        google_place_id=None, status="live", status_reason=None, status_note=None,
        source="google", submitted_by_user_id=None, reviewed_at=None,
        reviewed_by=None, created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc), is_active=True,
    )
    fields.update(over)
    return SimpleNamespace(**fields)


class _Repo:
    def __init__(self, row=None, *, duplicates=(), pending_by_user=0, usage=None):
        self.row = row
        self.duplicates = list(duplicates)
        self.pending_by_user = pending_by_user
        self.usage = usage or {"reviews": 0, "media": 0, "visits": 0}
        self.created = []

    async def get_by_id(self, _id):
        return self.row

    async def update(self, row):
        return row

    async def create(self, row):
        row.id = uuid.uuid4()
        row.category = None
        row.created_at = datetime.now(timezone.utc)
        row.updated_at = row.created_at
        # What the INSERT would fill in: column defaults, and is_active,
        # which Postgres generates from status.
        for field, default in (
            ("opening_hours", {}), ("entry_fee", 0.0), ("currency", "USD"),
            ("rating", 0.0), ("review_count", 0), ("photo_urls", []),
            ("tags", []), ("geofence_radius_m", 100),
        ):
            if getattr(row, field) is None:
                setattr(row, field, default)
        row.is_active = row.status == "live"
        self.created.append(row)
        self.row = row
        return row

    async def find_possible_duplicates(self, **kwargs):
        return self.duplicates

    async def find_duplicate_by_coordinates(self, *a, **kw):
        return None

    async def count_pending_by_user(self, user_id):
        return self.pending_by_user

    async def usage_counts(self, _id):
        return self.usage


class _Db:
    def __init__(self):
        self.commits = 0

    async def commit(self):
        self.commits += 1


def _service(repo):
    svc = AttractionService(_Db())
    svc.repo = repo
    return svc


def _run(coro):
    return asyncio.run(coro)


@pytest.mark.parametrize("field", ["status", "is_active"])
def test_edit_cannot_carry_status(field):
    with pytest.raises(ValidationError):
        AdminPlaceUpdate(**{field: "live" if field == "status" else True})


def test_edit_applies_photos_and_keeps_status():
    row = _place(status="pending")
    svc = _service(_Repo(row))
    result = _run(svc.update_place(row.id, AdminPlaceUpdate(photo_urls=["/media/a.jpg"])))
    assert row.photo_urls == ["/media/a.jpg"]
    assert result.place.status == "pending"
    assert result.warnings == []


def test_moving_onto_a_similar_place_warns_instead_of_queueing():
    row = _place()
    other = _place(name="Old Fort Museum")
    svc = _service(_Repo(row, duplicates=[(other, 4.0)]))
    result = _run(svc.update_place(row.id, AdminPlaceUpdate(latitude=6.94, longitude=79.85)))
    assert row.status == "live"
    assert result.warnings[0]["code"] == "possible_duplicate"


def test_latitude_without_longitude_refused():
    row = _place()
    with pytest.raises(HTTPException) as e:
        _run(_service(_Repo(row)).update_place(row.id, AdminPlaceUpdate(latitude=6.9)))
    assert e.value.status_code == 400


def test_create_duplicate_asks_first():
    other = _place(name="Old Fort")
    repo = _Repo(duplicates=[(other, 3.0)])
    data = AdminPlaceCreate(name="Old Fort", latitude=6.93, longitude=79.84)
    with pytest.raises(HTTPException) as e:
        _run(_service(repo).create_admin(data, "admin"))
    assert e.value.status_code == 409
    assert e.value.detail["code"] == "possible_duplicate"
    assert e.value.detail["matches"][0]["name"] == "Old Fort"
    assert repo.created == []

    data.confirm_duplicate = True
    place = _run(_service(repo).create_admin(data, "admin"))
    assert place.status == "live" and place.source == "admin"
    assert place.reviewed_by == "admin"


def test_disallowed_status_move_is_409():
    row = _place(status="live")
    with pytest.raises(HTTPException) as e:
        _run(_service(_Repo(row)).change_status(
            row.id, target="rejected", reason="closed", note=None, admin="admin"))
    assert e.value.status_code == 409
    assert row.status == "live"


def test_hide_records_who_and_why_and_commits():
    row = _place(status="live")
    svc = _service(_Repo(row))
    place = _run(svc.change_status(
        row.id, target="hidden", reason="closed", note="closed in 2025", admin="musny"))
    assert (row.status, row.status_reason, row.status_note) == ("hidden", "closed", "closed in 2025")
    assert row.reviewed_by == "musny" and row.reviewed_at is not None
    assert svc.db.commits == 1
    assert place.status == "hidden"


def test_status_change_body_rejects_unknown_fields():
    with pytest.raises(ValidationError):
        PlaceStatusChange(status="live", is_active=True)


def test_suggestion_is_pending_from_the_user():
    repo = _Repo()
    user = SimpleNamespace(id=uuid.uuid4())
    out = _run(_service(repo).create_suggestion(
        AttractionSuggest(name="Hidden Beach", latitude=6.0, longitude=80.2), user))
    row = repo.created[0]
    assert (row.status, row.source, row.status_reason) == ("pending", "user", "user_suggestion")
    assert row.submitted_by_user_id == user.id
    assert out.is_active is False


def test_suggestion_cap():
    repo = _Repo(pending_by_user=MAX_PENDING_SUGGESTIONS_PER_USER)
    with pytest.raises(HTTPException) as e:
        _run(_service(repo).create_suggestion(
            AttractionSuggest(name="Hidden Beach", latitude=6.0, longitude=80.2),
            SimpleNamespace(id=uuid.uuid4())))
    assert e.value.status_code == 429
    assert repo.created == []


def test_delete_refused_when_people_added_content():
    row = _place()
    repo = _Repo(row, usage={"reviews": 2, "media": 0, "visits": 9})
    with pytest.raises(HTTPException) as e:
        _run(_service(repo).hard_delete(row.id))
    assert e.value.status_code == 409
    assert e.value.detail["code"] == "has_user_content"


def test_static_routes_come_before_the_id_route():
    from app.api.v1.attractions_admin import router

    paths = [r.path for r in router.routes]
    assert paths.index("/admin/attractions/counts") < paths.index("/admin/attractions/{attraction_id}")
