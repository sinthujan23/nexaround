"""Grouping and survivor rules of the duplicate-copy merge."""
from datetime import datetime, timedelta, timezone

from app.scripts.merge_duplicate_attractions import (
    Row,
    _review_conflicts,
    is_candidate,
    near_duplicates,
    plan_groups,
)

T0 = datetime(2026, 5, 1, tzinfo=timezone.utc)


def _row(i, name="Galle Face Green", *, status="pending", gid=None,
         lat=6.927079, lng=79.845626, days=0, **kw):
    return Row(id=f"{i:08d}-0000-0000-0000-000000000000", name=name, gid=gid,
               lat=lat, lng=lng, status=status,
               created_at=T0 + timedelta(days=days), **kw)


def test_same_spot_same_name_is_one_place():
    rows = [_row(1, status="live"), _row(2, days=1), _row(3, days=2)]
    groups, _ = plan_groups(rows)
    assert len(groups) == 1
    g = groups[0]
    assert g.survivor.id == rows[0].id
    assert {m.id for m in g.losers} == {rows[1].id, rows[2].id}
    assert g.status == "live" and g.status_reason is None


def test_same_spot_different_names_are_different_places():
    rows = [_row(1, "Galle Face Green", status="live"), _row(2, "Ministry of Crab")]
    groups, _ = plan_groups(rows)
    assert groups == []


def test_name_contained_in_the_other_merges_unless_exact_only():
    rows = [_row(1, "One Galle Face", status="live"), _row(2, "One Galle Face Mall")]
    assert len(plan_groups(rows)[0]) == 1
    assert plan_groups(rows, exact_names_only=True)[0] == []


def test_strict_mode_needs_the_same_name_for_google_id_links_too():
    rows = [
        _row(1, "The Gardens Mall", gid="ChIJm", status="live"),
        _row(2, "MST Golf Arena", gid="ChIJm", lat=6.9272, lng=79.8457),
    ]
    assert len(plan_groups(rows)[0]) == 1
    assert plan_groups(rows, exact_names_only=True)[0] == []


def test_google_id_links_nearby_rows_but_not_far_ones():
    near = [
        _row(1, gid="ChIJa", status="live"),
        _row(2, "Galle Face", gid="ChIJa", lat=6.9275, lng=79.8460),
    ]
    far = _row(3, gid="ChIJa", lat=7.29, lng=80.63)  # Kandy
    groups, report = plan_groups(near + [far])
    assert len(groups) == 1
    assert far.id not in {m.id for m in groups[0].members}
    assert report["gid_conflicts"][0]["b"]["id"] == far.id


def test_group_without_live_copy_comes_back_live():
    rows = [_row(1), _row(2, days=3)]
    g = plan_groups(rows)[0][0]
    assert (g.status, g.status_reason) == ("live", "merged_restored")


def test_survivor_is_richest_then_oldest():
    rows = [
        _row(1, status="live", days=5),
        _row(2, status="live", days=1, photos=3, has_description=True),
        _row(3, status="live", days=0),
    ]
    assert plan_groups(rows)[0][0].survivor.id == rows[1].id
    plain = [_row(4, status="live", days=5), _row(5, status="live", days=1)]
    assert plan_groups(plain)[0][0].survivor.id == plain[1].id


def test_live_beats_richer_pending_copy():
    rows = [_row(1, status="live"), _row(2, photos=5, has_history=True, gid="ChIJz")]
    assert plan_groups(rows)[0][0].survivor.id == rows[0].id


def test_admin_decision_outranks_leftover_copies():
    rows = [_row(1, status="rejected"), _row(2), _row(3)]
    g = plan_groups(rows)[0][0]
    assert g.status == "rejected"


def test_only_live_rows_and_old_copies_take_part():
    assert is_candidate(_row(1, status="live"))
    assert is_candidate(_row(2, reason="legacy_inactive"))
    # an app user's suggestion waits for an admin, it is not a leftover
    assert not is_candidate(_row(3, reason="user_suggestion"))
    assert not is_candidate(_row(4, status="hidden", reason="closed"))
    assert not is_candidate(_row(5, status="rejected", reason="not_a_place"))


def test_same_user_reviews_on_two_copies_counted_as_conflict():
    rows = [_row(1, status="live"), _row(2)]
    g = plan_groups(rows)[0][0]
    reviewers = {rows[0].id: ["u1", "u2"], rows[1].id: ["u1"]}
    assert _review_conflicts(g, reviewers) == 1


def test_near_duplicates_reported_not_merged():
    rows = [_row(1, status="live"), _row(2, status="live", lat=6.92716, lng=79.84570)]
    assert plan_groups(rows)[0] == []
    assert near_duplicates(rows) == 1
