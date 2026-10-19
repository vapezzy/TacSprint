"""Draws the app icon: dark backdrop, the rifle silhouette, an orange bar and
a small crosshair.      python tools/make_icon.py  ->  icon.png (1024x1024)"""
import os

from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "icon.png")
ACCENT = (242, 158, 41)
RIFLE = [(4, 26), (40, 26), (44, 22), (58, 22), (58, 30), (50, 30), (48, 34), (40, 34), (34, 46),
         (26, 46), (30, 34), (20, 34), (16, 42), (8, 42), (10, 34), (4, 34)]


def main():
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            t = (x * 0.35 + (S - y)) / (S * 1.35)
            d = ((x - S / 2) ** 2 + (y - S / 2) ** 2) ** 0.5 / (S * 0.72)
            k = 1.0 - max(0.0, d - 0.35) * 0.9
            px[x, y] = tuple(int((a + (b - a) * t) * k) for a, b in zip((9, 11, 15), (30, 34, 41)))
    draw = ImageDraw.Draw(img)
    for i in range(0, S, 64):                                   # fine grid
        draw.line([(i, 0), (i, S)], fill=(40, 44, 52), width=2)
        draw.line([(0, i), (S, i)], fill=(40, 44, 52), width=2)
    scale, ox, oy = 14.5, 512 - 31 * 14.5, 470 - 31 * 14.5
    pts = [(ox + x * scale, oy + y * scale) for x, y in RIFLE]
    glow = Image.new("L", (S, S))
    ImageDraw.Draw(glow).polygon(pts, fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(28))
    img.paste(Image.new("RGB", (S, S), ACCENT), (0, 0), glow.point(lambda v: int(v * 0.45)))
    draw = ImageDraw.Draw(img)
    draw.polygon(pts, fill=(236, 238, 242))
    draw.rectangle([ox + 44 * scale, oy + 16 * scale, ox + 54 * scale, oy + 20 * scale], fill=(236, 238, 242))
    draw.rectangle([150, 790, 874, 818], fill=ACCENT)           # accent bar
    cx, cy, r = 250, 230, 70                                    # crosshair
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ACCENT, width=14)
    for a, b in (((cx, cy - 115), (cx, cy - 80)), ((cx, cy + 80), (cx, cy + 115)),
                 ((cx - 115, cy), (cx - 80, cy)), ((cx + 80, cy), (cx + 115, cy))):
        draw.line([a, b], fill=ACCENT, width=14)
    img.save(OUT)
    print("icon", OUT)


if __name__ == "__main__":
    main()
