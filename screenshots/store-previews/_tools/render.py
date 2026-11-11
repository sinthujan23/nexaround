"""Render store preview screens (3 directions x 8 screens) with headless Chromium.

usage: python3 render.py <A|B|C> <out_dir> [W H]   (default canvas 1320x2868 = iPhone 6.9")
"""
import math, os, sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from landmarks import LANDMARKS, place as lm_place

HERE = Path(__file__).resolve().parent
IMG = HERE / "img"
HTML = HERE / "html"
HTML.mkdir(exist_ok=True)

DIRECTION = sys.argv[1]
OUT = Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
W = int(sys.argv[3]) if len(sys.argv) > 3 else 1320
H = int(sys.argv[4]) if len(sys.argv) > 4 else 2868
# design space is always 1320 wide; canvas height in design px
DW = 1320
SCALE = W / DW
DH = round(H / SCALE)

TEAL = "#007b7d"
MINT = "#19d3c5"
AMBER = "#ffb547"
CORAL = "#ff6b4a"
INK = "#0f2325"

ICONS = {
    "pin": '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
    "mic": '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" x2="12" y1="19" y2="22"/>',
    "check": '<path d="M20 6 9 17l-5-5"/>',
    "star": '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
    "smile": '<circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" x2="9.01" y1="9" y2="9"/><line x1="15" x2="15.01" y1="9" y2="9"/>',
    "flag": '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" x2="4" y1="22" y2="15"/>',
    "heart": '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
    "spark": '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/>',
    "cal": '<rect width="18" height="18" x="3" y="4" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    "compass": '<circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"/>',
    "msg": '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    "food": '<path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2"/><path d="M7 2v20"/><path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"/>',
    "boat": '<path d="M2 21c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1 .6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M19.38 20A11.6 11.6 0 0 0 21 14l-9-4-9 4c0 2.9.94 5.34 2.81 7.76"/><path d="M19 13V7a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v6"/><path d="M12 10v4"/><path d="M12 2v3"/>',
    "train": '<rect width="16" height="16" x="4" y="3" rx="2"/><path d="M4 11h16"/><path d="M12 3v8"/><path d="m8 19-2 3"/><path d="m18 22-2-3"/><path d="M8 15h.01"/><path d="M16 15h.01"/>',
    "zap": '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
    "layers": '<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    "camera": '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/>',
    "route": '<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>',
    "wallet": '<path d="M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1"/><path d="M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4"/>',
}

def icon(name, size=34, color="currentColor", sw=2.2):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{ICONS[name]}</svg>')

