"""Saving gallery images, shared by the admin and partner routers.

Extracted rather than copied. The two callers are not equally trusted — the
admin endpoint is reachable only by the platform, the partner one by a
semi-trusted third party — so if the two copies drifted, the partner one would
be the soft target, and it is the one an attacker can actually reach.
"""
import io
import os
import uuid
from typing import List

from fastapi import HTTPException, UploadFile, status
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
