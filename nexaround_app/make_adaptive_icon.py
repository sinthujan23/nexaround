"""
Creates a padded foreground image for Android adaptive icons.
The content is scaled to ~65% of the target size and centered on a teal background,
ensuring it fits within the adaptive icon safe zone (avoiding circular crop).
"""
from PIL import Image

SRC = 'assets/images/app_icon.png'
OUT = 'assets/images/app_icon_foreground.png'
TARGET = 1024        # output canvas size
SCALE  = 0.62        # logo fills 62% — stays safely inside the circle mask

teal = (0, 122, 124, 255)  # #007A7C

src = Image.open(SRC).convert('RGBA')

logo_size = int(TARGET * SCALE)
logo = src.resize((logo_size, logo_size), Image.LANCZOS)

canvas = Image.new('RGBA', (TARGET, TARGET), teal)
offset = ((TARGET - logo_size) // 2, (TARGET - logo_size) // 2)
canvas.paste(logo, offset, logo)

canvas.save(OUT)
print(f"Saved padded foreground → {OUT}  ({TARGET}x{TARGET}, logo at {SCALE*100:.0f}%)")