SCREENS = [
    dict(key="home", hc=['One app for', 'every trip'], n="01", tag="All-in-one travel app", icon="layers",
         h=["One app for", "every trip"],
         sub="AR discovery, Neva AI, trip plans, city guides and local tours in one place.",
         img="app_home.png",
         chips=[("pin", "Exploring Paris"), ("compass", "Craft your journey")],
         note="your trip, one app", color="#17284d", light=False, pill_top=1440),
    dict(key="ar", hc=['See what’s', 'around you'], n="02", tag="AR Discovery", icon="camera",
         h=["See what’s", "around you"],
         sub="Hold up your phone. Nearby food, hotels and sights appear over the camera view.",
         img="app_scan_landmark_v4.png",
         chips=[("pin", "Café Mocha · ★ 4.6 · 85 m"), ("layers", "Food · Hotels · Nature · Medical")],
         note="point → discover → go", color=TEAL, light=False),
    dict(key="neva", hc=['Ask Neva.', 'Or just talk.'], n="03", tag="Neva AI companion", icon="msg",
         h=["Ask Neva.", "Or just talk."],
         sub="Answers based on where you are. Tap Listen and hear any reply read aloud.",
         img="meet_neva_v4.png",
         chips=[("mic", "Listening…"), ("msg", "“Quiet beach near me?”")],
         note="she knows the way", color="#0f1d1f", light=False),
    dict(key="odyssey", hc=['Your trip,', 'day by day'], n="04", tag="Odyssey AI planner", icon="compass",
         h=["Your whole trip,", "planned day by day"],
         sub="Flights, stays, budget, visa guidance and what to book first.",
         img="app_odyssey_plans_v4.png",
         chips=[("cal", "6 days · 2 travellers"), ("wallet", "Budget breakdown")],
         note="6 days, sorted", color=CORAL, light=False),
    dict(key="guides", hc=['City guides', 'that navigate'], n="05", tag="City Guides", icon="route",
         h=["Follow a city guide", "with live navigation"],
         sub="Creator-written, reviewed by nexARound. Tick off sights as you go.",
         img="app_city_guides.png",
         chips=[("flag", "Day 1 done"), ("train", "Metro to the Louvre")],
         note="Paris, day 1", color="#f4d58d", light=True),
    dict(key="today", hc=['Pick a mood.', 'Get a plan.'], n="06", tag="Where should I go today?", icon="smile",
         h=["Pick a mood.", "Get today’s plan."],
         sub="Food Quest, Photo Hunt or Surprise Me, built from stops near you.",
         img="app_where_should_i_go.png",
         chips=[("smile", "Happy"), ("spark", "Curious"), ("food", "Food Quest")],
         note="feeling curious", color="#cfe9ea", light=True),
    dict(key="experiences", hc=['Tours run', 'by locals'], n="07", tag="Local experiences", icon="boat",
         h=["Safaris, boat rides", "and local tours"],
         sub="Request your date. The provider confirms, and you pay on the day.",
         img="app_experiences.png",
         chips=[("check", "Date confirmed"), ("boat", "Boat · Water · Wildlife")],
         note="booked with a local", color="#0b5a55", light=False),
    dict(key="walk", hc=['Check in.', 'Earn XP.'], n="08", tag="Walking Challenge", icon="flag",
         h=["Walk. Check in.", "Earn XP."],
         sub="Nearby sights become stops on a map. Raise your Explorer Level.",
         img="app_walking_challenge.png",
         chips=[("zap", "XP earned"), ("check", "Checked in · Mangrove Island")],
         note="1.7 km to the next stop", color=AMBER, light=True),
    dict(key="community", hc=['Stories from', 'travellers'], n="09", tag="Stories & forum", icon="heart",
         h=["Real stories from", "travellers near you"],
         sub="Post, like, comment and ask the travel community anything.",
         img="app_travel_stories_v4.png",
         chips=[("heart", "Stories near you first"), ("msg", "Ask the community")],
         note="from travellers like you", color="#e9e3d6", light=True),
]

HEAD = f"""<!doctype html><html><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800;900&family=Caveat:wght@500;700&display=swap" rel="stylesheet">
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:{DW}px;height:{DH}px;overflow:hidden}}
body{{font-family:'Outfit',sans-serif;position:relative;-webkit-font-smoothing:antialiased}}
.abs{{position:absolute}}
.phone{{position:absolute;width:1040px;aspect-ratio:1223/2600;background:#131416;border-radius:164px;padding:22px;
  box-shadow:0 80px 140px rgba(0,0,0,.45),0 20px 40px rgba(0,0,0,.25),inset 0 0 0 4px #303237}}
.phone .screen{{width:100%;height:100%;border-radius:142px;overflow:hidden;background:#000;position:relative}}
.phone .screen img{{width:100%;height:100%;object-fit:cover;object-position:top;display:block}}
.phone .island{{position:absolute;left:50%;top:34px;transform:translateX(-50%);width:246px;height:72px;background:#000;border-radius:40px}}
.phone .sb{{position:absolute;right:-8px;width:8px;background:#2a2c30;border-radius:0 4px 4px 0}}
.phone .sbl{{position:absolute;left:-8px;width:8px;background:#2a2c30;border-radius:4px 0 0 4px}}
.chip{{position:absolute;display:flex;align-items:center;gap:18px;white-space:nowrap;font-weight:600;font-size:34px;line-height:1;padding:24px 38px 24px 30px;border-radius:999px}}
.wm{{position:absolute;display:flex;align-items:center;gap:16px;font-weight:700;font-size:36px;letter-spacing:-.01em}}
.wm b{{color:{MINT};font-weight:800}}
.wm img{{width:64px;height:64px;object-fit:contain}}
</style>"""

def phone(img, left, top, extra_style="", screen_overlay=""):
    return f"""<div class="phone" style="left:{left}px;top:{top}px;{extra_style}">
  <div class="sbl" style="top:380px;height:90px"></div><div class="sbl" style="top:520px;height:170px"></div><div class="sbl" style="top:720px;height:170px"></div>
  <div class="sb" style="top:600px;height:260px"></div>
  <div class="screen"><img src="file://{IMG}/{img}">{screen_overlay}</div><div class="island"></div></div>"""

def wordmark(left, top, color="#fff", logo="logo_white.png"):
    return f'<div class="wm" style="left:{left}px;top:{top}px;color:{color}"><img src="file://{IMG}/{logo}"><span>nex<b>AR</b>ound</span></div>'

