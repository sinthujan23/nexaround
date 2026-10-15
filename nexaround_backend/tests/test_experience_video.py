"""Package videos: what may be stored, and that the route can serve a range."""
import asyncio
import io
import uuid

import pytest
from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.testclient import TestClient

from app.services import experience_upload as up

MP4 = b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00" + b"x" * 100
WEBM = b"\x1a\x45\xdf\xa3" + b"y" * 100


@pytest.fixture
def store(tmp_path, monkeypatch):
    monkeypatch.setattr(up, "UPLOAD_DIR", str(tmp_path))
    return tmp_path


def _upload(name, data):
    return asyncio.run(up.save_experience_video(UploadFile(filename=name, file=io.BytesIO(data))))


def test_an_mp4_and_a_webm_are_accepted_and_stored_under_a_fresh_name(store):
    for name, data, ext in (("trip.MP4", MP4, ".mp4"), ("a.webm", WEBM, ".webm"), ("b.mov", MP4, ".mov")):
        url = _upload(name, data)
        assert url.startswith(up.VIDEO_URL_PREFIX) and url.endswith(ext)
        assert up.video_file(url.rsplit("/", 1)[1])


def test_a_renamed_script_or_image_is_refused_and_leaves_nothing_behind(store):
    for name, data in (("x.mp4", b"#!/bin/sh\nrm -rf /\n" + b"z" * 40), ("x.webm", MP4), ("x.mp4", WEBM)):
        with pytest.raises(HTTPException) as e:
            _upload(name, data)
        assert e.value.status_code == 400
    assert list(store.iterdir()) == []


def test_other_extensions_are_refused(store):
    for name in ("x.exe", "x.gif", "x", "x.mkv"):
        with pytest.raises(HTTPException):
            _upload(name, MP4)


def test_an_empty_file_is_refused(store):
    with pytest.raises(HTTPException):
        _upload("x.mp4", b"")


def test_a_video_over_the_cap_is_refused_and_removed(store, monkeypatch):
    monkeypatch.setattr(up, "MAX_VIDEO_SIZE", 150)
    with pytest.raises(HTTPException) as e:
        _upload("x.mp4", MP4 + b"q" * 500)
    assert "limit" in e.value.detail
    assert list(store.iterdir()) == []


def test_only_our_own_uuid_names_resolve_to_a_file(store):
    (store / "secret.txt").write_text("nope")
    for bad in ("../secret.txt", "secret.txt", "..%2fsecret.txt", "x.mp4", f"{uuid.uuid4()}.exe", ""):
        assert up.video_file(bad) is None
    assert up.video_file(f"{uuid.uuid4()}.mp4") is None  # well-formed, but not stored


@pytest.mark.parametrize("header,expected", [
    (None, None), ("", None), ("items=0-5", None), ("bytes=0-1,5-6", None),
    ("bytes=0-9", (0, 9)), ("bytes=10-", (10, 99)), ("bytes=-20", (80, 99)),
    ("bytes=90-500", (90, 99)), ("bytes=-500", (0, 99)),
])
def test_range_headers_are_read(header, expected):
    assert up.parse_range(header, 100) == expected


@pytest.mark.parametrize("header", ["bytes=100-", "bytes=50-10", "bytes=abc-", "bytes=-0", "bytes=-x"])
def test_unsatisfiable_ranges_are_rejected(header):
    with pytest.raises(ValueError):
        up.parse_range(header, 100)


def _client():
    from app.api.v1.experiences import router

    app = FastAPI()
    app.include_router(router, prefix="/api/v1")
    return TestClient(app)


def test_the_video_route_serves_whole_files_and_byte_ranges(store):
    url = _upload("v.mp4", MP4)
    client = _client()
    full = client.get(url)
    assert full.status_code == 200 and full.content == MP4
    assert full.headers["accept-ranges"] == "bytes" and full.headers["content-type"] == "video/mp4"

    part = client.get(url, headers={"Range": "bytes=4-11"})
    assert part.status_code == 206 and part.content == MP4[4:12]
    assert part.headers["content-range"] == f"bytes 4-11/{len(MP4)}"
    assert part.headers["content-length"] == "8"

    tail = client.get(url, headers={"Range": "bytes=-5"})
    assert tail.status_code == 206 and tail.content == MP4[-5:]


def test_the_video_route_refuses_bad_ranges_and_unknown_names(store):
    url = _upload("v.mp4", MP4)
    client = _client()
    bad = client.get(url, headers={"Range": f"bytes={len(MP4)}-"})
    assert bad.status_code == 416 and bad.headers["content-range"] == f"bytes */{len(MP4)}"
    assert client.get(f"/api/v1/experiences/videos/{uuid.uuid4()}.mp4").status_code == 404
    assert client.get("/api/v1/experiences/videos/..%2f..%2fetc%2fpasswd").status_code == 404


def test_a_package_takes_at_most_three_videos():
    from pydantic import ValidationError

    from app.schemas.experience import ExperiencePackageCreate

    base = {"title": "T"}
    assert ExperiencePackageCreate(**base).video_urls == []
    assert len(ExperiencePackageCreate(**base, video_urls=["a", "b", "c"]).video_urls) == 3
    with pytest.raises(ValidationError):
        ExperiencePackageCreate(**base, video_urls=["a", "b", "c", "d"])


