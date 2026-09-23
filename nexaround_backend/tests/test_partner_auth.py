"""What a partner token must prove, and where its link tokens may live.

Every rule here guards an escalation rather than a convenience, so each test
names the escalation it prevents. Pure functions only — no DB, no network.
"""
from datetime import datetime, timedelta, timezone

import pytest

from app.core.security import create_access_token, create_refresh_token, decode_token
from app.services import partner_auth as PA

VENDOR = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"
LOGIN = "33333333-3333-3333-3333-333333333333"


def _decoded(token: str) -> dict:
    return decode_token(token)


def test_a_real_partner_token_passes():
    tok = create_access_token({"sub": LOGIN, "role": "vendor", "vendor_id": VENDOR})
    assert PA.claims_ok(_decoded(tok), VENDOR)


def test_a_refresh_token_is_refused():
    """The sharpest hole in the design if it were missed.

    `create_refresh_token` signs with the same key and lasts 30 days. Nothing
    else in the codebase checks `type`, so without this a vendor's refresh
    token would work as an access token indefinitely — defeating the one-hour
    expiry and the logout blacklist at the same time.
    """
    tok = create_refresh_token({"sub": LOGIN, "role": "vendor", "vendor_id": VENDOR})
    assert not PA.claims_ok(_decoded(tok), VENDOR)


def test_a_traveller_token_is_refused():
    """An app user's token carries no role; it must not reach the partner API."""
    tok = create_access_token({"sub": LOGIN, "email": "someone@example.test"})
    assert not PA.claims_ok(_decoded(tok), VENDOR)


def test_an_admin_token_is_refused():
    tok = create_access_token({"sub": "admin", "role": "admin"})
    assert not PA.claims_ok(_decoded(tok), VENDOR)


def test_a_token_for_another_vendor_is_refused():
    """Re-pointing a login at a different vendor invalidates its live tokens."""
    tok = create_access_token({"sub": LOGIN, "role": "vendor", "vendor_id": OTHER})
    assert not PA.claims_ok(_decoded(tok), VENDOR)


@pytest.mark.parametrize("payload", [None, {}, {"role": "vendor"}, {"type": "access"}])
def test_a_token_missing_its_claims_is_refused(payload):
    assert not PA.claims_ok(payload, VENDOR)


# ── sessions after a password change ────────────────────────────────────────

def _ts(**kw) -> float:
    return (datetime.now(timezone.utc) + timedelta(**kw)).timestamp()


def test_a_login_that_never_changed_its_password_stays_valid():
    assert PA.session_is_current(_ts(minutes=-5), None)


def test_a_session_older_than_the_password_change_is_dead():
    """This is what makes a reset sign the other browsers out.

    Their jti values were never recorded, so there is nothing to blacklist —
    the timestamp comparison is the whole mechanism.
    """
    changed = datetime.now(timezone.utc)
    assert not PA.session_is_current(_ts(minutes=-30), changed)


def test_a_session_issued_after_the_change_survives():
    changed = datetime.now(timezone.utc) - timedelta(minutes=10)
    assert PA.session_is_current(_ts(minutes=-1), changed)


def test_a_naive_timestamp_is_treated_as_utc_not_crashed_on():
    """Postgres can hand back a naive datetime; comparing it must not raise."""
    changed = datetime.now(timezone.utc).replace(tzinfo=None)
    assert PA.session_is_current(_ts(minutes=5), changed) is True


def test_a_token_with_no_iat_cannot_prove_it_is_current():
    assert not PA.session_is_current(None, datetime.now(timezone.utc))


# ── Redis key namespace ─────────────────────────────────────────────────────

def test_link_tokens_never_land_in_the_traveller_reset_namespace():
    """The cross-tenant escalation this separation exists to prevent.

    `AuthService.reset_password` reads `reset_token:{token}`, maps it to an
    EMAIL, and updates the matching `users` row. A vendor invite stored under
    that prefix would let whoever holds the link take over the traveller
    account with the same address.
    """
    keys = [
        PA.invite_key("abc"), PA.reset_key("abc"),
        PA.invite_pointer_key(LOGIN), PA.reset_pointer_key(LOGIN),
    ]
    for key in keys:
        assert not key.startswith("reset_token:"), key
        assert key.startswith("vendor_")


def test_invite_and_reset_tokens_do_not_collide():
    assert PA.invite_key("abc") != PA.reset_key("abc")
    assert PA.invite_pointer_key(LOGIN) != PA.reset_pointer_key(LOGIN)


def test_a_link_token_is_long_enough_to_be_unguessable():
    token = PA.new_link_token()
    assert len(token) >= 32
    assert token != PA.new_link_token()


def test_the_invite_window_outlasts_a_weekend_and_resets_do_not():
    assert PA.INVITE_TTL_SECONDS == 72 * 3600
    assert PA.RESET_TTL_SECONDS == 3600


# ── what the router actually mints ──────────────────────────────────────────

def test_a_minted_partner_token_carries_iat():
    """The regression that locked every vendor out of their own account.

    `create_access_token` injects `exp`, `type` and `jti` — but no `iat`. The
    rules above are all satisfied without one, so the unit tests passed while
    signing in did not: `session_is_current` saw `iat=None` against a freshly
    set `password_changed_at` and refused every token a vendor could ever hold.

    This asserts the claim exists on the real minted token rather than on a
    dict a test wrote, which is the difference that mattered.
    """
    from app.api.v1.partner import _claims

    class _Login:
        id = LOGIN
        vendor_id = VENDOR

    claims = _claims(_Login())
    assert "iat" in claims, "a partner token without iat can never be current"

    token = create_access_token(claims)
    payload = _decoded(token)
    assert payload.get("iat"), "iat did not survive encoding"
    assert PA.claims_ok(payload, VENDOR)
    # The whole point: it must outlive a password change made a moment ago.
    assert PA.session_is_current(
        payload["iat"], datetime.now(timezone.utc) - timedelta(seconds=1),
    )


def test_the_minted_claims_are_the_ones_the_gate_checks():
    from app.api.v1.partner import _claims

    class _Login:
        id = LOGIN
        vendor_id = VENDOR

    claims = _claims(_Login())
    assert claims["role"] == "vendor"
    assert claims["sub"] == LOGIN
    assert claims["vendor_id"] == VENDOR