# ---------------------------------------------------------------- direction A
def route_svg(i, n_screens=8):
    """one continuous glowing path across all screens, offset per screen"""
    total = DW * n_screens
    pts = []
    x = -200
    while x <= total + 200:
        y = 2150 + 240 * math.sin(x / 760) + 110 * math.sin(x / 330 + 1.3)
        pts.append((x, y)); x += 24
    d = "M" + " L".join(f"{px:.0f},{py:.0f}" for px, py in pts)
    # waypoint dots in the left margin of each screen
    dots = ""
    for k in range(n_screens):
        for fx in (70, 1250):
            yy = 2150 + 240 * math.sin((k * DW + fx) / 760) + 110 * math.sin((k * DW + fx) / 330 + 1.3)
            dots += f'<circle cx="{k*DW+fx}" cy="{yy:.0f}" r="11" fill="{MINT}"/><circle cx="{k*DW+fx}" cy="{yy:.0f}" r="26" fill="none" stroke="{MINT}" stroke-opacity=".4" stroke-width="3"/>'
    return f"""<svg class="abs" style="left:{-i*DW}px;top:0" width="{total}" height="{DH}" viewBox="0 0 {total} {DH}">
<defs><filter id="g" x="-5%" y="-50%" width="110%" height="200%"><feGaussianBlur stdDeviation="22"/></filter></defs>
<path d="{d}" fill="none" stroke="{MINT}" stroke-opacity=".55" stroke-width="34" filter="url(#g)"/>
<path d="{d}" fill="none" stroke="{MINT}" stroke-width="7" stroke-linecap="round" stroke-dasharray="30 26"/>
{dots}</svg>"""

def contours():
    out = []
    for cx, cy, rings, phase in ((1060, 520, 9, 0.4), (180, 2500, 7, 2.1)):
        for r in range(220, 220 + rings * 95, 95):
            pts = []
            for t in range(0, 361, 6):
                a = math.radians(t)
                rr = r * (1 + .13 * math.sin(3 * a + phase) + .08 * math.sin(5 * a - phase * 2) + .05 * math.sin(7 * a))
                pts.append((cx + rr * math.cos(a), cy + rr * .78 * math.sin(a)))
            out.append('<path d="M' + " L".join(f"{x:.0f},{y:.0f}" for x, y in pts) + f'Z" fill="none" stroke="{MINT}" stroke-opacity=".13" stroke-width="2"/>')
    return f'<svg class="abs" style="left:0;top:0" width="{DW}" height="{DH}">' + "".join(out) + "</svg>"

def render_A(i, s):
    tilt = -10 if i % 2 == 0 else 10
    rz = -3 if i % 2 == 0 else 3
    chips = ""
    places = [(-10, round(DH * .54), -7), (None, round(DH * .70), 5), (40, round(DH * .84), -4)]
    for k, (ic, txt) in enumerate(s["chips"]):
        left, top, rot = places[k]
        pos = f"left:{left}px" if left is not None else "right:30px"
        chips += (f'<div class="chip" style="{pos};top:{top}px;transform:rotate({rot}deg);color:#fff;'
                  f'background:rgba(6,24,27,.62);backdrop-filter:blur(26px);-webkit-backdrop-filter:blur(26px);'
                  f'border:1.5px solid rgba(255,255,255,.35);box-shadow:0 30px 60px rgba(0,0,0,.45)">'
                  f'<span style="display:flex;width:56px;height:56px;border-radius:50%;background:{MINT};color:#063;align-items:center;justify-content:center;color:#052a2a">{icon(ic,30,"#052a2a",2.6)}</span>{txt}</div>')
    body = f"""<body style="background:#06181b;background-image:radial-gradient(900px 760px at 18% 12%,rgba(0,123,125,.62),transparent 62%),radial-gradient(760px 700px at 88% 78%,rgba(255,181,71,.16),transparent 60%),radial-gradient(600px 600px at 60% 100%,rgba(25,211,197,.18),transparent 60%)">
{contours()}
{route_svg(i)}
{wordmark(100, 128)}
<div class="abs" style="right:100px;top:132px;font-size:28px;letter-spacing:.22em;font-weight:600;color:{MINT};text-transform:uppercase;padding:16px 28px;border:2px solid rgba(25,211,197,.5);border-radius:999px">{s['n']} · {s['tag']}</div>
<div class="abs" style="left:100px;top:300px;width:1140px;color:#fff;font-size:124px;line-height:1.0;font-weight:800;letter-spacing:-.03em">
  {s['h'][0]}<br><span style="background:linear-gradient(90deg,{MINT},#b5f3e5);-webkit-background-clip:text;background-clip:text;color:transparent">{s['h'][1]}</span></div>
<div class="abs" style="left:100px;top:{300+124*2+40}px;width:1080px;color:rgba(255,255,255,.78);font-size:44px;line-height:1.3;font-weight:400">{s['sub']}</div>
<div class="abs" style="left:140px;top:960px;width:1040px;height:1500px;border-radius:50%;background:radial-gradient(closest-side,rgba(25,211,197,.35),transparent)"></div>
{phone(s['img'], 140, 930, f"transform:perspective(3200px) rotateY({tilt}deg) rotateZ({rz}deg);transform-origin:50% 40%")}
{chips}
</body></html>"""
    return HEAD + body

