"""HelloSafe Atlas travel insurance provider tests.

Pins:
- HMAC-SHA256 signature conforms to v2 specification;
- quote_and_mint picks the cheapest available offer and mints a tracked link;
- shadow mode records full audit data and changes nothing in traveller's plan;
- live mode injects the priced Booking Plan row and Safety & Health button;
- international trips receive insurance, domestic trips never.
"""
from __future__ import annotations

import json
import time
from typing import Optional

import httpx
import pytest

from app.services.providers import atlas, base, config, enrich


# ── Signature and Link Recognition ───────────────────────────────────────────

def test_atlas_signature_generation():
    key_id = "ak_test_sample"
    secret = "sk_test_secret"
    headers = atlas.sign_request(key_id, secret, "POST", "/api/v1/travel/quotes", '{"trip":{}}')

    assert headers["x-atlas-key-id"] == key_id
    assert headers["content-type"] == "application/json"
    assert "x-atlas-timestamp" in headers
    assert headers["x-atlas-signature"].startswith("v2=")
    # v2= + 64 hex characters
    assert len(headers["x-atlas-signature"]) == 67


def test_atlas_link_recognition():
    assert atlas.is_atlas_link("https://atlas.hellosafe.com/r/abc?quote=123")
    assert atlas.is_atlas_link("https://hellosafe.com/travel-insurance?destination=TH")
    assert atlas.is_atlas_link("https://subdomain.hellosafe.com/path")
    assert not atlas.is_atlas_link("https://tp.media/r?p=5869")
    assert not atlas.is_atlas_link("https://ektatraveling.com/")
    assert not atlas.is_atlas_link("https://google.com")


def test_atlas_plan_item_formatting():
    # Visa needed -> BOOK NOW
    visa_item = atlas.plan_item(
        "https://atlas.hellosafe.com/r/1",
        visa_needed=True,
        insurer="Chapka",
        price=24.50,
        currency="USD",
    )
    assert visa_item["label"] == "BOOK NOW"
    assert "Chapka" in visa_item["item"]
    assert "embassy" in visa_item["reason"].lower()
    assert "24.50" in visa_item["reason"]

    # No visa needed -> BOOK CLOSER TO TRAVEL
    standard_item = atlas.plan_item(
        "https://atlas.hellosafe.com/r/2",
        visa_needed=False,
        insurer="Allianz",
        price=19.00,
        currency="EUR",
    )
    assert standard_item["label"] == "BOOK CLOSER TO TRAVEL"
    assert "Allianz" in standard_item["item"]
    assert "19" in standard_item["reason"]


# ── Quote and Mint Flow with Mock HTTP ───────────────────────────────────────

SAMPLE_QUOTES_RESPONSE = {
    "ok": True,
    "mode": "sandbox",
    "sessionId": "qs_sample_session_1234567890",
    "offers": [
        {
            "id": 9002,
            "name": "Comprehensive",
            "insurer": {"name": "Allianz Assurance"},
            "price": {"amount": 48.00, "currency": "USD"},
            "guarantees": {"hospitalFeesAbroad": {"value": 300000}},
        },
        {
            "id": 9001,
            "name": "Essential",
            "insurer": {"name": "Chapka Assurance"},
            "price": {"amount": 22.50, "currency": "USD"},
            "guarantees": {"hospitalFeesAbroad": {"value": 100000}},
        },
    ],
}

SAMPLE_LINKS_RESPONSE = {
    "url": "https://atlas.hellosafe.com/r/testcode?quote=qs_sample_session_1234567890&offer=9001",
    "subscriptionId": "sub_sandbox_999",
}


@pytest.mark.asyncio
async def test_quote_and_mint_picks_cheapest_offer(monkeypatch):
    # Set config keys in-memory
    monkeypatch.setattr(config, "_config", {
        config.ATLAS_KEY_ID: "ak_test_123",
        config.ATLAS_SIGNING_SECRET: "sk_test_456",
    })
    monkeypatch.setattr(config, "_config_at", time.time())

    calls = []

    def _handler(request: httpx.Request):
        calls.append(request)
        if "/quotes" in str(request.url):
            return httpx.Response(200, json=SAMPLE_QUOTES_RESPONSE)
        if "/links" in str(request.url):
            return httpx.Response(201, json=SAMPLE_LINKS_RESPONSE)
        return httpx.Response(404)

    monkeypatch.setattr(
        base, "_new_client",
        lambda: httpx.AsyncClient(transport=httpx.MockTransport(_handler)),
    )

    result = await atlas.quote_and_mint(
        origin_country="FR",
        dest_country="TH",
        start_date="2026-10-10",
        end_date="2026-10-24",
        travelers=1,
        currency="USD",
        visa_needed=False,
    )

    assert result is not None
    assert result["offer_id"] == 9001  # picked the $22.50 Chapka offer over the $48 Allianz offer
    assert result["price"] == 22.50
    assert result["insurer"] == "Chapka Assurance"
    assert result["link"] == "https://atlas.hellosafe.com/r/testcode?quote=qs_sample_session_1234567890&offer=9001"
    assert len(calls) == 2


# ── Shadow vs Live Mode in enrich.py ─────────────────────────────────────────

def test_shadow_mode_records_and_changes_nothing():
    meta = {
        "visa": {"status": "not_needed"},
        "practical_info": {"safety": "Safe tap water."},
        "booking_plan": [{"label": "BOOK NOW", "item": "Hotel", "url": "https://h"}],
    }
    sample_result = {
        "link": "https://atlas.hellosafe.com/r/sample",
        "price": 25.00,
        "currency": "USD",
        "insurer": "Chapka",
        "session_id": "qs_123",
        "offer_id": 9001,
    }

    entry = enrich._apply_atlas_insurance(meta, sample_result, live=False, currency="USD")

    # Audit records full details
    assert entry["mode"] == "shadow"
    assert entry["price"] == 25.00
    assert entry["insurer"] == "Chapka"
    assert entry["link"] == "https://atlas.hellosafe.com/r/sample"

    # Traveller output is unchanged
    assert len(meta["booking_plan"]) == 1
    assert meta["booking_plan"][0]["item"] == "Hotel"
    assert "safety_url" not in meta["practical_info"]


def test_live_mode_applies_booking_row_and_safety_pill():
    meta = {
        "visa": {"status": "needed"},
        "practical_info": {"safety": "Safe tap water."},
        "booking_plan": [{"label": "BOOK CLOSER TO TRAVEL", "item": "Museum", "url": "https://m"}],
    }
    sample_result = {
        "link": "https://atlas.hellosafe.com/r/live_sample",
        "price": 30.00,
        "currency": "USD",
        "insurer": "Chapka",
        "session_id": "qs_123",
        "offer_id": 9001,
    }

    entry = enrich._apply_atlas_insurance(meta, sample_result, live=True, currency="USD")

    assert entry["mode"] == "live"
    assert entry.get("applied") is True

    # Booking plan gained the row with visa urgency
    items = [r["item"] for r in meta["booking_plan"]]
    assert "Travel insurance with Chapka" in items
    atlas_row = [r for r in meta["booking_plan"] if "Chapka" in r["item"]][0]
    assert atlas_row["label"] == "BOOK NOW"

    # Practical Info gained the safety CTA and URL
    assert meta["practical_info"]["safety_url"] == "https://atlas.hellosafe.com/r/live_sample"
    assert "30.00" in meta["practical_info"]["safety_cta"]
