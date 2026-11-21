"""Draws the Turret launcher icon: a castle turret whose battlements are
equalizer bars, with a play-button doorway, coloured green to red for the
move between Spotify and YouTube.

Run from the mobile folder:  python tool/make_icon.py
Then:                        dart run flutter_launcher_icons
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supersampling for smooth edges
BACKGROUND = (20, 22, 26, 255)
STOPS = [(0.0, (34, 211, 107)), (0.5, (255, 197, 61)), (1.0, (255, 75, 75))]
MERLONS = [0.72, 1.0, 0.55, 0.86]  # relative heights, like equalizer bars


def gradient(width, height, x0, x1):
    strip = Image.new("RGB", (width, 1))
    for x in range(width):
        t = min(1.0, max(0.0, (x - x0) / (x1 - x0)))
        for (a, ca), (b, cb) in zip(STOPS, STOPS[1:]):
            if a <= t <= b:
                k = (t - a) / (b - a)
                strip.putpixel((x, 0), tuple(round(ca[i] + (cb[i] - ca[i]) * k) for i in range(3)))
                break
    return strip.resize((width, height))


def draw(content, background):
    """content: fraction of the canvas the turret spans; background: RGBA or None."""
    n = SIZE * SS
    mask = Image.new("L", (n, n), 0)
    pen = ImageDraw.Draw(mask)

    width = n * content
    height = width * 1.08
    left, top = (n - width) / 2, (n - height) / 2
    right, bottom = left + width, top + height
    body_top = top + height * 0.42
    radius = width * 0.07

    # Tower body.
    pen.rounded_rectangle([left, body_top, right, bottom], radius=radius, fill=255)
    pen.rectangle([left, body_top, right, body_top + radius * 2], fill=255)  # square top corners
    # Battlements of different heights.
    bar, gap = width * 0.19, width * 0.08
    for index, level in enumerate(MERLONS):
        x = left + index * (bar + gap)
        y = body_top - (body_top - top) * level
        pen.rounded_rectangle([x, y, x + bar, body_top + bar], radius=bar * 0.32, fill=255)
    # Play-button doorway.
    cx, cy = (left + right) / 2, (body_top + bottom) / 2
    t = (bottom - body_top) * 0.50
    pen.polygon([(cx - t * 0.36, cy - t * 0.5), (cx - t * 0.36, cy + t * 0.5), (cx + t * 0.52, cy)], fill=0)

    colour = gradient(n, n, left, right).convert("RGBA")
    canvas = Image.new("RGBA", (n, n), background or (0, 0, 0, 0))
    canvas.paste(colour, (0, 0), mask)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    draw(0.56, BACKGROUND).save(out / "icon.png")        # full icon
    draw(0.40, None).save(out / "icon_fg.png")           # adaptive-icon foreground
    print("wrote", out)
