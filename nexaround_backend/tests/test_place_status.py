"""The rules for moving a place between live / pending / hidden / rejected."""
import itertools

import pytest

from app.services import place_status as ps
from app.services.place_status import TransitionError, check_transition

ALLOWED = {
    ("pending", "live"),
    ("pending", "rejected"),
    ("live", "hidden"),
    ("hidden", "live"),
    ("rejected", "live"),
    ("rejected", "pending"),
}


@pytest.mark.parametrize("current,target", list(itertools.product(ps.STATUSES, repeat=2)))
def test_every_pair(current, target):
    """All 16 moves: the six allowed ones pass (given a reason where one is
    required), a move to the same status is a no-op, the rest are refused."""
    if current == target:
        assert check_transition(current, target) is None
    elif (current, target) in ALLOWED:
        check_transition(current, target, reason="closed")
    else:
        with pytest.raises(TransitionError):
            check_transition(current, target, reason="closed")


@pytest.mark.parametrize("move", [("pending", "rejected"), ("live", "hidden")])
def test_hide_and_reject_need_a_reason(move):
    with pytest.raises(TransitionError, match="reason"):
        check_transition(*move)
    assert check_transition(*move, reason="not_a_place") == "not_a_place"


def test_other_needs_a_note():
    with pytest.raises(TransitionError, match="note"):
        check_transition("live", "hidden", reason="other")
    assert check_transition("live", "hidden", reason="other", note="road closed") == "other"


def test_unknown_reason_refused():
    with pytest.raises(TransitionError):
        check_transition("live", "hidden", reason="because")


def test_reopen_is_labelled_and_approve_clears_reason():
    assert check_transition("rejected", "pending") == "reopened"
    assert check_transition("pending", "live") is None
    assert check_transition("hidden", "live") is None


def test_live_to_rejected_message_points_at_hide():
    with pytest.raises(TransitionError, match="Hide it instead"):
        check_transition("live", "rejected", reason="closed")


def test_unknown_status():
    with pytest.raises(TransitionError):
        check_transition("live", "archived")
