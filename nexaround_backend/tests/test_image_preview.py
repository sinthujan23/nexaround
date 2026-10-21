"""Blur previews of story photos (app/services/image_preview.py).

The feed sends each photo's preview with the story; these check the preview
itself and which URLs may get one. No Redis or database needed.
"""
import asyncio
import base64
import io

from PIL import Image

from app.services import image_preview
from app.services.image_preview import PREVIEW_SIDE, _local_path, preview_of_file


def decoded(preview: str) -> Image.Image:
    return Image.open(io.BytesIO(base64.b64decode(preview)))


def test_preview_is_a_tiny_webp_with_the_photo_shape(tmp_path):
    path = tmp_path / "photo.jpg"
    Image.new("RGB", (3000, 2000), (30, 120, 200)).save(path, "JPEG")

    preview = preview_of_file(str(path))

    im = decoded(preview)
    assert im.format == "WEBP"
    assert im.size == (PREVIEW_SIDE, round(PREVIEW_SIDE * 2 / 3))
    assert len(preview) < 1000


def test_preview_is_turned_like_the_phone_shows_the_photo(tmp_path):
    path = tmp_path / "portrait.jpg"
    exif = Image.Exif()
    exif[0x0112] = 6  # Orientation: rotate 90° clockwise to view
    Image.new("RGB", (400, 300), (200, 50, 50)).save(path, "JPEG", exif=exif)

    w, h = decoded(preview_of_file(str(path))).size
    assert h > w


def test_transparent_png_gets_a_white_background(tmp_path):
    path = tmp_path / "logo.png"
    Image.new("RGBA", (200, 200), (0, 0, 0, 0)).save(path, "PNG")

    r, g, b = decoded(preview_of_file(str(path))).convert("RGB").getpixel((5, 5))
    assert min(r, g, b) > 230


def test_no_preview_for_a_missing_or_broken_file(tmp_path):
    broken = tmp_path / "broken.jpg"
    broken.write_bytes(b"not an image")
    assert preview_of_file(str(broken)) is None
    assert preview_of_file(str(tmp_path / "gone.jpg")) is None


def test_only_files_under_static_qualify():
    assert _local_path("/static/uploads/a.jpg") == "app/static/uploads/a.jpg"
    assert _local_path("/static/uploads/experiences/b.jpg") == "app/static/uploads/experiences/b.jpg"
    assert _local_path("https://example.com/a.jpg") is None
    assert _local_path("/data/user/0/cache/a.jpg") is None
    assert _local_path("/static/../.env") is None
    assert _local_path("/static/uploads/../../main.py") is None
    assert _local_path("") is None


def test_previews_for_skips_photos_without_one(tmp_path, monkeypatch):
    (tmp_path / "uploads").mkdir()
    Image.new("RGB", (100, 80), (10, 200, 10)).save(tmp_path / "uploads" / "ok.jpg", "JPEG")
    monkeypatch.setattr(image_preview, "_STATIC_DIR", str(tmp_path))

    async def no_redis():
        return None
    monkeypatch.setattr(image_preview, "get_redis_client", no_redis)

    previews = asyncio.run(image_preview.previews_for([
        "/static/uploads/ok.jpg", "/static/uploads/gone.jpg", "https://x.test/a.jpg",
        "/static/uploads/ok.jpg",
    ]))
    assert list(previews) == ["/static/uploads/ok.jpg"]
