"""The keys the Flutter app reads off a stored plan.

A rename on this side is invisible until someone opens the app: the Dart
parsers use `json['key'] ?? default`, so a missing key is a silent default, not
an error. `inter_city_flights` spent a release being written and never read, and
`budget_notes` had to be added to three separate places in the model before it
survived a round trip. These pin the names.

Read alongside tests/test_client_server_sync.py, which covers the same idea for
the fields that existed before Odyssey.
"""
import inspect

from app.services.odyssey_ai_service import build_meta_item


def _meta(**kw):
    args = dict(
        destination="India", mood="Cultural", budget=1.0, currency="INR",
        days=2, nights=1,
    )
    args.update(kw)
    return build_meta_item(**args)


# Every key `Odyssey.fromItinerary` reaches for on the meta header.
APP_READS = {
    "destination", "mood", "budget", "currency", "days", "nights", "travelers",
    "summary", "budget_split", "visa", "logistics", "booking_partners",
    "cover_url", "flight_strategies", "hotel_strategies", "inter_city_flights",
    "start_date", "end_date", "departure_city", "budget_breakdown",
    "budget_advisory", "budget_notes", "plan_advisory", "verified_sources",
    "verdict", "budget_scenarios", "budget_basis", "practical_info",
    "booking_plan", "legs",
}


def test_the_meta_header_carries_every_key_the_app_reads():
    meta = _meta()
    missing = sorted(APP_READS - set(meta))
    assert not missing, f"the app reads keys the backend no longer writes: {missing}"


def test_every_key_is_present_even_on_a_bare_plan():
    """The app reads unconditionally; a key that appears only sometimes is a bug."""
    for key in APP_READS:
        assert key in _meta(), key


def test_the_containers_are_the_shapes_the_app_casts_to():
    meta = _meta()
    for key in ("flight_strategies", "hotel_strategies", "visa", "verdict",
                "budget_breakdown", "budget_scenarios", "budget_basis",
                "practical_info", "budget_notes"):
        assert isinstance(meta[key], dict), f"{key} must be a map"
    for key in ("booking_partners", "verified_sources", "booking_plan", "legs",
                "inter_city_flights"):
        assert isinstance(meta[key], list), f"{key} must be a list"
    for key in ("budget_advisory", "plan_advisory", "summary", "logistics"):
        assert isinstance(meta[key], str), f"{key} must be a string"


def test_budget_notes_uses_the_three_keys_the_card_draws():
    from app.services.odyssey_ai_service import _budget_notes

    full = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="direct", no_airfare=False,
    )
    assert set(full) == {"summary", "stay", "transit"}
    assert all(isinstance(v, str) and v for v in full.values())


def test_an_inter_city_flight_carries_the_fields_the_card_shows():
    """The card names the carrier, the flight number and the journey time."""
    import app.services.odyssey_ai_service as svc

    src = inspect.getsource(svc.generate_inter_city_flights)
    for key in ("day", "from_city", "to_city", "from_code", "to_code", "date",
                "airlines", "flight_numbers", "stops", "duration",
                "price_per_traveler", "currency", "booking_url"):
        assert f'"{key}"' in src, f"inter-city hops no longer carry {key!r}"
