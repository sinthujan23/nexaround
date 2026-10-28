"""City Tours: the guide document, its review rules and its partner links."""
import urllib.parse
import uuid

import pytest

from app.services import city_tours as ct


def _stop(name="Eiffel Tower", lat=48.8584, lng=2.2945, **extra):
    return {"type": "stop", "name": name, "lat": lat, "lng": lng, **extra}


def _move(mode="metro", **extra):
    return {"type": "move", "mode": mode, "title": "Line 6 towards Nation", **extra}


def _guide(**extra):
    guide = {
        "city": "Paris", "country": "France", "title": "Paris in a day",
        "summary": "The icons by metro.", "cover_url": "/static/uploads/experiences/a.jpg",
        "steps": [_stop(), _move(), _stop("Louvre", 48.8606, 2.3376)],
    }
    guide.update(extra)
    return guide


# ── normalize ────────────────────────────────────────────────────────────────

def test_normalize_keeps_known_fields_and_trims():
    out = ct.normalize(_guide(title="  Paris in a day  ", junk="dropped"))
    assert out["title"] == "Paris in a day"
    assert "junk" not in out
    assert [s["type"] for s in ct.all_steps(out)] == ["stop", "move", "stop"]
    assert all(uuid.UUID(s["id"]) for s in ct.all_steps(out))


def test_normalize_keeps_good_ids_and_replaces_duplicates():
    step_id = str(uuid.uuid4())
    out = ct.normalize(_guide(steps=[_stop(id=step_id), _stop("Louvre", id=step_id)]))
    assert ct.all_steps(out)[0]["id"] == step_id
    assert ct.all_steps(out)[1]["id"] != step_id


def test_normalize_drops_half_a_pin_and_bad_coordinates():
    out = ct.normalize(_guide(steps=[_stop(lat=48.8, lng=None), _stop(lat=200, lng=2.0)]))
    assert ct.all_steps(out)[0]["lat"] is None and ct.all_steps(out)[0]["lng"] is None
    assert ct.all_steps(out)[1]["lat"] is None and ct.all_steps(out)[1]["lng"] is None


def test_unknown_transport_mode_becomes_walk():
    out = ct.normalize(_guide(steps=[_stop(), _move(mode="teleport")]))
    assert ct.all_steps(out)[1]["mode"] == "walk"


def test_too_long_text_is_refused_with_the_editors_words():
    with pytest.raises(ct.ContentError, match="Title is too long"):
        ct.normalize(_guide(title="x" * 121))
    with pytest.raises(ct.ContentError, match="Step 1: the name is too long"):
        ct.normalize(_guide(steps=[_stop(name="x" * 121)]))


def test_photo_must_be_an_upload_or_https():
    with pytest.raises(ct.ContentError):
        ct.normalize(_guide(cover_url="javascript:alert(1)"))
    assert ct.normalize(_guide(cover_url="https://example.com/a.jpg"))["cover_url"]


def _links(guide):
    return {link["partner"]: link["url"] for step in ct.all_steps(guide) for link in step["links"]}


def test_partner_pages_are_made_from_the_guide_not_typed():
    guide = ct.normalize(_guide(steps=[
        _stop(links=[
            {"kind": "affiliate", "partner": "klook", "url": "https://evil.example/x"},
            {"kind": "affiliate", "partner": "gocity", "url": "https://evil.example/x"},
            {"kind": "affiliate", "partner": "airalo"},
            {"kind": "affiliate", "partner": "gettransfer"},
        ]),
        _stop("Louvre", 48.8606, 2.3376),
    ]))
    urls = _links(guide)
    # A pasted address is ignored: each page comes from the guide itself.
    assert urls["klook"] == "https://www.klook.com/search/result/?query=Eiffel+Tower+Paris"
    assert urls["gocity"] == "https://gocity.com/en/paris/passes"
    assert urls["airalo"] == "https://www.airalo.com/france-esim"
    query = urllib.parse.parse_qs(urllib.parse.urlparse(urls["gettransfer"]).query)
    assert query["to_name"] == ["Eiffel Tower, Paris"] and "from_name" not in query


def test_klook_searches_the_creators_words_in_the_city():
    guide = ct.normalize(_guide(steps=[
        _stop(links=[{"kind": "affiliate", "partner": "klook", "words": "Seine cruise"}]),
        _move(links=[{"kind": "affiliate", "partner": "klook", "words": "Batobus Paris"}]),
        _stop("Louvre"),
    ]))
    first, ride = [s["links"][0]["url"] for s in ct.all_steps(guide)[:2]]
    assert first.endswith("?query=Seine+cruise+Paris")
    assert ride.endswith("?query=Batobus+Paris")  # the city is not added twice


