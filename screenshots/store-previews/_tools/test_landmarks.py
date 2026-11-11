import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from landmarks import LANDMARKS, place
names = list(LANDMARKS)
cells = []
x = 40; y = 60; svg = []
for i, n in enumerate(names):
    col = i % 5; row = i // 5
    cx = 40 + col * 520; by = 560 + row * 560
    W, H, _ = LANDMARKS[n]()
    k = min(440 / W, 440 / H)
    svg.append(place(n, cx + (440 - W * k) / 2, by, height=H * k, color="#e8f4f4", opacity=.9, sw=3))
    svg.append(f'<text x="{cx}" y="{by+40}" fill="#9cc" font-size="28" font-family="sans-serif">{n}</text>')
html = f'<html><body style="margin:0;background:#0d2a2c"><svg width="2640" height="1760">{"".join(svg)}</svg></body></html>'
open('html_test.html', 'w').write(html)
sys.path.insert(0, 'pylib'); os.environ['PLAYWRIGHT_BROWSERS_PATH'] = 'pw-browsers'
from playwright.sync_api import sync_playwright
with sync_playwright() as pw:
    b = pw.chromium.launch(args=['--no-sandbox', '--disable-gpu']); p = b.new_page(viewport={'width': 2640, 'height': 1760})
    p.goto('file://' + os.path.abspath('html_test.html')); p.screenshot(path='landmarks_test.png'); b.close()
