"""Place photos without Google: link cleaning, approved photos, uploads.

No database writes (the suite runs against production) and no files outside a
temporary folder.
"""
import asyncio
import io
import os
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from PIL import Image

from app.services import place_photos

GOOGLE = "/api/v1/places/photo?ref=places/ABC/photos/XYZ&i=0"
OURS = "/static/uploads/place_photos/abc.webp"
WIKI = "https://upload.wikimedia.org/x.jpg"


def _jpeg(w=1200, h=900) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (w, h), (30, 120, 90)).save(buf, format="JPEG")
    return buf.getvalue()


# ── Google links ────────────────────────────────────────────────────────────

def test_unsaved_google_links_are_dropped_while_photos_are_off(monkeypatch):
    monkeypatch.setattr(place_photos, "_google_photo_saved", lambda url: False)
    assert place_photos.usable_photo_urls([GOOGLE, OURS, WIKI], google_on=False) == [OURS, WIKI]


def test_saved_google_photos_stay(monkeypatch):
    monkeypatch.setattr(place_photos, "_google_photo_saved", lambda url: True)
    assert place_photos.usable_photo_urls([GOOGLE], google_on=False) == [GOOGLE]


def test_nothing_is_dropped_while_photos_are_on(monkeypatch):
    def must_not_check(url):
        raise AssertionError("no disk checks while Google photos are on")
    monkeypatch.setattr(place_photos, "_google_photo_saved", must_not_check)
    assert place_photos.usable_photo_urls([GOOGLE], google_on=True) == [GOOGLE]


def test_saved_check_reads_ref_index_and_width(monkeypatch, tmp_path):
    from app.services import photo_cache_service
    seen = {}

    def path(ref, width, index):
        seen.update(ref=ref, width=width, index=index)
        f = tmp_path / "p"
        f.write_bytes(b"x")
        return f

    monkeypatch.setattr(photo_cache_service, "cached_path", path)
    assert place_photos._google_photo_saved(
        "/api/v1/places/photo?ref=places/A/photos/B&i=1&maxwidth=1080")
    assert seen == {"ref": "places/A/photos/B", "width": 1080, "index": 1}


# ── The order: saved Google photo, Wikipedia/Unsplash, approved, none ───────

def _setup(monkeypatch, *, found=None, approved=None, credit_ok=True, google_on=False):
    queued = []

    async def g():
        return google_on

    async def f(ids):
        return {i: v for i, v in (found or {}).items() if i in ids}

    async def c():
        return credit_ok

    async def any_ok():
        return bool(approved)

    async def appr(ids):
        return {i: v for i, v in (approved or {}).items() if i in ids}

    async def enqueue(places):
        queued.extend(places)

    from app.services import open_photos
    monkeypatch.setattr(place_photos, "_google_on", g)
    monkeypatch.setattr(place_photos, "_google_photo_saved", lambda url: False)
    monkeypatch.setattr(place_photos, "_found", f)
    monkeypatch.setattr(place_photos, "_credit_shown", c)
    monkeypatch.setattr(place_photos, "_any_approved", any_ok)
    monkeypatch.setattr(place_photos, "approved_for", appr)
    monkeypatch.setattr(open_photos, "enqueue", enqueue)
    return queued


def _place(pid, urls=()):
    return {"id": pid, "name": f"Place {pid}", "latitude": 1.0, "longitude": 2.0,
            "category_name": "Attractions", "review_count": 900, "photo_urls": list(urls)}


def test_saved_google_photo_comes_first(monkeypatch):
    _setup(monkeypatch, found={"g1": {"url": WIKI, "credit": "c", "needs_credit": False}})
    monkeypatch.setattr(place_photos, "_google_photo_saved", lambda url: True)
    places = [_place("g1", [GOOGLE])]
    asyncio.run(place_photos.attach(places))
    # The saved photo, as one fixed card-sized link.
    assert places[0]["photo_urls"] == ["/api/v1/places/photo?ref=places/ABC/photos/saved&i=0&maxwidth=640"]
    assert places[0]["photo_credit"] is None


def test_wikipedia_beats_an_approved_photo(monkeypatch):
    _setup(monkeypatch,
           found={"p1": {"url": WIKI, "credit": "Photo: X / Wikimedia Commons, CC BY-SA 4.0", "needs_credit": True}},
           approved={"p1": SimpleNamespace(url=OURS, uploader_name="Anna K.")})
    places = [_place("p1", [GOOGLE])]
    asyncio.run(place_photos.attach(places))
    assert places[0]["photo_urls"] == [WIKI]
    assert places[0]["photo_credit"].startswith("Photo: X")


def test_old_builds_get_only_photos_that_need_no_credit(monkeypatch):
    _setup(monkeypatch, credit_ok=False,
           found={"p1": {"url": WIKI, "credit": "c", "needs_credit": True},
                  "p2": {"url": WIKI, "credit": "Public domain", "needs_credit": False}},
           approved={"p1": SimpleNamespace(url=OURS, uploader_name="Anna K.")})
    places = [_place("p1"), _place("p2")]
    asyncio.run(place_photos.attach(places))
    assert places[0]["photo_urls"] == [OURS]          # falls through to the approved one
    assert places[1]["photo_urls"] == [WIKI]