def test_a_car_on_a_ride_goes_from_the_stop_before_to_the_stop_after():
    guide = ct.normalize(_guide(steps=[
        _stop(), _move(mode="taxi", links=[{"kind": "affiliate", "partner": "gettransfer"}]), _stop("Louvre"),
    ]))
    query = urllib.parse.parse_qs(urllib.parse.urlparse(ct.all_steps(guide)[1]["links"][0]["url"]).query)
    assert query["from_name"] == ["Eiffel Tower, Paris"] and query["to_name"] == ["Louvre, Paris"]


def test_wegotrip_link_must_be_a_page_from_its_catalogue():
    good = "https://wegotrip.com/paris-d2988507/louvre-p2381/"
    for url, kept in ((good, True), ("https://wegotrip.com/about", False), ("https://evil.example/paris-d1/x-p2/", False)):
        guide = ct.normalize(_guide(steps=[
            _stop(links=[{"kind": "affiliate", "partner": "wegotrip", "url": url, "product_title": "Louvre"}]),
            _stop("Louvre"),
        ]))
        assert (_links(guide)["wegotrip"] == url) is kept
        assert ("Stop 1: pick the WeGoTrip ticket for its link." in ct.problems(guide)) is not kept


def test_go_city_only_where_it_sells_a_pass():
    guide = ct.normalize(_guide(city="Colombo", country="Sri Lanka", steps=[
        _stop(links=[{"kind": "affiliate", "partner": "gocity"}]), _stop("Galle Face"),
    ]))
    assert _links(guide)["gocity"] == ""
    assert "Stop 1: Go City has no pass for Colombo. Remove its link." in ct.problems(guide)


def test_airalo_page_names():
    assert ct.airalo_slug("France") == "france"
    assert ct.airalo_slug("United Arab Emirates") == "united-arab-emirates"
    assert ct.airalo_slug("Czechia") == "czech-republic"
    assert ct.airalo_slug("") == ""


def test_flight_partners_are_not_offered_in_guides():
    assert set(ct.AFFILIATES) == {"klook", "wegotrip", "gocity", "gettransfer", "airalo"}


def test_unknown_partner_is_refused():
    with pytest.raises(ct.ContentError, match="pick a partner"):
        ct.normalize(_guide(steps=[_stop(links=[{"kind": "affiliate", "partner": "acme", "url": ""}])]))


def test_link_ids_are_unique_across_the_whole_guide():
    link_id = str(uuid.uuid4())
    link = {"id": link_id, "kind": "affiliate", "partner": "klook", "url": ""}
    out = ct.normalize(_guide(steps=[_stop(links=[link]), _stop("Louvre", links=[dict(link)])]))
    first, second = ct.all_steps(out)[0]["links"][0]["id"], ct.all_steps(out)[1]["links"][0]["id"]
    assert first == link_id and second != link_id


def test_experience_link_keeps_only_a_wellformed_package_id():
    package_id = str(uuid.uuid4())
    out = ct.normalize(_guide(steps=[_stop(links=[
        {"kind": "experience", "package_id": package_id.upper(), "label": "Cruise"},
        {"kind": "experience", "package_id": "not-an-id"},
    ])]))
    links = ct.all_steps(out)[0]["links"]
    assert links[0]["package_id"] == package_id
    assert links[1]["package_id"] == ""


# ── problems ─────────────────────────────────────────────────────────────────

def test_complete_guide_has_no_problems():
    assert ct.problems(ct.normalize(_guide())) == []


def test_problems_name_what_is_missing():
    found = ct.problems(ct.normalize({"steps": [_move(), _stop(name="", lat=None, lng=None)]}))
    text = " ".join(found)
    assert "Add a title." in found
    assert "Add a cover photo." in found
    assert "Add at least two stops." in found
    assert "Stop 1: add its name." in found
    assert "Stop 1: put it on the map." in found


def test_problems_flag_links_without_a_target():
    guide = ct.normalize(_guide(steps=[
        _stop(links=[{"kind": "affiliate", "partner": "wegotrip", "url": ""}]),
        _move(links=[{"kind": "experience", "package_id": ""}]),
        _stop("Louvre"),
    ]))
    found = ct.problems(guide)
    assert "Stop 1: pick the WeGoTrip ticket for its link." in found
    assert "Travel to stop 2: pick the experience for each Experience link." in found


