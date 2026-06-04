"""
Crops app_logo.png to keep only the phone+compass graphic,
removing the 'nexARound' text and tagline below it.
"""
from PIL import Image
import os

INPUT = os.path.join(os.path.dirname(__file__), 'assets', 'images', 'app_logo.png')
OUTPUT = os.path.join(os.path.dirname(__file__), 'assets', 'images', 'app_icon.png')  # icon-only, no text

img = Image.open(INPUT).convert('RGBA')
w, h = img.size
pixels = img.load()

print(f"Original size: {w}x{h}")

# Find the last row that contains non-transparent pixels belonging to the phone
# graphic. Walk rows from the bottom up and look for a clear gap between the
# phone artwork and the text beneath it.
row_alpha_counts = []
for y in range(h):
    count = sum(1 for x in range(w) if pixels[x, y][3] > 10)
    row_alpha_counts.append(count)

# Detect gap: find topmost row of the text block by scanning downward from
# roughly the middle of the image for a zero-row followed by non-zero rows.
mid = h // 2
gap_end = None
for y in range(mid, h):
    if row_alpha_counts[y] == 0:
        # Found an empty row — the text starts after any following non-empty rows
        # Record where the empty band begins and stop.
        gap_start = y
        gap_end = y
        break

if gap_end is None:
    # Fallback: just cut at 67% height (phone graphic is roughly in upper 2/3)
    cut_bottom = int(h * 0.67)
    print(f"No gap found, cutting at row {cut_bottom}")
else:
    cut_bottom = gap_start
    print(f"Gap found at row {gap_start} — cutting there")

# Crop to [0, 0, w, cut_bottom]
cropped = img.crop((0, 0, w, cut_bottom))

# Tight bounding box of actual content (removes transparent margins)
bbox = cropped.getbbox()
print(f"Content bounding box: {bbox}")
tight = cropped.crop(bbox)
cw, ch = tight.size
print(f"Tight crop size: {cw}x{ch}")

# Pad to a perfect square (transparent background)
side = max(cw, ch)
square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
x_off = (side - cw) // 2
y_off = (side - ch) // 2
square.paste(tight, (x_off, y_off))
print(f"Final square size: {side}x{side}")

square.save(OUTPUT, 'PNG')
print(f"Saved to {OUTPUT}")
