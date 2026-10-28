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
    assert [s["type"] for s in out["steps"]] == ["stop", "move", "stop"]
    assert all(uuid.UUID(s["id"]) for s in out["steps"])


def test_normalize_keeps_good_ids_and_replaces_duplicates():
    step_id = str(uuid.uuid4())
    out = ct.normalize(_guide(steps=[_stop(id=step_id), _stop("Louvre", id=step_id)]))
    assert out["steps"][0]["id"] == step_id
    assert out["steps"][1]["id"] != step_id


def test_normalize_drops_half_a_pin_and_bad_coordinates():
    out = ct.normalize(_guide(steps=[_stop(lat=48.8, lng=None), _stop(lat=200, lng=2.0)]))
    assert out["steps"][0]["lat"] is None and out["steps"][0]["lng"] is None
    assert out["steps"][1]["lat"] is None and out["steps"][1]["lng"] is None


def test_unknown_transport_mode_becomes_walk():
    out = ct.normalize(_guide(steps=[_stop(), _move(mode="teleport")]))
    assert out["steps"][1]["mode"] == "walk"


def test_too_long_text_is_refused_with_the_editors_words():
    with pytest.raises(ct.ContentError, match="Title is too long"):
        ct.normalize(_guide(title="x" * 121))
    with pytest.raises(ct.ContentError, match="Step 1: the name is too long"):
        ct.normalize(_guide(steps=[_stop(name="x" * 121)]))


def test_photo_must_be_an_upload_or_https():
    with pytest.raises(ct.ContentError):
        ct.normalize(_guide(cover_url="javascript:alert(1)"))
    assert ct.normalize(_guide(cover_url="https://example.com/a.jpg"))["cover_url"]


def test_affiliate_link_must_be_on_the_partners_own_site():
    good = {"kind": "affiliate", "partner": "klook", "url": "https://www.klook.com/activity/123/"}
    out = ct.normalize(_guide(steps=[_stop(links=[good])]))
    assert out["steps"][0]["links"][0]["url"] == good["url"]

    for url in (
        "http://www.klook.com/activity/123/",       # not https
        "https://klook.com.evil.example/activity",  # look-alike host
        "https://www.gocity.com/en/paris",          # another partner's site
    ):
        bad = dict(good, url=url)
        with pytest.raises(ct.ContentError, match="klook.com"):
            ct.normalize(_guide(steps=[_stop(links=[bad])]))


def test_unknown_partner_is_refused():
    with pytest.raises(ct.ContentError, match="pick a partner"):
        ct.normalize(_guide(steps=[_stop(links=[{"kind": "affiliate", "partner": "acme", "url": ""}])]))


def test_link_ids_are_unique_across_the_whole_guide():
    link_id = str(uuid.uuid4())
    link = {"id": link_id, "kind": "affiliate", "partner": "klook", "url": ""}
    out = ct.normalize(_guide(steps=[_stop(links=[link]), _stop("Louvre", links=[dict(link)])]))
    first, second = out["steps"][0]["links"][0]["id"], out["steps"][1]["links"][0]["id"]
    assert first == link_id and second != link_id


def test_experience_link_keeps_only_a_wellformed_package_id():
    package_id = str(uuid.uuid4())
    out = ct.normalize(_guide(steps=[_stop(links=[
        {"kind": "experience", "package_id": package_id.upper(), "label": "Cruise"},
        {"kind": "experience", "package_id": "not-an-id"},
    ])]))
    links = out["steps"][0]["links"]
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
    assert "Start with a stop" in text
    assert "Stop 1: add its name." in found
    assert "Stop 1: put it on the map." in found


def test_problems_flag_links_without_a_target():
    guide = ct.normalize(_guide(steps=[
        _stop(links=[{"kind": "affiliate", "partner": "gocity", "url": ""}]),
        _move(links=[{"kind": "experience", "package_id": ""}]),
        _stop("Louvre"),
    ]))
    found = ct.problems(guide)
    assert "Stop 1: paste the Go City page for its link." in found
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
    url = ct.tracked_url("aviasales", "https://www.aviasales.com/search/X", marker="1", project_id="2")
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
    stop, move, last = guide["steps"]
    assert ct.step_name(guide, stop) == "Stop 1 · Eiffel Tower"
    assert ct.step_name(guide, move) == "Travel to stop 2 · Metro"
    assert ct.step_name(guide, last) == "Stop 2 · Louvre"
