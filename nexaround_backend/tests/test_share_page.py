"""The public share page for an experience (app/api/share.py).

It renders vendor-entered text into HTML that anyone can open, and link
previews depend on its Open Graph tags, so both are pinned here.
"""

import uuid

from app.api.share import (
    absolute_image_url, render_experience_page, render_not_found_page, share_url,
)
from app.schemas.experience import ExperiencePackageCard


def _card(**overrides) -> ExperiencePackageCard:
    fields = dict(
        id=uuid.UUID("11111111-2222-3333-4444-555555555555"),
        title="Sunset Boat Ride",
        summary="Two hours on the lagoon at golden hour.",
        category="boat",
        vendor_id=uuid.uuid4(),
        vendor_name="Blue Lagoon Tours",
        cover_photo_url="/static/uploads/experiences/abc.jpg",
        price_label="LKR 4,500 / person",
        duration_label="2h",
        latitude=8.57,
        longitude=81.23,
    )
    fields.update(overrides)
    return ExperiencePackageCard(**fields)


def test_share_url_is_on_the_public_site():
    assert share_url(_card().id) == "https://nexaround.com/e/11111111-2222-3333-4444-555555555555"


def test_page_carries_open_graph_tags_for_link_previews():
    html = render_experience_page(_card())
    assert '<meta property="og:title" content="Sunset Boat Ride · Blue Lagoon Tours">' in html
    assert 'content="https://api.nexaround.com/static/uploads/experiences/abc.jpg"' in html
    assert '<meta property="og:url" content="https://nexaround.com/e/11111111-2222-3333-4444-555555555555">' in html
    assert 'name="twitter:card" content="summary_large_image"' in html
    assert "LKR 4,500 / person · 2h" in html


def test_vendor_text_is_escaped():
    html = render_experience_page(_card(
        title='<script>alert(1)</script>',
        vendor_name='"><img src=x onerror=alert(1)>',
        summary="Tom & Jerry's <b>trip</b>",
    ))
    assert "<script>alert(1)</script>" not in html
    assert "<img src=x" not in html
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html
    assert "Tom &amp; Jerry&#x27;s &lt;b&gt;trip&lt;/b&gt;" in html


def test_no_photo_means_no_image_tag_and_a_small_card():
    html = render_experience_page(_card(cover_photo_url=None))
    assert "og:image" not in html
    assert 'name="twitter:card" content="summary"' in html


def test_only_fetchable_image_urls_are_used():
    assert absolute_image_url("https://cdn.example.com/a.jpg") == "https://cdn.example.com/a.jpg"
    assert absolute_image_url("/static/a.jpg") == "https://api.nexaround.com/static/a.jpg"
    assert absolute_image_url("data:image/png;base64,AAAA") is None
    assert absolute_image_url(None) is None


def test_open_in_app_targets_this_package():
    html = render_experience_page(_card())
    assert "intent://nexaround.com/e/11111111-2222-3333-4444-555555555555#Intent;scheme=https;package=com.nexaround.app" in html
    assert "nexaround:///e/11111111-2222-3333-4444-555555555555" in html


def test_not_found_page_offers_the_stores_but_no_open_button_script():
    html = render_not_found_page()
    assert "no longer available" in html
    assert "play.google.com/store/apps/details?id=com.nexaround.app" in html
    assert "intent://" not in html
