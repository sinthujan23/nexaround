"""Package descriptions are light Markdown; older app versions get plain text."""
from app.schemas.experience import ExperiencePackageDetail
from app.services.experience_format import strip_markdown


def test_headings_bold_and_italic_lose_their_symbols():
    text = "## Your Experience\n**Duration:** 6 hours, *very* scenic"
    assert strip_markdown(text) == "Your Experience\nDuration: 6 hours, very scenic"


def test_lists_become_bullets_and_dividers_become_a_gap():
    text = "Intro\n\n- one\n- two\n\n---\n\n1. first"
    assert strip_markdown(text) == "Intro\n\n• one\n• two\n\n1. first"


def test_plain_text_and_line_breaks_are_untouched():
    text = "🐘 Anakulam\nWhere the wild meets the wonderful.\n\nSecond para"
    assert strip_markdown(text) == text


def test_unrelated_asterisks_and_symbols_survive():
    assert strip_markdown("5 * 3 = 15, rated 4*") == "5 * 3 = 15, rated 4*"
    assert strip_markdown("Price: ₹5,500 per vehicle (6 pax)") == "Price: ₹5,500 per vehicle (6 pax)"


def test_nothing_in_nothing_out():
    assert strip_markdown(None) is None
    assert strip_markdown("") == ""


def test_detail_carries_both_forms():
    fields = ExperiencePackageDetail.model_fields
    assert "description" in fields and "description_md" in fields
