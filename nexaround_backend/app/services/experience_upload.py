"""Saving gallery images, shared by the admin and partner routers.

Extracted rather than copied. The two callers are not equally trusted — the
admin endpoint is reachable only by the platform, the partner one by a
semi-trusted third party — so if the two copies drifted, the partner one would
be the soft target, and it is the one an attacker can actually reach.
"""
import io
import os
import re
import uuid
from typing import List, Optional

from fastapi import HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from PIL import Image

ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
ALLOWED_IMAGE_FORMATS = {"JPEG", "PNG", "WEBP", "GIF"}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
UPLOAD_DIR = "app/static/uploads/experiences"


async def save_experience_images(files: List[UploadFile]) -> List[str]:
    """Validate and store images, returning their `/static/...` paths.

    Three checks, and the third is the one that matters: an extension allowlist,
    a size cap, and a real Pillow decode — so a renamed executable cannot land
    in a directory that is served without authentication.
    """
    os.makedirs(UPLOAD_DIR, exist_ok=True)

    urls: List[str] = []
    for file in files:
        filename = file.filename or ""
        file_ext = os.path.splitext(filename)[1].lower()
        if file_ext not in ALLOWED_IMAGE_EXTENSIONS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"File extension '{file_ext}' is not allowed. "
                    "Only JPG, PNG, WEBP, and GIF images are permitted."
                ),
            )

        content = await file.read()
        if len(content) > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File size exceeds maximum allowed limit (10MB)",
            )

        try:
            img = Image.open(io.BytesIO(content))
            img.verify()
            if img.format not in ALLOWED_IMAGE_FORMATS:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid image format",
                )
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uploaded file is not a valid image",
            )

        # A fresh name: the uploader does not get to choose a path.
        unique_filename = f"{uuid.uuid4()}{file_ext}"
        with open(os.path.join(UPLOAD_DIR, unique_filename), "wb") as buffer:
            buffer.write(content)
        urls.append(f"/static/uploads/experiences/{unique_filename}")

    return urls


# --- Videos ------------------------------------------------------------------
#
# Stored beside the images but served by their own route
# (`GET /api/v1/experiences/videos/{name}`), not by the `/static` mount: that
# mount cannot answer byte-range requests, and iOS will not play a video from a
# server that cannot.

ALLOWED_VIDEO_EXTENSIONS = {".mp4", ".mov", ".webm"}
VIDEO_MEDIA_TYPES = {".mp4": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm"}
# Below nginx's 50 MB request cap (client_max_body_size) with room for the
# multipart framing, so a file at the limit is refused here with a readable
# message instead of by nginx with an HTML 413.
MAX_VIDEO_SIZE = 45 * 1024 * 1024
MAX_VIDEOS_PER_PACKAGE = 3
VIDEO_URL_PREFIX = "/api/v1/experiences/videos/"
VIDEO_NAME_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(mp4|mov|webm)$")
_CHUNK = 1024 * 1024


def looks_like_video(head: bytes, ext: str) -> bool:
    """Whether the first bytes are a container of the kind the extension claims.

    No decoder is installed, so this is a signature check, not a decode: MP4 and
    MOV carry `ftyp` at byte 4, WebM starts with the EBML magic. It stops a
    renamed script or archive landing in a directory served without
    authentication; it cannot prove the stream inside plays.
    """
    if ext == ".webm":
        return head[:4] == b"\x1a\x45\xdf\xa3"
    if ext in (".mp4", ".mov"):
        return len(head) >= 12 and head[4:8] == b"ftyp"
    return False


async def save_experience_video(file: UploadFile) -> str:
    """Validate and store one video, returning its API path.

    Streamed to disk in chunks and cut off at the size cap, so a large upload is
    never held in memory.
    """
    os.makedirs(UPLOAD_DIR, exist_ok=True)

    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_VIDEO_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File extension '{ext}' is not allowed. Only MP4, MOV and WebM videos are permitted.",
        )

    name = f"{uuid.uuid4()}{ext}"
    path = os.path.join(UPLOAD_DIR, name)
    size = 0
    head = b""
    try:
        with open(path, "wb") as out:
            while True:
                chunk = await file.read(_CHUNK)
                if not chunk:
                    break
                if not head:
                    head = chunk[:16]
                    if not looks_like_video(head, ext):
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Uploaded file is not a valid video",
                        )
                size += len(chunk)
                if size > MAX_VIDEO_SIZE:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Video is larger than the {MAX_VIDEO_SIZE // (1024 * 1024)} MB limit",
                    )
                out.write(chunk)
        if size == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Uploaded file is empty"
            )
    except BaseException:
        # Never leave a partial or rejected file in the served directory.
        if os.path.exists(path):
            os.remove(path)
        raise
    if ext in (".mp4", ".mov"):
        # Blocking file work, so off the event loop. Failure just means the
        # file is kept as uploaded.
        await run_in_threadpool(ensure_faststart, path)
    return f"{VIDEO_URL_PREFIX}{name}"


def video_file(name: str) -> Optional[str]:
    """The on-disk path for a stored video name, or None. The name is matched
    against a strict pattern, so it cannot name anything but our own files."""
    if not VIDEO_NAME_RE.match(name):
        return None
    path = os.path.join(UPLOAD_DIR, name)
    return path if os.path.isfile(path) else None