def test_never_looked_up_places_are_queued_once(monkeypatch):
    queued = _setup(monkeypatch, found={"seen": None})
    places = [_place("new"), _place("seen"), _place("has", [WIKI])]
    asyncio.run(place_photos.attach(places))
    assert [q["id"] for q in queued] == ["new"]
    assert queued[0]["section"] == "Attractions" and queued[0]["reviews"] == 900
    assert all(p["photo_urls"] == [] for p in places[:2])


def test_attach_fills_an_empty_place_with_its_approved_photo(monkeypatch):
    _setup(monkeypatch, found={"op_1": None},
           approved={"op_1": SimpleNamespace(url=OURS, uploader_name="Anna K.")})
    places = [_place("op_1"), _place("ChIJx", [GOOGLE])]
    asyncio.run(place_photos.attach(places))
    assert places[0]["photo_urls"] == [OURS]
    assert places[0]["photo_credit"] == "Photo: Anna K. · nexAround traveller"
    assert places[1]["photo_urls"] == [] and places[1]["photo_credit"] is None


# ── Uploads ─────────────────────────────────────────────────────────────────

def test_upload_is_shrunk_to_webp_without_exif(monkeypatch, tmp_path):
    monkeypatch.setattr(place_photos, "UPLOAD_DIR", str(tmp_path))
    url, w, h, size = place_photos.save_upload(_jpeg(4000, 3000))
    assert url.startswith(place_photos.PUBLIC_PREFIX + "/") and url.endswith(".webp")
    assert max(w, h) == place_photos.MAX_SIDE_PX
    stored = Image.open(tmp_path / os.path.basename(url))
    assert stored.format == "WEBP"
    assert not stored.getexif()
    card = tmp_path / os.path.basename(url).replace(".webp", "_640.webp")
    assert max(Image.open(card).size) == 640
    assert place_photos.sized_url(url, card=True, google_on=False).endswith("_640.webp")
    assert place_photos.sized_url(url, card=False, google_on=False) == url
    place_photos.delete_file(url)
    assert not (tmp_path / os.path.basename(url)).exists() and not card.exists()


@pytest.mark.parametrize("content", [b"not an image", _jpeg(120, 90)])
def test_bad_or_tiny_uploads_are_refused(monkeypatch, tmp_path, content):
    monkeypatch.setattr(place_photos, "UPLOAD_DIR", str(tmp_path))
    with pytest.raises(HTTPException) as e:
        place_photos.save_upload(content)
    assert e.value.status_code == 400
    assert list(tmp_path.iterdir()) == []


def test_delete_file_only_touches_our_folder(monkeypatch, tmp_path):
    monkeypatch.setattr(place_photos, "UPLOAD_DIR", str(tmp_path))
    victim = tmp_path / "keep.txt"
    victim.write_text("x")
    place_photos.delete_file("/static/uploads/experiences/keep.txt")
    place_photos.delete_file(None)
    assert victim.exists()


# ── Card-sized, fixed links ─────────────────────────────────────────────────

def test_google_links_are_fixed_and_card_sized():
    url = "/api/v1/places/photo?ref=places/PID/photos/TOKEN123&i=1"
    assert place_photos.sized_url(url, card=True, google_on=False) == \
        "/api/v1/places/photo?ref=places/PID/photos/saved&i=1&maxwidth=640"
    assert place_photos.sized_url(url, card=False, google_on=False) == \
        "/api/v1/places/photo?ref=places/PID/photos/saved&i=1"
    # Same photo under another code: the very same link, so the phone reuses it.
    other = "/api/v1/places/photo?ref=places/PID/photos/OTHER999&i=1"
    assert place_photos.sized_url(other, card=True, google_on=False) == \
        place_photos.sized_url(url, card=True, google_on=False)
    # Untouched while Google photos are on.
    assert place_photos.sized_url(url, card=True, google_on=True) == url


def test_wikipedia_and_unsplash_card_sizes():
    wiki = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/X.jpg/960px-X.jpg?utm=1"
    assert place_photos.sized_url(wiki, card=True, google_on=False) == wiki.replace("/960px-", "/500px-")
    assert place_photos.sized_url(wiki, card=False, google_on=False) == wiki
    uns = "https://images.unsplash.com/photo-1?ixid=abc&q=80&w=1080"
    small = place_photos.sized_url(uns, card=True, google_on=False)
    assert "w=640" in small and "ixid=abc" in small and "w=1080" not in small


def test_small_copy_is_made_from_the_saved_photo(monkeypatch, tmp_path):
    from app.services import photo_cache_service as pcs
    monkeypatch.setattr(pcs, "_CACHE_DIR", tmp_path)
    ref = "places/PID/photos/TOKEN"
    Image.new("RGB", (800, 600), (10, 80, 160)).save(pcs.cached_path(ref, 800, 0), format="JPEG")
    assert pcs.is_saved(ref, 640, 0) and not pcs.is_saved(ref, 640, 1)
    path = pcs.saved_or_smaller("places/PID/photos/saved", 640, 0)
    assert path is not None and max(Image.open(path).size) == 640
    assert pcs.media_type_of(path) == "image/webp"
    assert pcs.media_type_of(pcs.cached_path(ref, 800, 0)) == "image/jpeg"
    assert pcs.saved_or_smaller(ref, 640, 1) is None       # never asks Google
