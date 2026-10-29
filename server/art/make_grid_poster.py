#!/usr/bin/env python3
"""A collection poster in the style of the universe posters: its titles' posters in a 3x3 grid,
darkened towards the bottom, with the collection's name, a coloured subtitle and a small line.

Example:
  make_grid_poster.py example-saga.jpg "Example Saga" "The complete story" "3 films · 1 series" \
      ff7a1a poster1.jpg poster2.jpg ... poster9.jpg

Needs Pillow and the Lato font (Heavy and Black weights), or any font via --font / FONT."""
import argparse
import os
import sys
from PIL import Image, ImageDraw, ImageFont

FONT_HELP = ('a font file path with {} for the weight ("Heavy", "Black"), e.g. '
             '/usr/share/fonts/truetype/lato/Lato-{}.ttf, or one font file for both; or set FONT')
FONT_GUESSES = ("/usr/share/fonts/lato-fonts/Lato-{}.ttf", "/usr/share/fonts/truetype/lato/Lato-{}.ttf",
                "/usr/share/fonts/TTF/Lato-{}.ttf", "/usr/local/share/fonts/Lato-{}.ttf")


def find_font(given):
    """The font pattern to use: --font, else $FONT, else Lato where distributions put it."""
    pattern = given or os.environ.get("FONT")
    tries = [pattern] if pattern else list(FONT_GUESSES)
    for p in tries:
        if all(os.path.exists(p.format(w)) for w in ("Heavy", "Black")):
            return p
    sys.exit("font not found: tried " + ", ".join(p.format("Black") for p in tries) +
             ". Install Lato (fonts-lato, lato-fonts) or pass --font PATTERN with {} for the weight "
             "(Heavy and Black are used).")


ap = argparse.ArgumentParser(description="A collection poster: its titles' posters in a 3x3 grid, with its name.")
ap.add_argument("out", help="the poster to write (.jpg)")
ap.add_argument("title", help="the collection's name")
ap.add_argument("subtitle", help="a line in the accent colour")
ap.add_argument("line", help="a small last line")
ap.add_argument("accent", help="accent colour, hex (e.g. ff7a1a)")
ap.add_argument("posters", nargs="+", help="up to 9 posters, filled in left to right, top to bottom")
ap.add_argument("--font", help=FONT_HELP)
a = ap.parse_args()
out, title, subtitle, line, posters = a.out, a.title, a.subtitle, a.line, a.posters
accent = tuple(int(a.accent.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
W, H = 1000, 1500
FONT = find_font(a.font)

img = Image.new("RGB", (W, H), (8, 8, 12))
cw, ch = W // 3, H // 3 + 1
for n, p in enumerate(posters[:9]):
    src = Image.open(p).convert("RGB")
    s = max(cw / src.width, ch / src.height)
    src = src.resize((round(src.width * s), round(src.height * s)), Image.LANCZOS)
    left, top = (src.width - cw) // 2, (src.height - ch) // 2
    img.paste(src.crop((left, top, left + cw, top + ch)), ((n % 3) * cw, (n // 3) * ch))

# Dim the grid, then fade to near-black under the title, with a touch of the accent at the top.
shade = Image.new("RGBA", (W, H))
d = ImageDraw.Draw(shade)
for y in range(H):
    t = y / H
    dark = max(0.0, (t - 0.45) / 0.55)
    d.line([(0, y), (W, y)], fill=(6, 6, 10, round(255 * min(0.95, 0.38 + 0.9 * dark ** 0.8))))
img = Image.alpha_composite(img.convert("RGBA"), shade)
tint = Image.new("RGBA", (W, H), accent + (0,))
td = ImageDraw.Draw(tint)
for y in range(H):
    td.line([(0, y), (W, y)], fill=accent + (round(255 * 0.14 * max(0, 1 - y / (H * 0.45))),))
img = Image.alpha_composite(img, tint)
d = ImageDraw.Draw(img)


def spaced(text, y, font, fill, spacing):
    widths = [d.textlength(ch, font=font) for ch in text]
    x = (W - sum(widths) - spacing * (len(text) - 1)) / 2
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=font, fill=fill)
        x += w + spacing


size = 150
while d.textlength(title.upper(), font=ImageFont.truetype(FONT.format("Black"), size)) > 900:
    size -= 4
f = ImageFont.truetype(FONT.format("Black"), size)
d.text(((W - d.textlength(title.upper(), font=f)) / 2, 1150 - size), title.upper(), font=f, fill="white")
spaced(subtitle.upper(), 1195, ImageFont.truetype(FONT.format("Heavy"), 58), accent, 10)
spaced(line.upper(), 1300, ImageFont.truetype(FONT.format("Heavy"), 27), (215, 215, 215), 5)
img.convert("RGB").save(out, quality=92)
print("saved", out)