def test_problems_flag_an_experience_no_longer_listed():
    package_id = str(uuid.uuid4())
    guide = ct.normalize(_guide(steps=[
        _stop(links=[{"kind": "experience", "package_id": package_id}]), _stop("Louvre"),
    ]))
    assert ct.problems(guide, package_ok=lambda _id: True) == []
    assert ct.problems(guide, package_ok=lambda _id: False) == [
        "Stop 1: an Experience it links to is no longer listed in the app.",
    ]


# ── review ───────────────────────────────────────────────────────────────────

def test_an_edit_sends_a_guide_back_to_draft_but_keeps_a_note():
    assert ct.status_after_edit(ct.APPROVED) == ct.DRAFT
    assert ct.status_after_edit(ct.PENDING) == ct.DRAFT
    assert ct.status_after_edit(ct.DRAFT) == ct.DRAFT
    assert ct.status_after_edit(ct.CHANGES_REQUESTED) == ct.CHANGES_REQUESTED


def test_only_drafts_and_sent_back_guides_can_be_sent():
    assert ct.can_submit(ct.DRAFT) and ct.can_submit(ct.CHANGES_REQUESTED)
    assert not ct.can_submit(ct.PENDING) and not ct.can_submit(ct.APPROVED)


# ── links ────────────────────────────────────────────────────────────────────

def test_tracked_url_goes_through_travelpayouts_with_the_partners_program():
    url = ct.tracked_url("klook", "https://www.klook.com/activity/1/", marker="781739", project_id="577812")
    parsed = urllib.parse.urlparse(url)
    query = urllib.parse.parse_qs(parsed.query)
    assert parsed.netloc == "tp.media"
    assert query["campaign_id"] == ["137"] and query["p"] == ["4110"]
    assert query["marker"] == ["781739"] and query["trs"] == ["577812"]
    assert query["u"] == ["https://www.klook.com/activity/1/"]


def test_tracked_url_without_campaign_and_without_ids():
    url = ct.tracked_url("gettransfer", "https://gettransfer.com/en/transfers/new", marker="1", project_id="2")
    assert "campaign_id" not in urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
    page = "https://www.klook.com/activity/1/"
    assert ct.tracked_url("klook", page, marker="", project_id="2") == page


def test_every_affiliate_builds_a_link():
    for key, affiliate in ct.AFFILIATES.items():
        page = f"https://www.{affiliate.domains[0]}/x"
        assert ct.host_matches(page, affiliate.domains)
        query = urllib.parse.parse_qs(urllib.parse.urlparse(
            ct.tracked_url(key, page, marker="m", project_id="p")
        ).query)
        assert query["p"] == [affiliate.promo_id], key


# ── the app's view ───────────────────────────────────────────────────────────

def test_app_view_numbers_stops_and_resolves_links():
    package_id = str(uuid.uuid4())
    guide = ct.normalize(_guide(steps=[
        _stop(links=[
            {"kind": "affiliate", "partner": "klook", "url": "https://www.klook.com/a/", "label": ""},
            {"kind": "experience", "package_id": package_id, "label": ""},
            {"kind": "experience", "package_id": str(uuid.uuid4())},   # no longer listed
        ]),
        _move(mode="tuk_tuk"),
        _stop("Louvre"),
    ]))
    view = ct.app_view(
        guide,
        tap_url=lambda link_id: f"https://api/go/{link_id}",
        package_view=lambda pid: {"title": "Seine cruise"} if pid == package_id else None,
    )
    first, move, last = view["steps"]
    assert (first["number"], last["number"]) == (1, 2)
    assert move["mode_label"] == "Tuk-tuk"
    assert view["stop_count"] == 2
    assert [link["kind"] for link in first["links"]] == ["affiliate", "experience"]
    assert first["links"][0]["label"] == "Book on Klook"
    assert first["links"][0]["url"].startswith("https://api/go/")
    assert first["links"][1]["label"] == "Seine cruise"


def test_city_key_ignores_case_and_spacing():
    assert ct.city_key({"city": "New  York", "country": "USA"}) == ct.city_key({"city": "new york", "country": "usa"})


def test_step_name_says_where_a_link_sits():
    guide = ct.normalize(_guide())
    stop, move, last = ct.all_steps(guide)
    assert ct.step_name(guide, stop) == "Stop 1 · Eiffel Tower"
    assert ct.step_name(guide, move) == "Travel to stop 2 · Metro"
    assert ct.step_name(guide, last) == "Stop 2 · Louvre"


# ── Days ─────────────────────────────────────────────────────────────────────

