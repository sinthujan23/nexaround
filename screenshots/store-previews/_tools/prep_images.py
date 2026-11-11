"""Upscale the ~500px website screenshots to 1100px wide with a light unsharp mask before render.py.
Run once on _tools/img; skip images already wider than 900px (real device screenshots)."""
import glob, os, sys
from PIL import Image, ImageFilter
d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "img")
for f in sorted(glob.glob(f"{d}/app_*.png")) + [f"{d}/meet_neva_v4.png"]:
    im = Image.open(f).convert("RGB")
    if im.width > 900: continue
    k = 1100 / im.width
    im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS).filter(
        ImageFilter.UnsharpMask(radius=1.6, percent=70, threshold=2)).save(f, optimize=True)