def test_the_package_detail_carries_video_urls_and_the_card_does_not():
    from app.schemas.experience import ExperiencePackageCard, ExperiencePackageDetail

    assert "video_urls" in ExperiencePackageDetail.model_fields
    assert "video_urls" not in ExperiencePackageCard.model_fields


def test_a_setting_is_read_fresh_from_the_database_not_from_one_process_cache():
    from app.services.settings_service import SettingsService

    class Row:
        value = "false"

    class Result:
        def __init__(self, row): self.row = row
        def scalar_one_or_none(self): return self.row

    class Db:
        def __init__(self, row): self.row = row
        async def execute(self, _q): return Result(self.row)

    SettingsService._cache["experiences_country_mode"] = "true"   # stale, as in the other worker
    got = asyncio.run(SettingsService(Db(Row())).get_setting_fresh("experiences_country_mode", ""))
    assert got == "false"
    assert SettingsService._cache["experiences_country_mode"] == "false"
    # A deleted row falls back to the default and drops the stale cache entry.
    assert asyncio.run(SettingsService(Db(None)).get_setting_fresh("experiences_country_mode", "x")) == "x"
    assert "experiences_country_mode" not in SettingsService._cache


# --- Fast start: the index must come before the video data -------------------

def _box(kind: bytes, body: bytes) -> bytes:
    return (8 + len(body)).to_bytes(4, "big") + kind + body


def _mp4(index_first: bool, wide_offsets: bool = False):
    """A tiny MP4: ftyp, mdat of 3 marked chunks, and an index whose chunk
    offsets point at those markers. Returns (bytes, expected marker bytes)."""
    ftyp = _box(b"ftyp", b"mp42" + b"\x00" * 4 + b"mp42isom")
    chunks = [b"AAAA" * 8, b"BBBB" * 8, b"CCCC" * 8]
    mdat = _box(b"mdat", b"".join(chunks))
    width = 8 if wide_offsets else 4

    def moov_for(mdat_pos: int) -> bytes:
        offsets, at = [], mdat_pos + 8
        for c in chunks:
            offsets.append(at)
            at += len(c)
        table = b"".join(o.to_bytes(width, "big") for o in offsets)
        stco = _box(b"co64" if wide_offsets else b"stco",
                    b"\x00\x00\x00\x00" + len(offsets).to_bytes(4, "big") + table)
        return _box(b"moov", _box(b"trak", _box(b"mdia", _box(b"minf", _box(b"stbl", stco)))))

    if index_first:
        moov_len = len(moov_for(0))
        return ftyp + moov_for(len(ftyp) + moov_len) + mdat, chunks
    return ftyp + mdat + moov_for(len(ftyp)), chunks


def _chunk_offsets(data: bytes) -> list:
    i = data.index(b"stco") if b"stco" in data else data.index(b"co64")
    width = 4 if b"stco" in data else 8
    count = int.from_bytes(data[i + 8:i + 12], "big")
    return [int.from_bytes(data[i + 12 + k * width:i + 12 + (k + 1) * width], "big") for k in range(count)]


def _order(path) -> list:
    with open(path, "rb") as f:
        return [k.decode() for k, _, _ in up._top_level_atoms(f, path.stat().st_size)]


@pytest.mark.parametrize("wide", [False, True])
def test_an_index_at_the_end_is_moved_to_the_front_and_every_chunk_still_resolves(tmp_path, wide):
    slow, chunks = _mp4(index_first=False, wide_offsets=wide)
    path = tmp_path / "v.mp4"
    path.write_bytes(slow)
    assert _order(path) == ["ftyp", "mdat", "moov"]

    assert up.ensure_faststart(str(path)) is True

    assert _order(path) == ["ftyp", "moov", "mdat"]
    data = path.read_bytes()
    assert len(data) == len(slow)
    for offset, chunk in zip(_chunk_offsets(data), chunks):
        assert data[offset:offset + len(chunk)] == chunk
    # And it is exactly the file a fast-start encoder would have written.
    assert data == _mp4(index_first=True, wide_offsets=wide)[0]
    assert not list(tmp_path.glob("*.faststart"))


def test_a_file_that_already_starts_fast_or_is_not_an_mp4_is_left_alone(tmp_path):
    fast = tmp_path / "fast.mp4"
    fast.write_bytes(_mp4(index_first=True)[0])
    junk = tmp_path / "junk.mp4"
    junk.write_bytes(MP4)
    truncated = tmp_path / "cut.mp4"
    truncated.write_bytes(_mp4(index_first=False)[0][:-6])
    for p in (fast, junk, truncated):
        before = p.read_bytes()
        assert up.ensure_faststart(str(p)) is False
        assert p.read_bytes() == before
    assert not list(tmp_path.glob("*.faststart"))


def test_an_uploaded_video_with_the_index_at_the_end_is_stored_fast_start(store):
    slow, chunks = _mp4(index_first=False)
    url = _upload("phone.mp4", slow)
    stored = store / url.rsplit("/", 1)[1]
    assert _order(stored) == ["ftyp", "moov", "mdat"]
    data = stored.read_bytes()
    for offset, chunk in zip(_chunk_offsets(data), chunks):
        assert data[offset:offset + len(chunk)] == chunk
