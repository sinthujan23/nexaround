"""Public share pages: what a shared experience link opens.

The app shares `https://nexaround.com/e/<package id>`. nginx on nexaround.com
proxies `/e/` here. Three kinds of visitor reach it:

* A phone with the app installed never gets here: Android App Links and iOS
  Universal Links (website/.well-known/) hand the URL straight to the app.
* A phone without the app sees the package and the store buttons.
* WhatsApp, Facebook and X fetch it for the link preview. They read the Open
  Graph tags and run no JavaScript, which is why this is rendered server-side
  and not a page of the website's SPA.

Everything shown is vendor-entered text, so every value is HTML-escaped.
"""

import uuid
from html import escape
from typing import Optional

from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.repositories.experience_repository import ExperienceRepository
from app.schemas.experience import ExperiencePackageCard
from app.services.experience_service import package_to_card

router = APIRouter(prefix="/share", tags=["Share"], include_in_schema=False)

ANDROID_PACKAGE = "com.nexaround.app"
APP_STORE_ID = "6806252363"
PLAY_STORE_URL = f"https://play.google.com/store/apps/details?id={ANDROID_PACKAGE}"
APP_STORE_URL = f"https://apps.apple.com/app/id{APP_STORE_ID}"

_CATEGORY_LABELS = {
    "boat": "Boat ride",
    "water_sports": "Water sports",
    "guided_tour": "Guided tour",
    "wildlife": "Wildlife",
    "cultural": "Cultural",
    "adventure": "Adventure",
    "food": "Food",
}


def share_url(package_id: uuid.UUID) -> str:
    return f"{settings.PUBLIC_SITE_URL.rstrip('/')}/e/{package_id}"


def absolute_image_url(url: Optional[str]) -> Optional[str]:
    """An image URL a crawler can fetch, or None.

    Uploads are stored as origin-relative `/static/...` paths. Anything that is
    neither that nor http(s) — an inline data: URI, say — is left out: preview
    crawlers will not render it.
    """
    if not url:
        return None
    if url.startswith("https://") or url.startswith("http://"):
        return url
    if url.startswith("/"):
        return f"{settings.PUBLIC_BASE_URL.rstrip('/')}{url}"
    return None


def _truncate(text: str, limit: int) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def render_experience_page(card: ExperiencePackageCard) -> str:
    url = share_url(card.id)
    image = absolute_image_url(card.cover_photo_url)
    details = " · ".join(p for p in (card.price_label, card.duration_label) if p)
    summary = (card.summary or "").strip()

    og_title = f"{card.title} · {card.vendor_name}" if card.vendor_name else card.title
    og_description = _truncate(" — ".join(p for p in (details, summary) if p), 200) \
        or "An experience on nexARound."
    category = _CATEGORY_LABELS.get(card.category or "", "Experience")

    e = lambda s: escape(s or "", quote=True)  # noqa: E731

    image_meta = (
        f'<meta property="og:image" content="{e(image)}">\n'
        f'  <meta name="twitter:image" content="{e(image)}">'
        if image else ""
    )
    photo = (
        f'<img class="photo" src="{e(image)}" alt="">'
        if image else '<div class="photo placeholder">🏝️</div>'
    )

    body = f"""
    <article class="card">
      {photo}
      <div class="body">
        <span class="pill">{e(category)}</span>
        <h1>{e(card.title)}</h1>
        <p class="vendor">by {e(card.vendor_name)}</p>
        {f'<p class="details">{e(details)}</p>' if details else ''}
        {f'<p class="summary">{e(summary)}</p>' if summary else ''}
      </div>
    </article>"""

    return _page(
        title=og_title,
        description=og_description,
        url=url,
        head_extra=image_meta,
        twitter_card="summary_large_image" if image else "summary",
        # Lets iOS Safari offer "Open" in its own banner when the app is installed.
        app_argument=url,
        body=body,
        open_path=f"e/{card.id}",
    )


def render_not_found_page() -> str:
    body = """
    <article class="card">
      <div class="photo placeholder">🧭</div>
      <div class="body">
        <h1>This experience is no longer available</h1>
        <p class="summary">It may have been removed by the operator. There are plenty more
        to discover in the nexARound app.</p>
      </div>
    </article>"""
    return _page(
        title="Experience not available · nexARound",
        description="Discover local experiences near you with nexARound.",
        url=settings.PUBLIC_SITE_URL,
        head_extra="",
        twitter_card="summary",
        app_argument=None,
        body=body,
        open_path=None,
    )


