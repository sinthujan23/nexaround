"""Daily currency rates: reading the provider, when to fetch, what the admin sees."""
from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from app.schemas.experience import ExperiencePackageAdminResponse, ExperiencePackageCreate
from app.schemas.partner import PartnerPackageCreate
from app.services import fx_service as fx
from app.services.currencies import PRICE_CURRENCIES

NOW = datetime(2026, 10, 16, 12, 0, tzinfo=timezone.utc)


def test_the_keyed_answer_is_read():
    fields, error = fx.parse_latest({
        "result": "success",
        "time_last_update_unix": 1792108801,
        "time_next_update_unix": 1792195201,
        "conversion_rates": {"USD": 1, "QAR": 3.64, "INR": 95.1, "BAD": "x", "ZERO": 0},
    })
    assert error is None
    assert fields["rates"] == {"USD": 1.0, "QAR": 3.64, "INR": 95.1}
    assert fields["provider_updated_at"] == datetime(2026, 10, 16, 0, 0, 1, tzinfo=timezone.utc)
    assert fields["provider_next_update_at"] == datetime(2026, 10, 17, 0, 0, 1, tzinfo=timezone.utc)


def test_the_open_answer_is_read_too():
    fields, error = fx.parse_latest({"result": "success", "rates": {"USD": 1, "EUR": 0.89}})
    assert error is None and fields["rates"]["EUR"] == 0.89


@pytest.mark.parametrize("data, expected", [
    ({"result": "error", "error-type": "invalid-key"}, "invalid-key"),
    ({"result": "error", "error-type": "quota-reached"}, "quota-reached"),
    ({"result": "success", "conversion_rates": {}}, "no-rates-in-response"),
    (None, "unreadable-response"),
])
def test_a_failure_is_named(data, expected):
    assert fx.parse_latest(data) == (None, expected)


def test_fetch_when_nothing_is_stored_or_the_source_changed():
    assert fx.is_due(None, None, None, fx.KEYED_SOURCE, NOW)
    assert fx.is_due(NOW, NOW + timedelta(hours=10), fx.OPEN_SOURCE, fx.KEYED_SOURCE, NOW)


def test_wait_for_the_next_publish():
    nxt = NOW + timedelta(hours=3)
    assert not fx.is_due(NOW - timedelta(hours=9), nxt, fx.KEYED_SOURCE, fx.KEYED_SOURCE, NOW)
    # A few minutes after the publish time, not on the dot.
    assert not fx.is_due(NOW, NOW - timedelta(minutes=5), fx.KEYED_SOURCE, fx.KEYED_SOURCE, NOW)
    assert fx.is_due(NOW, NOW - timedelta(minutes=20), fx.KEYED_SOURCE, fx.KEYED_SOURCE, NOW)


def test_a_day_old_answer_without_a_publish_time_is_refreshed():
    assert fx.is_due(NOW - timedelta(hours=25), None, fx.OPEN_SOURCE, fx.OPEN_SOURCE, NOW)
    assert not fx.is_due(NOW - timedelta(hours=2), None, fx.OPEN_SOURCE, fx.OPEN_SOURCE, NOW)


def test_health():
    assert fx.health(NOW - timedelta(hours=3), None, NOW) == "ok"
    assert fx.health(NOW - timedelta(hours=3), "invalid-key", NOW) == "error"
    assert fx.health(NOW - timedelta(hours=49), None, NOW) == "stale"
    assert fx.health(None, None, NOW) == "stale"
    assert fx.health(None, "invalid-key", NOW) == "error"


def test_the_key_is_never_shown_whole():
    assert fx.mask_key("27afc4792097c68470a3f022") == "••••f022"
    assert fx.mask_key("") == ""


def test_prices_take_only_known_currencies():
    assert ExperiencePackageCreate(title="T", price_currency=" qar ").price_currency == "QAR"
    assert PartnerPackageCreate(title="T", price_currency="inr").price_currency == "INR"
    for bad in ("94", "XYZ", "KPW"):
        with pytest.raises(ValidationError):
            ExperiencePackageCreate(title="T", price_currency=bad)
        with pytest.raises(ValidationError):
            PartnerPackageCreate(title="T", price_currency=bad)


def test_a_stored_unknown_currency_still_loads():
    from datetime import datetime as dt
    import uuid
    out = ExperiencePackageAdminResponse(
        id=uuid.uuid4(), vendor_id=uuid.uuid4(), title="Old", price_currency="XYZ",
        created_at=dt.now(timezone.utc),
    )
    assert out.price_currency == "XYZ"


def test_the_list_covers_the_live_prices():
    assert {"LKR", "INR", "QAR", "USD", "AED"} <= set(PRICE_CURRENCIES)