def parse_range(header: Optional[str], size: int) -> Optional[tuple[int, int]]:
    """`Range: bytes=...` as an inclusive (start, end), None for no/ignored
    header, ValueError when it cannot be satisfied."""
    if not header or not header.startswith("bytes=") or "," in header:
        return None
    spec = header[len("bytes="):].strip()
    first, _, last = spec.partition("-")
    try:
        if first == "":
            n = int(last)
            if n <= 0:
                raise ValueError("bad suffix")
            start, end = max(size - n, 0), size - 1
        else:
            start = int(first)
            end = int(last) if last else size - 1
    except ValueError:
        raise ValueError("bad range")
    end = min(end, size - 1)
    if start < 0 or start > end or start >= size:
        raise ValueError("unsatisfiable")
    return start, end


# --- Fast start --------------------------------------------------------------
#
# A phone camera writes an MP4's index (the `moov` atom) AFTER the video data
# (`mdat`) because it only knows the index once recording stops. A player cannot
# start until it has the index, so with the index at the end it must first
# fetch the tail of the file; on a mobile connection that is the "wait" before
# a video starts. Moving `moov` to the front lets playback begin on the first
# bytes while the rest streams in. It is a lossless rearrangement (the same job
# as ffmpeg's `-movflags +faststart`), done here without ffmpeg, which this
# image does not have. Only the chunk offsets inside `moov` change.

_CONTAINERS = {b"moov", b"trak", b"mdia", b"minf", b"stbl"}


def _top_level_atoms(f, size: int) -> Optional[list]:
    """[(type, offset, size)] for the file's top-level atoms, or None if they
    do not add up (truncated or corrupt: leave such a file alone)."""
    atoms = []
    pos = 0
    while pos < size:
        f.seek(pos)
        head = f.read(8)
        if len(head) < 8:
            return None
        length = int.from_bytes(head[:4], "big")
        kind = head[4:8]
        header_len = 8
        if length == 1:
            ext = f.read(8)
            if len(ext) < 8:
                return None
            length = int.from_bytes(ext, "big")
            header_len = 16
        elif length == 0:
            length = size - pos
        if length < header_len or pos + length > size:
            return None
        atoms.append((kind, pos, length))
        pos += length
    return atoms


def _shift_chunk_offsets(buf: bytearray, start: int, end: int, shift) -> None:
    """Rewrite every `stco` / `co64` chunk offset under buf[start:end] with
    `shift(old) -> new`."""
    pos = start
    while pos + 8 <= end:
        length = int.from_bytes(buf[pos:pos + 4], "big")
        kind = bytes(buf[pos + 4:pos + 8])
        header_len = 8
        if length == 1:
            length = int.from_bytes(buf[pos + 8:pos + 16], "big")
            header_len = 16
        if length < header_len or pos + length > end:
            raise ValueError("bad atom inside moov")
        body = pos + header_len
        if kind in _CONTAINERS:
            _shift_chunk_offsets(buf, body, pos + length, shift)
        elif kind in (b"stco", b"co64"):
            width = 4 if kind == b"stco" else 8
            count = int.from_bytes(buf[body + 4:body + 8], "big")
            first = body + 8
            if first + count * width > pos + length:
                raise ValueError("bad chunk offset table")
            for i in range(count):
                at = first + i * width
                new = shift(int.from_bytes(buf[at:at + width], "big"))
                if new < 0 or new >= 1 << (8 * width):
                    raise ValueError("chunk offset out of range")
                buf[at:at + width] = new.to_bytes(width, "big")
        pos += length


def ensure_faststart(path: str) -> bool:
    """Move the `moov` atom ahead of the video data. Returns True when the file
    was rewritten, False when it was left as it was (already fast-start, not an
    MP4/MOV layout this handles, or anything unexpected). Never raises: a video
    that cannot be rearranged still plays, just starts slower."""
    tmp = f"{path}.faststart"
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            atoms = _top_level_atoms(f, size)
            if not atoms:
                return False
            kinds = [a[0] for a in atoms]
            if b"moov" not in kinds or b"mdat" not in kinds or b"moof" in kinds:
                return False
            moov_i = kinds.index(b"moov")
            mdat_i = kinds.index(b"mdat")
            if moov_i < mdat_i:
                return False  # already starts fast
            _, moov_pos, moov_len = atoms[moov_i]
            if moov_len > 64 * 1024 * 1024:
                return False
            f.seek(moov_pos)
            moov = bytearray(f.read(moov_len))
            if b"cmov" in moov:
                return False  # compressed index: not worth the risk

            # Inserting `moov` before `mdat` pushes everything from there to
            # the old index position back by its length; what follows the
            # index does not move (it loses the index but gained the copy).
            def shift(old: int) -> int:
                for i, (_, pos, length) in enumerate(atoms):
                    if pos <= old < pos + length:
                        return old + moov_len if mdat_i <= i < moov_i else old
                return old

            _shift_chunk_offsets(moov, 8, moov_len, shift)

            with open(tmp, "wb") as out:
                for i, (_, pos, length) in enumerate(atoms):
                    if i == mdat_i:
                        out.write(moov)
                    if i == moov_i:
                        continue
                    f.seek(pos)
                    left = length
                    while left > 0:
                        chunk = f.read(min(_CHUNK, left))
                        if not chunk:
                            raise ValueError("short read")
                        out.write(chunk)
                        left -= len(chunk)
        if os.path.getsize(tmp) != size:
            raise ValueError("size changed")
        os.replace(tmp, path)
        return True
    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        return False