def _days_guide(**extra):
    guide = _guide(steps=None)
    guide.pop("steps")
    guide["days"] = [
        {"title": "Eiffel Tower and Champ de Mars", "starts_at": "9:00", "steps": [
            _stop(time_here="2 hr 45 min", access_note="Open daily"),
            _move(mode="walk", duration="15 min"),
            {"type": "break", "title": "Lunch / Rest", "duration": "45 min"},
            _stop("Champ de Mars", 48.8556, 2.2986, time_here="30 min"),
        ]},
        {"title": "Palace of Versailles", "starts_at": "8:00 AM", "steps": [
            _move(mode="train", title="RER C to Versailles", duration="1 hr"),
            _stop("Palace of Versailles", 48.8049, 2.1204, time_here="3 hr"),
        ]},
    ]
    guide.update(extra)
    return guide


def test_a_guide_saved_before_days_is_one_day():
    out = ct.normalize(_guide())
    assert len(out["days"]) == 1 and "steps" not in out
    assert out["days"][0]["id"] == ct.LEGACY_DAY_ID
    assert [s["type"] for s in out["days"][0]["steps"]] == ["stop", "move", "stop"]
    # Read as stored, without saving it again.
    assert ct.days_of(_guide())[0]["id"] == ct.LEGACY_DAY_ID


def test_days_keep_their_order_title_and_start_time():
    out = ct.normalize(_days_guide())
    assert [d["title"] for d in out["days"]] == ["Eiffel Tower and Champ de Mars", "Palace of Versailles"]
    assert [d["starts_at"] for d in out["days"]] == ["09:00", "08:00"]
    assert all(uuid.UUID(d["id"]) for d in out["days"])
    brk = out["days"][0]["steps"][2]
    assert brk["type"] == "break" and brk["title"] == "Lunch / Rest" and "lat" not in brk
    assert out["days"][0]["steps"][0]["access_note"] == "Open daily"


def test_start_times():
    assert ct.start_time("09:00", "Day 1") == "09:00"
    assert ct.start_time("9:30 pm", "Day 1") == "21:30"
    assert ct.start_time("12:15 AM", "Day 1") == "00:15"
    assert ct.start_time("", "Day 1") == ""
    with pytest.raises(ct.ContentError, match="Day 2: the start time"):
        ct.start_time("25:00", "Day 2")


def test_step_ids_are_unique_across_days():
    step_id = str(uuid.uuid4())
    guide = _days_guide()
    guide["days"][0]["steps"][0]["id"] = step_id
    guide["days"][1]["steps"][1]["id"] = step_id
    out = ct.normalize(guide)
    ids = [s["id"] for s in ct.all_steps(out)]
    assert len(ids) == len(set(ids)) and ids[0] == step_id


def test_a_day_may_start_with_a_ride_and_needs_its_places_line():
    out = ct.normalize(_days_guide())
    assert ct.problems(out) == []
    out["days"][1]["title"] = ""
    assert "Day 2: add the line of places it covers, which travellers pick days by." in ct.problems(out)


def test_problems_name_the_day():
    guide = _days_guide()
    guide["days"][1]["steps"][1].update(name="", lat=None, lng=None)
    found = ct.problems(ct.normalize(guide))
    assert "Day 2 · Stop 1: add its name." in found
    assert "Day 2 · Stop 1: put it on the map." in found


def test_app_view_has_days_with_minutes_and_numbers_per_day():
    view = ct.app_view(ct.normalize(_days_guide()), tap_url=lambda i: i, package_view=lambda i: None)
    first, second = view["days"]
    assert [s["minutes"] for s in first["steps"]] == [165, 15, 45, 30]
    assert first["minutes"] == 255 and first["stop_count"] == 2 and first["starts_at"] == "09:00"
    assert [s.get("number") for s in second["steps"]] == [None, 1]
    assert view["day_count"] == 2 and view["stop_count"] == 3
    assert len(view["steps"]) == 6  # the flat list older app builds read


def test_links_on_a_ride_use_the_stops_of_its_own_day():
    guide = _days_guide()
    guide["days"][1]["steps"][0]["links"] = [{"kind": "affiliate", "partner": "gettransfer"}]
    out = ct.normalize(guide)
    query = urllib.parse.parse_qs(urllib.parse.urlparse(out["days"][1]["steps"][0]["links"][0]["url"]).query)
    # Nothing before it on its day: from the city itself, to the day's first stop.
    assert query["from_name"] == ["Paris"] and query["to_name"] == ["Palace of Versailles, Paris"]


def test_step_name_for_reports_says_the_day():
    out = ct.normalize(_days_guide())
    brk = out["days"][0]["steps"][2]
    palace = out["days"][1]["steps"][1]
    assert ct.step_name(out, brk) == "Day 1 · Break after stop 1 · Lunch / Rest"
    assert ct.step_name(out, palace) == "Day 2 · Stop 1 · Palace of Versailles"
