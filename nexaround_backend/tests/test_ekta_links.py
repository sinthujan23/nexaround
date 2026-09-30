"""EKTA: travel insurance on trips to another country (user, 2026-09-30).

What these pin:
- the link is EKTA's page credited to us the way Travelpayouts' Links API
  credits EKTA (campaign 225, promo 5869);
- only a trip to another country gets it, a short hop over the border
  included, and a trip at home never;
- with a visa to get it is booked now, since embassies ask for insurance
  with the application; no price and no cover are named;
- live adds the Booking Plan row and the Safety button's link; shadow and off
  change nothing.
"""
import time

from app.services.providers import config, ekta, enrich

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)


def test_the_link_is_credited_to_us_through_travelpayouts():
    assert ekta.booking_link(marker="781739", project_id="577812") == (
        "https://tp.media/r?campaign_id=225&marker=781739&p=5869&trs=577812&u=https%3A%2F%2Fektatraveling.com%2F"
    )
    assert ekta.booking_link(marker="781739", project_id="") == "https://ektatraveling.com/"


def test_ekta_links_are_recognised_and_others_are_not():
    assert ekta.is_ekta_link(ekta.booking_link(marker="1", project_id="2"))
    assert ekta.is_ekta_link("https://ektatraveling.com/?sub_id=x")
    assert not ekta.is_ekta_link("https://tp.media/r?campaign_id=541&p=8310&u=x")   # Airalo
    assert not ekta.is_ekta_link("https://notektatraveling.com/")


def test_with_a_visa_to_get_insurance_is_booked_now():
    row = ekta.plan_item("https://tp.media/r?x", visa_needed=True)
    assert row["label"] == "BOOK NOW"
    assert "visa application" in row["reason"]
    row = ekta.plan_item("https://tp.media/r?x", visa_needed=False)
    assert row["label"] == "BOOK CLOSER TO TRAVEL"
    for visa in (True, False):
        text = " ".join(ekta.plan_item("u", visa_needed=visa).values())
        assert not any(ch.isdigit() for ch in text), "no price, no cover amount"


def test_live_adds_the_row_and_the_safety_button_once():
    meta = {"visa": {"status": "not_needed"}, "practical_info": {"safety": "Tap water is safe."},
            "booking_plan": [{"label": "BOOK NOW", "item": "Hotel", "reason": "", "url": "https://h"}]}
    for _ in range(2):
        entry = enrich._apply_insurance(meta, live=True, marker="781739", project_id="577812")
    assert [r["item"] for r in meta["booking_plan"]] == ["Hotel", "Travel insurance with EKTA"]
    assert meta["practical_info"] == {
        "safety": "Tap water is safe.",
        "safety_url": ekta.booking_link(marker="781739", project_id="577812"),
        "safety_cta": "Get travel insurance",
    }
    assert entry == {"mode": "live", "visa_needed": False, "applied": True}


def test_shadow_records_the_link_and_changes_nothing():
    meta = {"visa": {"status": "needed"}, "booking_plan": []}
    entry = enrich._apply_insurance(meta, live=False, marker="781739", project_id="577812")
    assert meta == {"visa": {"status": "needed"}, "booking_plan": []}
    assert entry["visa_needed"] is True and entry["link"].startswith("https://tp.media/r?campaign_id=225")


# ── End to end through generate_odyssey ──────────────────────────────────────

def _switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


def _insurance_rows(meta):
    return [r for r in meta.get("booking_plan") or [] if r["item"] == "Travel insurance with EKTA"]


def test_a_trip_abroad_with_a_visa_gets_it_first(world, monkeypatch):
    # The e2e world: Colombo, Sri Lanka → India, with an e-visa to get.
    _switches(monkeypatch, ekta="live")
    _, meta, _ = e2e.run(world)
    rows = _insurance_rows(meta)
    assert len(rows) == 1 and rows[0]["label"] == "BOOK NOW"
    assert meta["practical_info"]["safety_cta"] == "Get travel insurance"


def test_a_trip_at_home_gets_no_insurance(world, monkeypatch):
    _switches(monkeypatch, ekta="live")
    _, meta, _ = e2e.run(world, include_flights=False, departure_city="Nagpur", departure_country="India")
    assert not _insurance_rows(meta)
    assert "safety_url" not in (meta.get("practical_info") or {})
    assert "ekta" not in meta["provider_audit"]


def test_off_adds_nothing(world):
    _, meta, _ = e2e.run(world)
    assert not _insurance_rows(meta)
    assert "ekta" not in meta.get("provider_audit", {})
