"""Strip alpha (stores reject it), verify sizes, build contact sheets.  usage: finalize.py <final_dir>"""
import sys, glob, os
from PIL import Image, ImageDraw
root = sys.argv[1]
for plat, (w, h) in {"ios": (1320, 2868), "android": (1080, 1920)}.items():
    fs = sorted(glob.glob(f"{root}/{plat}/*.png"))
    for f in fs:
        im = Image.open(f)
        assert im.size == (w, h), (f, im.size)
        im.convert("RGB").save(f, optimize=True)
    th = 760; tw = round(th * w / h); gap = 18
    sheet = Image.new("RGB", (len(fs) * (tw + gap) + gap, th + gap * 2 + 70), "#222")
    d = ImageDraw.Draw(sheet); d.text((gap, 22), f"nexARound store screenshots - final C ({plat} {w}x{h})", fill="white")
    for i, f in enumerate(fs):
        sheet.paste(Image.open(f).resize((tw, th), Image.LANCZOS), (gap + i * (tw + gap), 70))
    sheet.save(f"{root}/ALL_SCREENS_{plat}.png")
    print(plat, len(fs), "files", [round(os.path.getsize(f) / 1e6, 2) for f in fs], "MB")
