#!/usr/bin/env python3
"""A poster for a cut of a show (its own stop on a universe's path), in the style of the universe
posters: an episode still filling the frame, fading to black, the cut's name over the bottom.

Example:
  make_cut_poster.py still.jpg example-saga-the-lost-map.jpg "Example Saga: The Series" \
      "The Lost Map" "Season 2 · Episodes 1-2" "A side story" 0.4 ff7a1a

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


ap = argparse.ArgumentParser(description="A poster for a cut of a show, in the style of the universe posters.")
ap.add_argument("still", help="a landscape episode still")
ap.add_argument("out", help="the poster to write (.jpg)")
ap.add_argument("show", help="the show's name, small at the top")
ap.add_argument("title", help="the cut's name, large at the bottom")
ap.add_argument("episodes", help="the line under it, e.g. \"Season 2 · Episodes 1-2\"")
ap.add_argument("note", help="a small last line")
ap.add_argument("focus", nargs="?", type=float, default=0.5, help="where to crop the still, 0 (left) to 1 (right)")
ap.add_argument("accent", nargs="?", default="ff7a1a", help="accent colour, hex (default ff7a1a)")
ap.add_argument("--font", help=FONT_HELP)
a = ap.parse_args()
still, out, show, title, episodes, note, focus = a.still, a.out, a.show, a.title, a.episodes, a.note, a.focus
accent = tuple(int(a.accent.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
W, H = 1000, 1500
FONT = find_font(a.font)

src = Image.open(still).convert("RGB")
# Portrait crop of the landscape still around [focus], filling the full height.
s = H / src.height
src = src.resize((round(src.width * s), H), Image.LANCZOS)
left = min(max(0, round(src.width * focus - W / 2)), src.width - W)
img = src.crop((left, 0, left + W, H)).convert("RGBA")

# A touch of the accent at the top, then a fade to near-black under the title.
shade = Image.new("RGBA", (W, H))
d = ImageDraw.Draw(shade)
for y in range(H):
    t = y / H
    dark = max(0.0, (t - 0.38) / 0.62)
    d.line([(0, y), (W, y)], fill=(4, 4, 8, round(255 * min(0.94, 0.08 + 0.95 * dark ** 0.9))))
img = Image.alpha_composite(img, shade)
tint = Image.new("RGBA", (W, H), accent + (0,))
td = ImageDraw.Draw(tint)
for y in range(H):
    td.line([(0, y), (W, y)], fill=accent + (round(255 * 0.16 * max(0, 1 - y / (H * 0.5))),))
img = Image.alpha_composite(img, tint)

d = ImageDraw.Draw(img)


def spaced(text, y, font, fill, spacing):
    widths = [d.textlength(ch, font=font) for ch in text]
    x = (W - sum(widths) - spacing * (len(text) - 1)) / 2
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=font, fill=fill)
        x += w + spacing


# The show's name at the top, like a series banner.
spaced(show.upper(), 64, ImageFont.truetype(FONT.format("Heavy"), 30), (240, 240, 240), 7)
d.line([(W / 2 - 50, 112), (W / 2 + 50, 112)], fill=accent, width=4)

# The title: as large as fits, on up to two lines.
words, size = title.upper().split(), 170
while True:
    f = ImageFont.truetype(FONT.format("Black"), size)
    lines, line = [], ""
    for w in words:
        trial = (line + " " + w).strip()
        if d.textlength(trial, font=f) <= 900 or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    lines.append(line)
    if len(lines) <= 2 and max(d.textlength(l, font=f) for l in lines) <= 900:
        break
    size -= 6
lh = round(size * 1.02)
y = 1235 - lh * len(lines)
for l in lines:
    d.text(((W - d.textlength(l, font=f)) / 2, y), l, font=f, fill="white")
    y += lh
spaced(episodes.upper(), 1262, ImageFont.truetype(FONT.format("Heavy"), 46), accent, 9)
spaced(note.upper(), 1350, ImageFont.truetype(FONT.format("Heavy"), 27), (215, 215, 215), 5)
img.convert("RGB").save(out, quality=92)
print("saved", out)
