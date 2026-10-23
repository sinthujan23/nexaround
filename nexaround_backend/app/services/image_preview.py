"""Tiny stand-ins for story and experience photos, shown blurred while the real
ones load.

Each preview is the photo shrunk to PREVIEW_SIDE px on its long side and saved
as a low-quality WebP, base64 encoded: about 300 characters, small enough to
ride along in the feed response. The app draws it scaled up and blurred where
the photo goes, so a card shows the photo's colours at once instead of a
spinner, and the photo fades in over it.

Only files this server holds (`/static/...`) get one. Upload names are random
and never rewritten, so a preview is cached in Redis by URL; the expiry only
lets the photos of deleted stories fall out.
"""
import asyncio
import base64
import io
import logging
import os
from typing import Iterable, Optional

from PIL import Image, ImageOps

from app.core.rate_limiter import get_redis_client

logger = logging.getLogger(__name__)

PREVIEW_SIDE = 32
_QUALITY = 40
_STATIC_URL = "/static/"
_STATIC_DIR = "app/static"
_KEY = "img_preview:v1:"
_TTL_SECONDS = 90 * 24 * 60 * 60
# Cached for a file that is missing or not an image, so it isn't opened again
# on every feed load.
_NO_PREVIEW = "-"
# Uploads are capped at 10 MB, but a PNG that size can still claim a huge
# canvas; one that big is skipped rather than decoded.
_MAX_PIXELS = 60_000_000


def _local_path(url: str) -> Optional[str]:
    """The file behind a `/static/...` URL, or None for anything else."""
    if not url or not url.startswith(_STATIC_URL):
        return None
    path = os.path.normpath(os.path.join(_STATIC_DIR, url[len(_STATIC_URL):]))
    # Story URLs come from the app, so "/static/../.env" must not get out.
    if not path.startswith(_STATIC_DIR + os.sep):
        return None
    return path


def preview_of_file(path: str) -> Optional[str]:
    """Base64 WebP of the photo at `path`, at most PREVIEW_SIDE px a side."""
    try:
        with Image.open(path) as im:
            if im.width * im.height > _MAX_PIXELS:
                return None
            # A JPEG decodes straight at 1/8 size or so; other formats ignore it.
            im.draft("RGB", (PREVIEW_SIDE * 4, PREVIEW_SIDE * 4))
            # Turned the way the phone shows it: the app honours EXIF too.
            small = ImageOps.exif_transpose(im)
            has_alpha = small.mode in ("RGBA", "LA", "P", "PA")
            small = small.convert("RGBA" if has_alpha else "RGB")
            small.thumbnail((PREVIEW_SIDE, PREVIEW_SIDE), Image.LANCZOS)
            if has_alpha:
                white = Image.new("RGBA", small.size, (255, 255, 255, 255))
                small = Image.alpha_composite(white, small).convert("RGB")
            out = io.BytesIO()
            small.save(out, "WEBP", quality=_QUALITY)
            return base64.b64encode(out.getvalue()).decode("ascii")
    except Exception as e:
        logger.info("No preview for %s: %s", path, e)
        return None


def _make_all(urls: list[str]) -> dict[str, str]:
    return {u: preview_of_file(_local_path(u)) or _NO_PREVIEW for u in urls}


async def previews_for(urls: Iterable[str]) -> dict[str, str]:
    """{url: preview} for those of `urls` that have one. Never raises."""
    wanted = list(dict.fromkeys(u for u in urls if _local_path(u)))
    if not wanted:
        return {}
    found: dict[str, str] = {}
    try:
        redis = await get_redis_client()
        if redis:
            cached = await redis.mget([_KEY + u for u in wanted])
            found = {u: v for u, v in zip(wanted, cached) if v}
        missing = [u for u in wanted if u not in found]
        if missing:
            made = await asyncio.to_thread(_make_all, missing)
            found.update(made)
            if redis:
                pipe = redis.pipeline()
                for u, v in made.items():
                    pipe.set(_KEY + u, v, ex=_TTL_SECONDS)
                await pipe.execute()
    except Exception as e:
        logger.warning("Story photo previews failed: %s", e)
    return {u: v for u, v in found.items() if v != _NO_PREVIEW}
