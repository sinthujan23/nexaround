"""App Store "Header and Search Results" banners in the direction C style.

usage: python3 banners.py <out_dir> [--guides]
  header_3840x1646.png  (21:9, safe area ~1646x661 centred)
  search_3840x2560.png  (3:2, safe area ~2168x1030 centred)
--guides draws the safe areas in red for checking (never upload those).
"""
import math, os, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from landmarks import LANDMARKS, place as lm_place

IMG = HERE / "img"
OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
GUIDES = "--guides" in sys.argv
NAVY, INK, MINT, CORAL = "#17284d", "#0f2325", "#19d3c5", "#ff6b4a"

HEAD = """<!doctype html><html><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:%(W)dpx;height:%(H)dpx;overflow:hidden}
body{font-family:'Outfit',sans-serif;position:relative;background:%(bg)s;-webkit-font-smoothing:antialiased}
.abs{position:absolute}
.phone{position:absolute;width:1040px;aspect-ratio:1223/2600;background:#131416;border-radius:164px;padding:22px;
  box-shadow:0 80px 140px rgba(0,0,0,.45),0 20px 40px rgba(0,0,0,.25),inset 0 0 0 4px #303237}
.phone .screen{width:100%%;height:100%%;border-radius:142px;overflow:hidden;background:#000;position:relative}
.phone .screen img{width:100%%;height:100%%;object-fit:cover;object-position:top;display:block}
.phone .island{position:absolute;left:50%%;top:34px;transform:translateX(-50%%);width:246px;height:72px;background:#000;border-radius:40px}
.phone .sb{position:absolute;right:-8px;width:8px;background:#2a2c30;border-radius:0 4px 4px 0}
.phone .sbl{position:absolute;left:-8px;width:8px;background:#2a2c30;border-radius:4px 0 0 4px}
.hl{color:#fff;font-weight:900;letter-spacing:-.045em;text-transform:uppercase;line-height:.92;white-space:nowrap}
.sub{color:rgba(255,255,255,.8);font-weight:500}
</style></head>"""

def phone(img, cx, cy, width, rot):
    """phone of visual width `width` centred at (cx, cy), rotated `rot` degrees."""
    k = width / 1040
    return f"""<div class="phone" style="left:{cx-520}px;top:{cy-1105.5}px;transform:rotate({rot}deg) scale({k:.4f});transform-origin:50% 50%">
  <div class="sbl" style="top:380px;height:90px"></div><div class="sbl" style="top:520px;height:170px"></div><div class="sbl" style="top:720px;height:170px"></div>
  <div class="sb" style="top:600px;height:260px"></div>
  <div class="screen"><img src="file://{IMG}/{img}"></div><div class="island"></div></div>"""

def ratio(n):
    W, H, _ = LANDMARKS[n](); return W / H

def skyline(W, ground, tall, wide, names, opacity, x_start=-80, gap=70):
    """landmarks side by side on one ground line, scaled to fill the width."""
    sizes = [(n, tall if ratio(n) < 1.2 else wide) for n in names]
    total = sum(h * ratio(n) for n, h in sizes) + gap * (len(sizes) - 1)
    k = (W - 2 * x_start) / total
    x, out = x_start, []
    for n, h in sizes:
        h *= k; w = h * ratio(n)
        out.append(lm_place(n, x, ground, height=h, color="#fff", opacity=opacity))
        x += w + gap * k
    return "".join(out)

def guide(x, y, w, h):
    return f'<div class="abs" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;outline:6px dashed red"></div>' if GUIDES else ""

OP = .23
SKY = ["golden_gate", "eiffel", "colosseum", "big_ben", "taj_mahal", "pisa", "opera_house",
       "burj_khalifa", "pyramids", "liberty", "christ_redeemer", "petronas", "space_needle"]

def header():
    W, H = 3840, 1646
    sx, sy, sw, sh = 1097, 492, 1646, 661          # centred safe area
    body = f"""<body>
<svg class="abs" style="left:0;top:0" width="{W}" height="{H}">{skyline(W, H - 70, 600, 270, SKY, OP)}</svg>
{phone("app_home.png", 560, 900, 700, -8)}
{phone("app_scan_landmark_v4.png", 3280, 900, 700, 8)}
<div class="abs" style="left:{sx}px;top:{sy}px;width:{sw}px;height:{sh}px;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center">
  <div class="hl" style="font-size:232px">One app for<br>every trip</div>
  <div class="sub" style="font-size:60px;margin-top:40px">AR discovery · Neva AI · Trip plans · City guides</div>
</div>
{guide(sx, sy, sw, sh)}
</body></html>"""
    return W, H, HEAD % dict(W=W, H=H, bg=NAVY) + body

def search():
    W, H = 3840, 2560
    sx, sy, sw, sh = 836, 765, 2168, 1030           # centred safe area
    body = f"""<body>
<svg class="abs" style="left:0;top:0" width="{W}" height="{H}">
  {skyline(W, H - 90, 760, 330, SKY[::-1], OP)}
</svg>
{phone("app_scan_landmark_v4.png", 2990, 1330, 820, 9)}
{phone("app_home.png", 2370, 1290, 900, -4)}
<div class="abs" style="left:{sx+36}px;top:{sy}px;width:1040px;height:{sh}px;display:flex;flex-direction:column;justify-content:center">
  <div class="hl" style="font-size:184px">One app<br>for every<br>trip</div>
  <div class="sub" style="font-size:62px;line-height:1.3;margin-top:44px">AR discovery, Neva AI, trip plans and city guides in one place.</div>
</div>
{guide(sx, sy, sw, sh)}
</body></html>"""
    return W, H, HEAD % dict(W=W, H=H, bg=NAVY) + body

def main():
    sys.path.insert(0, str(HERE / "pylib"))
    os.environ["PLAYWRIGHT_BROWSERS_PATH"] = str(HERE / "pw-browsers")
    from playwright.sync_api import sync_playwright
    jobs = [("header_3840x1646", header()), ("search_3840x2560", search())]
    with sync_playwright() as pw:
        br = pw.chromium.launch(args=["--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"])
        for name, (W, H, html) in jobs:
            src = HERE / "html" / f"banner_{name}.html"; src.parent.mkdir(exist_ok=True)
            src.write_text(html, encoding="utf-8")
            page = br.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
            page.goto(src.as_uri(), wait_until="networkidle")
            page.evaluate("async () => { await document.fonts.load('900 100px Outfit'); await document.fonts.ready; }")
            page.wait_for_timeout(400)
            dst = OUT / (name + ("_GUIDES" if GUIDES else "") + ".png")
            page.screenshot(path=str(dst)); page.close()
            from PIL import Image
            Image.open(dst).convert("RGB").save(dst, optimize=True)
            print("wrote", dst)
        br.close()

if __name__ == "__main__":
    main()
