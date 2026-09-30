"""EKTA: a travel-insurance link for trips abroad.

EKTA sells travel insurance worldwide, and Travelpayouts pays 25% of the
policy: the highest rate of any partner here. Many embassies want insurance
with a visa application (a Schengen visa needs medical cover), so on a trip
that needs a visa the row sits under "BOOK NOW", ahead of everything booked
"after visa".

Only a link, never a price or a cover amount. A price depends on the
traveller's age, destination and days, and EKTA's own page sets it; the
plan says nothing about cover it cannot read. Travelpayouts credits EKTA to
campaign 225, promo 5869: tp.media lands on ektatraveling.com with
sub_id=<click>-781739 (checked 2026-09-30). Bookings count on the website,
not in an app.

Note, 2026-09-30: ektatraveling.com's certificate expired on 14 Sep 2026 on
both servers our server reaches (AWS Singapore), which a browser shows as a
"connection is not private" warning. The switch stays in shadow until a
phone opens the page without one.
"""
from __future__ import annotations

import urllib.parse

_AFFILIATE_REDIRECT = "https://tp.media/r"
CAMPAIGN_ID = "225"
PROMO_ID = "5869"
SITE = "https://ektatraveling.com/"

PARTNER_NAME = "EKTA travel insurance"
BUTTON_LABEL = "Get travel insurance"


def booking_link(*, marker: str, project_id: str) -> str:
    """EKTA's page through Travelpayouts, so a policy earns us a share.

    Without both the partner ID and the Project ID it still opens the page.
    """
    if not (marker and project_id):
        return SITE
    return _AFFILIATE_REDIRECT + "?" + urllib.parse.urlencode({
        "campaign_id": CAMPAIGN_ID, "marker": marker, "p": PROMO_ID, "trs": project_id, "u": SITE,
    })


def is_ekta_link(url: str) -> bool:
    parsed = urllib.parse.urlparse(str(url or ""))
    if parsed.netloc == "tp.media":
        return urllib.parse.parse_qs(parsed.query).get("p") == [PROMO_ID]
    return parsed.netloc == "ektatraveling.com" or parsed.netloc.endswith(".ektatraveling.com")


def plan_item(link: str, *, visa_needed: bool) -> dict:
    """The Booking Plan row: before the visa when one is needed, since many
    embassies ask for insurance with the application."""
    if visa_needed:
        return {
            "label": "BOOK NOW",
            "item": "Travel insurance with EKTA",
            "reason": (
                "Many embassies ask for travel insurance with the visa application. "
                "Check the cover your embassy requires before you buy."
            ),
            "url": link,
        }
    return {
        "label": "BOOK CLOSER TO TRAVEL",
        "item": "Travel insurance with EKTA",
        "reason": "Covers medical costs and trip problems abroad. Compare plans and cover on EKTA.",
        "url": link,
    }