# ---------------------------------------------------------------- direction B
def stamp_svg(text_top, text_ring, color, size=320):
    return f"""<svg width="{size}" height="{size}" viewBox="0 0 320 320">
<defs><path id="ring" d="M160,160 m-118,0 a118,118 0 1,1 236,0 a118,118 0 1,1 -236,0"/></defs>
<circle cx="160" cy="160" r="150" fill="none" stroke="{color}" stroke-width="7"/>
<circle cx="160" cy="160" r="138" fill="none" stroke="{color}" stroke-width="2.5"/>
<circle cx="160" cy="160" r="92" fill="none" stroke="{color}" stroke-width="2.5"/>
<text font-family="Outfit" font-weight="700" font-size="25" letter-spacing="4" fill="{color}"><textPath href="#ring">{text_ring}</textPath></text>
<text x="160" y="150" text-anchor="middle" font-family="Outfit" font-weight="800" font-size="30" fill="{color}" letter-spacing="2">{text_top}</text>
<text x="160" y="190" text-anchor="middle" font-family="Outfit" font-weight="600" font-size="22" fill="{color}" letter-spacing="3">nexARound</text>
</svg>"""

def render_B(i, s):
    rot = (-3, 2.5, -2, 3, -2.5, 2, -3, 2.5)[i]
    ink_color = TEAL if i % 2 == 0 else CORAL
    first, rest = s["h"][0], s["h"][1]
    # highlight the last line with a marker stroke
    body = f"""<body style="background:#f4efe5">
<svg class="abs" style="left:0;top:0;opacity:.5;mix-blend-mode:multiply" width="{DW}" height="{DH}"><filter id="n"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 .55 0 0 0 0 .5 0 0 0 0 .42 0 0 0 .28 0"/></filter><rect width="100%" height="100%" filter="url(#n)"/></svg>
<div class="abs" style="left:0;top:0;width:{DW}px;height:26px;background:repeating-linear-gradient(-45deg,{TEAL} 0 60px,#f4efe5 60px 120px,{CORAL} 120px 180px,#f4efe5 180px 240px)"></div>
{wordmark(100, 118, INK, "logo_color.png")}
<div class="abs" style="right:100px;top:122px;font-size:26px;letter-spacing:.24em;font-weight:700;color:{ink_color};text-transform:uppercase;padding:14px 26px;border:2.5px dashed {ink_color};border-radius:8px">{s['n']} / {s['tag']}</div>
<div class="abs" style="left:100px;top:290px;width:1140px;color:{INK};font-size:120px;line-height:1.02;font-weight:800;letter-spacing:-.03em">
  {first}<br><span style="background:linear-gradient(transparent 58%,#bdeee7 58%,#bdeee7 94%,transparent 94%)">{rest}</span></div>
<div class="abs" style="left:100px;top:{290+120*2+44}px;width:1060px;color:#3f5658;font-size:42px;line-height:1.32;font-weight:400">{s['sub']}</div>
<div class="abs" style="left:120px;top:{290+120*2+150}px;font-family:Caveat;font-weight:700;font-size:66px;color:{ink_color};transform:rotate(-4deg);white-space:nowrap">{s['note']} <span style="font-family:Outfit;font-weight:400;font-size:52px">↘</span></div>
<!-- polaroid -->
<div class="abs" style="left:100px;top:900px;width:1120px;padding:36px 36px 176px;background:#fff;box-shadow:0 50px 90px rgba(30,40,40,.28),0 8px 18px rgba(0,0,0,.08);transform:rotate({rot}deg);transform-origin:50% 30%">
  <div style="width:100%;height:{min(1620, DH - 900 - 36 - 176 - 70)}px;overflow:hidden;border-radius:6px;background:#111"><img src="file://{IMG}/{s['img']}" style="width:100%;height:100%;object-fit:cover;object-position:top;display:block"></div>
  <div style="position:absolute;left:44px;bottom:48px;font-family:Caveat;font-weight:700;font-size:70px;color:#1d3436;line-height:1">{s['tag']}</div>
  <div style="position:absolute;right:44px;bottom:66px;font-size:26px;letter-spacing:.18em;color:#8a9a9b;font-weight:600">nexARound · {s['n']}/08</div>
  <div style="position:absolute;left:-70px;top:-26px;width:360px;height:78px;transform:rotate(-7deg);opacity:.9;background:repeating-linear-gradient(45deg,rgba(0,123,125,.62) 0 16px,rgba(0,123,125,.42) 16px 32px);box-shadow:0 4px 10px rgba(0,0,0,.08)"></div>
  <div style="position:absolute;right:-120px;top:-150px;transform:rotate(-16deg);opacity:.88;mix-blend-mode:multiply">{stamp_svg(s['n'], 'DISCOVER WHAT’S NEXT AROUND YOU · ' + s['tag'].upper() + ' · ', ink_color)}</div>
</div>
</body></html>"""
    return HEAD + body