def _page(
    *, title, description, url, head_extra, twitter_card, app_argument, body, open_path,
) -> str:
    e = lambda s: escape(s or "", quote=True)  # noqa: E731
    smart_banner = f"app-id={APP_STORE_ID}" + (f", app-argument={app_argument}" if app_argument else "")

    # "Open in the app" is for the case where the OS did not hand the link to
    # the app by itself: a link opened inside another app's browser, or before
    # link verification has happened. Android gets an intent: URL that names
    # the package (it falls back to Play when the app is missing); iOS gets the
    # app's own nexaround:// scheme. Desktop never sees the button.
    open_script = ""
    if open_path:
        open_script = f"""
  <script>
    (function () {{
      var btn = document.getElementById('open-app');
      var ua = navigator.userAgent || '';
      var fallback = encodeURIComponent('{PLAY_STORE_URL}');
      if (/android/i.test(ua)) {{
        btn.href = 'intent://{e(_host())}/{open_path}#Intent;scheme=https;package={ANDROID_PACKAGE};S.browser_fallback_url=' + fallback + ';end';
        btn.hidden = false;
      }} else if (/iphone|ipad|ipod/i.test(ua)) {{
        // Empty host (three slashes): Flutter routes by the URL's path, and
        // with nexaround://e/<id> the "e" would be read as the host.
        btn.href = 'nexaround:///{open_path}';
        btn.hidden = false;
      }}
    }})();
  </script>"""

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{e(title)}</title>
  <meta name="description" content="{e(description)}">
  <link rel="canonical" href="{e(url)}">
  <link rel="icon" href="/favicon.png">
  <meta name="apple-itunes-app" content="{e(smart_banner)}">
  <meta property="og:site_name" content="nexARound">
  <meta property="og:type" content="website">
  <meta property="og:title" content="{e(title)}">
  <meta property="og:description" content="{e(description)}">
  <meta property="og:url" content="{e(url)}">
  <meta name="twitter:card" content="{twitter_card}">
  <meta name="twitter:title" content="{e(title)}">
  <meta name="twitter:description" content="{e(description)}">
  {head_extra}
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f3f6f7; color: #121212; min-height: 100vh;
      display: flex; flex-direction: column; align-items: center; padding: 24px 16px 40px;
    }}
    .brand {{ display: flex; align-items: center; gap: 10px; margin-bottom: 20px;
      font-weight: 800; font-size: 20px; color: #007a7c; text-decoration: none; }}
    .brand img {{ width: 36px; height: 36px; }}
    .card {{ width: 100%; max-width: 440px; background: #fff; border-radius: 24px;
      overflow: hidden; box-shadow: 0 12px 32px rgba(0,0,0,0.08); }}
    .photo {{ display: block; width: 100%; aspect-ratio: 16 / 10; object-fit: cover; }}
    .placeholder {{ display: flex; align-items: center; justify-content: center; font-size: 56px;
      background: linear-gradient(135deg, #00a3a6, #005e60); }}
    .body {{ padding: 20px 20px 24px; }}
    .pill {{ display: inline-block; padding: 4px 12px; border-radius: 999px; background: #e6f3f3;
      color: #007a7c; font-size: 12px; font-weight: 700; margin-bottom: 10px; }}
    h1 {{ font-size: 22px; line-height: 1.25; font-weight: 800; }}
    .vendor {{ margin-top: 6px; color: #007a7c; font-weight: 600; font-size: 15px; }}
    .details {{ margin-top: 12px; font-size: 17px; font-weight: 800; }}
    .summary {{ margin-top: 10px; color: #545454; font-size: 15px; line-height: 1.5; }}
    .actions {{ width: 100%; max-width: 440px; margin-top: 20px; display: flex; flex-direction: column; gap: 10px; }}
    .btn {{ display: block; text-align: center; padding: 15px; border-radius: 14px; font-weight: 700;
      font-size: 16px; text-decoration: none; }}
    .btn[hidden] {{ display: none; }}
    .primary {{ background: #007a7c; color: #fff; }}
    .store {{ background: #fff; color: #121212; border: 1px solid #e2e2e2; }}
    .note {{ margin-top: 16px; font-size: 13px; color: #7a7a7a; text-align: center; max-width: 440px; }}
  </style>
</head>
<body>
  <a class="brand" href="{e(settings.PUBLIC_SITE_URL)}">
    <img src="/app_icon.png" alt="" onerror="this.remove()">nexARound
  </a>
  {body}
  <div class="actions">
    <a id="open-app" class="btn primary" href="#" hidden>Open in the nexARound app</a>
    <a class="btn store" href="{PLAY_STORE_URL}">Get it on Google Play</a>
    <a class="btn store" href="{APP_STORE_URL}">Download on the App Store</a>
  </div>
  <p class="note">Get the nexARound app to see details, contact the operator and send a booking request.</p>
  {open_script}
</body>
</html>"""


def _host() -> str:
    return settings.PUBLIC_SITE_URL.split("://", 1)[-1].rstrip("/")


_HEADERS = {
    # Short: an edited package should show its new title in fresh previews
    # without anyone waiting a day.
    "Cache-Control": "public, max-age=300",
}


@router.get("/e/{package_id}", response_class=HTMLResponse)
async def share_experience(package_id: str, db: AsyncSession = Depends(get_db)):
    # A str, parsed here, so a mangled link gets the friendly page and not a
    # JSON validation error.
    try:
        pid = uuid.UUID(package_id)
    except ValueError:
        return HTMLResponse(render_not_found_page(), status_code=404, headers=_HEADERS)

    # Published only: a hidden package, or one whose vendor is suspended, must
    # not be viewable just because someone kept the link.
    package = await ExperienceRepository(db).get_package(pid, published_only=True)
    if package is None:
        return HTMLResponse(render_not_found_page(), status_code=404, headers=_HEADERS)

    return HTMLResponse(render_experience_page(package_to_card(package)), headers=_HEADERS)
