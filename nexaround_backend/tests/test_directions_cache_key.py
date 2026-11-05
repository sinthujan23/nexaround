"""Which directions requests may share a cached route."""
from app.api.v1.proxy import _google_maps_cache_key

DESTINATION = "37.971500,23.731800"


def _key(origin, **kwargs):
    return _google_maps_cache_key(
        "directions/json",
        {"origin": origin, "destination": DESTINATION, "mode": "walking", "key": "secret"},
        **kwargs,
    )


def test_nearby_starts_share_a_route_by_default():
    assert _key("37.9685,23.7284") == _key("37.9686,23.7285")


def test_an_exact_start_never_gets_a_neighbours_route():
    assert _key("37.9685,23.7284", exact_origin=True) != _key("37.9686,23.7285", exact_origin=True)


def test_the_same_exact_start_still_shares_one_route():
    assert _key("37.9685,23.7284", exact_origin=True) == _key("37.968500,23.728400", exact_origin=True)


def test_exact_and_grid_routes_are_kept_apart():
    assert _key("37.9650,23.7250", exact_origin=True) != _key("37.9650,23.7250")


def test_other_paths_ignore_exact_origin():
    params = {"latlng": "37.9685,23.7284"}
    assert _google_maps_cache_key("geocode/json", params, exact_origin=True) == _google_maps_cache_key("geocode/json", params)