# ---------------------------------------------------------------- direction C
# landmark sketch sets for direction C: (hero in the free column, lower in the free column, top-right wide)
C_SKETCH = [
    ("eiffel", "christ_redeemer", "pyramids"),
    ("burj_khalifa", "petronas", "golden_gate"),
    ("liberty", "space_needle", "taj_mahal"),
    ("pisa", "big_ben", "colosseum"),
    ("eiffel", "liberty", "opera_house"),
    ("big_ben", "burj_khalifa", "pyramids"),
    ("petronas", "pisa", "colosseum"),
    ("space_needle", "eiffel", "golden_gate"),
    ("liberty", "big_ben", "taj_mahal"),
]

def c_geom(i):
    """Phone placement for direction C, after the Vaanga reference: centred under the text,
    ~73% of the frame width, small alternating tilt, fully inside on iPhone size."""
    T = 690
    Wv = 960 if DH > 2600 else 880          # Android 9:16 is shorter: slightly smaller phone, bottom cropped
    Hv = Wv * 2600 / 1223
    cx = DW / 2
    th = -3 if i % 2 == 0 else 3
    return dict(T=T, Wv=Wv, Hv=Hv, cx=cx, th=th)

def c_edge_x(g, side, y):
    """x of the phone's left (side=-1) or right (side=+1) edge at canvas height y."""
    a = math.radians(g["th"]); c, s_ = math.cos(a), math.sin(a)
    dx = side * g["Wv"] / 2
    pts = [(g["cx"] + dx * c - dy * s_, g["T"] + dx * s_ + dy * c) for dy in (0, g["Hv"])]
    (x1, y1), (x2, y2) = pts
    t = (y - y1) / (y2 - y1)
    return x1 + (x2 - x1) * t

def sketch_layer(i, light, bg, g):
    hero, lower, top = C_SKETCH[i]
    side_a = 1 if i % 2 == 0 else -1          # side of the first sticker
    color = "#0f2325" if light else "#ffffff"
    op = {"#007b7d": .22, "#0f1d1f": .17, "#ff6b4a": .30, "#0b5a55": .20, "#f4d58d": .17, "#cfe9ea": .17, "#ffb547": .20, "#e9e3d6": .15, "#17284d": .20}.get(bg, .18) * 1.15
    tuck = 60                                  # landmarks may slide this far behind the phone
    def strip(side, y):
        e = c_edge_x(g, side, y)
        return (e + 10 - tuck, DW - 22) if side > 0 else (22, e - 10 + tuck)
    def ratio(n):
        W, H, _ = LANDMARKS[n](); return W / H
    def put(name, side, y0, y1, max_w=None):
        x0, x1 = strip(side, y1)
        w_av = x1 - x0 if max_w is None else min(max_w, x1 - x0)
        h = min(y1 - y0, w_av / ratio(name)); w = h * ratio(name)
        x = x1 - w if side > 0 else x0
        return lm_place(name, x, y1, height=h, color=color, opacity=op)
    out = [
        put(hero, side_a, 740, round(DH * .585)),                       # above the first sticker
        put(lower, -side_a, 1340, round(DH * .80) - 30),                 # between the tag pill and the second sticker
    ]
    h = min(170, 460 / ratio(top)); w = h * ratio(top)                  # right of the wordmark, above the subtitle
    out.append(lm_place(top, DW - 56 - w, 196, height=h, color=color, opacity=op * .95))
    return f'<svg class="abs" style="left:0;top:0" width="{DW}" height="{DH}" viewBox="0 0 {DW} {DH}">{"".join(out)}</svg>'

