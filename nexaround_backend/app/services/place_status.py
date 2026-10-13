"""What a place's `status` means, and which moves between statuses are allowed.

    live      shown in the app
    pending   waiting in the admin Review queue (a user's suggestion, or an
              old duplicate copy the merge script has not resolved yet)
    hidden    an admin took a live place out of the app; reversible
    rejected  an admin turned a suggestion down. The row is kept as a
              tombstone so Google seeding recognises the place and never
              puts it back

Pure on purpose: the admin API, the merge script and the tests all ask this
module, so the rules live in one place.
"""
from typing import Optional

LIVE = "live"
PENDING = "pending"
HIDDEN = "hidden"
REJECTED = "rejected"
STATUSES = (LIVE, PENDING, HIDDEN, REJECTED)

SOURCES = ("google", "admin", "user", "seed", "unknown")

# Reasons an admin picks when hiding or rejecting.
ADMIN_REASONS = (
    "duplicate_location",
    "closed",
    "not_a_place",
    "wrong_location",
    "inappropriate",
    "admin_hidden",
    "other",
)

# Reasons the system sets on its own.
SYSTEM_REASONS = (
    "user_suggestion",
    "legacy_inactive",
    "merged_restored",
    "legacy_restored",
    "reopened",
)

# (from, to) -> the action's name, as the admin panel labels it.
TRANSITIONS = {
    (PENDING, LIVE): "approve",
    (PENDING, REJECTED): "reject",
    (LIVE, HIDDEN): "hide",
    (HIDDEN, LIVE): "unhide",
    (REJECTED, LIVE): "restore",
    (REJECTED, PENDING): "reopen",
}

# Moves that must say why.
_NEEDS_REASON = {(PENDING, REJECTED), (LIVE, HIDDEN)}


class TransitionError(ValueError):
    """A status move the rules do not allow, with a message an admin can read."""


def check_transition(
    current: str,
    target: str,
    reason: Optional[str] = None,
    note: Optional[str] = None,
) -> Optional[str]:
    """Validate a move and return the reason to store with it.

    Returns None for a move to the status the place already has (a no-op the
    caller should treat as success). Raises TransitionError otherwise.
    """
    if target not in STATUSES:
        raise TransitionError(f"Unknown status '{target}'.")
    if current == target:
        return None
    if (current, target) not in TRANSITIONS:
        raise TransitionError(_not_allowed_message(current, target))

    reason = (reason or "").strip() or None
    note = (note or "").strip() or None

    if (current, target) in _NEEDS_REASON:
        if reason is None:
            raise TransitionError("Choose a reason.")
        if reason not in ADMIN_REASONS:
            raise TransitionError(f"Unknown reason '{reason}'.")
        if reason == "other" and note is None:
            raise TransitionError("Add a note when the reason is 'other'.")
        return reason

    if (current, target) == (REJECTED, PENDING):
        return "reopened"

    # Approve, unhide and restore clear the reason: the place is fine now.
    if reason is not None and reason not in ADMIN_REASONS:
        raise TransitionError(f"Unknown reason '{reason}'.")
    return reason


def _not_allowed_message(current: str, target: str) -> str:
    if (current, target) == (LIVE, REJECTED):
        return "A live place can't be rejected. Hide it instead."
    if (current, target) == (LIVE, PENDING):
        return "A live place can't go back to the Review queue. Hide it instead."
    if current == HIDDEN:
        return "A hidden place can only be made live again."
    if current == PENDING and target == HIDDEN:
        return "Approve or reject a place in the Review queue; it can't be hidden."
    return f"Can't move a place from {current} to {target}."
