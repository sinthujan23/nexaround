"""Blocked dates on a package: merging, lookups, validation, and the enquiry rule."""
from datetime import date

import pytest
from pydantic import ValidationError

from app.services.experience_format import (
    MAX_UNAVAILABLE_RANGES, booking_window_error, is_date_unavailable,
    merge_date_ranges, package_field_value, unavailable_error,
)


def R(a, b):
    return {"start": a, "end": b}


def test_nothing_blocked_means_every_day_is_available():
    assert merge_date_ranges([]) == []
    assert not is_date_unavailable(date(2026, 11, 3), [])
    assert not is_date_unavailable(date(2026, 11, 3), None)
    assert unavailable_error(date(2026, 11, 3), None) is None
    assert unavailable_error(None, [R("2026-11-01", "2026-11-30")]) is None


def test_a_range_includes_both_of_its_end_days():
    rng = [R("2026-11-10", "2026-11-12")]
    assert not is_date_unavailable(date(2026, 11, 9), rng)
    for d in (10, 11, 12):
        assert is_date_unavailable(date(2026, 11, d), rng)
    assert not is_date_unavailable(date(2026, 11, 13), rng)


def test_a_single_blocked_day_is_a_range_of_one():
    rng = [R("2026-12-25", "2026-12-25")]
    assert is_date_unavailable(date(2026, 12, 25), rng)
    assert not is_date_unavailable(date(2026, 12, 24), rng)
    assert not is_date_unavailable(date(2026, 12, 26), rng)


def test_overlapping_and_touching_ranges_become_one_block_and_gaps_stay_apart():
    merged = merge_date_ranges([
        R("2026-11-05", "2026-11-08"),
        R("2026-11-01", "2026-11-03"),   # touches nothing yet
        R("2026-11-04", "2026-11-04"),   # joins 1-3 and 5-8 into 1-8
        R("2026-11-20", "2026-11-22"),
        R("2026-11-21", "2026-11-30"),   # overlaps
        R("2026-12-02", "2026-12-02"),   # a one-day gap after Nov 30 is Dec 1: stays apart
    ])
    assert merged == [R("2026-11-01", "2026-11-08"), R("2026-11-20", "2026-11-30"), R("2026-12-02", "2026-12-02")]


def test_a_range_inside_another_is_absorbed_and_dates_may_arrive_as_objects():
    class Obj:
        def __init__(self, a, b): self.start, self.end = a, b

    merged = merge_date_ranges([Obj(date(2026, 11, 1), date(2026, 11, 30)), Obj(date(2026, 11, 10), date(2026, 11, 12))])
    assert merged == [R("2026-11-01", "2026-11-30")]


def test_an_enquiry_for_a_blocked_date_is_refused_with_a_readable_reason():
    msg = unavailable_error(date(2026, 11, 11), [R("2026-11-10", "2026-11-12")])
    assert msg and "not available" in msg


def test_the_blocked_date_check_is_separate_from_the_booking_window_check():
    today = date(2026, 11, 1)
    assert booking_window_error(date(2026, 11, 11), today, 365) is None
    assert unavailable_error(date(2026, 11, 11), [R("2026-11-11", "2026-11-11")])


def test_a_range_cannot_end_before_it_starts():
    from app.schemas.experience import DateRange

    assert DateRange(start="2026-11-01", end="2026-11-01").end == date(2026, 11, 1)
    with pytest.raises(ValidationError):
        DateRange(start="2026-11-02", end="2026-11-01")
    with pytest.raises(ValidationError):
        DateRange(start="not-a-date", end="2026-11-01")


def test_admin_and_partner_packages_both_take_blocked_dates_and_default_to_none():
    from app.schemas.experience import ExperiencePackageCreate
    from app.schemas.partner import PartnerPackageCreate

    for schema in (ExperiencePackageCreate, PartnerPackageCreate):
        assert schema(title="T").unavailable_ranges == []
        pkg = schema(title="T", unavailable_ranges=[{"start": "2026-11-01", "end": "2026-11-02"}])
        assert pkg.unavailable_ranges[0].end == date(2026, 11, 2)
        with pytest.raises(ValidationError):
            schema(title="T", unavailable_ranges=[{"start": "2026-11-01", "end": "2026-11-02"}] * (MAX_UNAVAILABLE_RANGES + 1))


def test_saving_stores_plain_merged_json_not_pydantic_objects():
    from app.schemas.experience import ExperiencePackageCreate

    data = ExperiencePackageCreate(title="T", unavailable_ranges=[
        {"start": "2026-11-04", "end": "2026-11-06"},
        {"start": "2026-11-01", "end": "2026-11-03"},
    ])
    stored = package_field_value(data, "unavailable_ranges")
    assert stored == [R("2026-11-01", "2026-11-06")]
    import json
    json.dumps(stored)   # a JSONB column can serialise it
    assert package_field_value(data, "title") == "T"


def test_the_partner_may_write_blocked_dates_and_the_two_tuples_still_agree():
    from app.api.v1.experiences_admin import _PACKAGE_SCALARS
    from app.api.v1.partner import _PARTNER_PACKAGE_SCALARS

    assert "unavailable_ranges" in _PACKAGE_SCALARS
    assert "unavailable_ranges" in _PARTNER_PACKAGE_SCALARS


def test_the_app_detail_carries_blocked_dates_and_the_card_does_not():
    from app.schemas.experience import ExperiencePackageCard, ExperiencePackageDetail

    assert "unavailable_ranges" in ExperiencePackageDetail.model_fields
    assert "unavailable_ranges" not in ExperiencePackageCard.model_fields


def test_the_detail_serialises_blocked_dates_as_iso_strings_for_the_app():
    from app.schemas.experience import DateRange

    out = DateRange(start="2026-11-01", end="2026-11-03").model_dump(mode="json")
    assert out == {"start": "2026-11-01", "end": "2026-11-03"}