def render_C(i, s):
    bg = s["color"]; light = s["light"]
    fg = INK if light else "#fff"
    sub_c = "rgba(15,35,37,.72)" if light else "rgba(255,255,255,.8)"
    even = i % 2 == 0
    g = c_geom(i)
    k = g["Wv"] / 1040
    accent = CORAL if bg in (TEAL, "#0b5a55", "#0f1d1f", "#cfe9ea", "#17284d") else TEAL
    if bg == CORAL: accent = "#ffe08a"
    if bg == AMBER: accent = INK
    stickers = ""
    places = [("right:40px" if even else "left:40px", round(DH * .60), 6),
              ("left:40px" if even else "right:40px", min(round(DH * .80), DH - 240), -5)]
    for n, (ic, txt) in enumerate(s["chips"][:2]):
        pos, top, r = places[n]
        stickers += (f'<div class="chip" style="{pos};top:{top}px;transform:rotate({r}deg);background:#fff;color:{INK};'
                     f'border:5px solid {INK};box-shadow:12px 12px 0 {INK};font-weight:700;font-size:36px">'
                     f'{icon(ic,36,INK,2.6)}{txt}</div>')
    pill_fg = '#fff' if accent in (CORAL, TEAL, INK) else INK
    body = f"""<body style="background:{bg}">
{sketch_layer(i, light, bg, g)}
{wordmark(100, 104, fg, "logo_white.png" if not light else "logo_color.png")}
<div class="abs" style="left:100px;top:212px;width:1100px;color:{sub_c};font-size:42px;line-height:1.3;font-weight:500">{s['sub']}</div>
<div class="abs" style="left:96px;top:352px;width:1240px;color:{fg};font-size:160px;line-height:.92;font-weight:900;letter-spacing:-.045em;text-transform:uppercase;white-space:nowrap">{s['hc'][0]}<br>{s['hc'][1]}</div>
{phone(s['img'], g['cx'] - 520, g['T'], f"transform-origin:50% 0;transform:rotate({g['th']}deg) scale({k:.4f})")}
<div class="abs" style="{'left:40px' if even else 'right:40px'};top:{s.get('pill_top', 1180)}px;transform:rotate({-12 if even else 12}deg);display:flex;align-items:center;gap:22px;background:{accent};color:{pill_fg};padding:28px 44px;border-radius:999px;font-size:38px;font-weight:800;letter-spacing:.04em;text-transform:uppercase;border:8px solid #fff;box-shadow:0 30px 60px rgba(0,0,0,.3)">{icon(s['icon'],44,pill_fg,2.6)}{s['tag']}</div>
{stickers}
</body></html>"""
    return HEAD + body

RENDER = {"A": render_A, "B": render_B, "C": render_C}

def main():
    sys.path.insert(0, str(HERE / "pylib"))
    os.environ["PLAYWRIGHT_BROWSERS_PATH"] = str(HERE / "pw-browsers")
    from playwright.sync_api import sync_playwright
    files = []
    for i, s in enumerate(SCREENS):
        html = RENDER[DIRECTION](i, s)
        p = HTML / f"{DIRECTION}_{s['n']}_{s['key']}.html"
        p.write_text(html, encoding="utf-8")
        files.append((p, OUT / f"{s['n']}_{s['key']}.png"))
    with sync_playwright() as pw:
        br = pw.chromium.launch(args=["--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"])
        ctx = br.new_context(viewport={"width": DW, "height": DH}, device_scale_factor=SCALE)
        page = ctx.new_page()
        for src, dst in files:
            page.goto(src.as_uri(), wait_until="networkidle")
            page.evaluate("async () => { await document.fonts.load('800 100px Outfit'); await document.fonts.load('700 60px Caveat'); await document.fonts.ready; }")
            page.wait_for_timeout(400)
            page.screenshot(path=str(dst), full_page=False)
            print("wrote", dst)
        br.close()

if __name__ == "__main__":
    main()
