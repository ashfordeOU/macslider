#!/usr/bin/env python3
"""Renders the installer window background to assets/dmg/background.png (660x420)
and background@2x.png. Run when the design changes (needs Pillow)."""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 660, 420
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def font(size, bold=False):
    names = ["/System/Library/Fonts/SFNS.ttf", "/Library/Fonts/Arial Bold.ttf" if bold else "/Library/Fonts/Arial.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    for name in names:
        if os.path.exists(name):
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def render(scale):
    s = lambda v: int(round(v * scale))
    img = Image.new("RGBA", (s(W), s(H)))
    # Warm, light gradient so dark icon labels stay readable in Finder.
    top, bottom = (255, 246, 240), (250, 226, 232)
    for y in range(s(H)):
        t = y / (s(H) - 1)
        ImageDraw.Draw(img).line([(0, y), (s(W), y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((s(-120), s(-160), s(320), s(200)), fill=(255, 170, 120, 90))
    gd.ellipse((s(420), s(260), s(820), s(560)), fill=(214, 58, 128, 60))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(s(60))))

    d = ImageDraw.Draw(img)
    # Title.
    title = "Monorail"
    f = font(s(26), bold=True)
    tw = d.textlength(title, font=f)
    d.text(((s(W) - tw) / 2, s(34)), title, fill=(70, 30, 70, 255), font=f)
    sub = "Every window rides one rail."
    f2 = font(s(13))
    sw = d.textlength(sub, font=f2)
    d.text(((s(W) - sw) / 2, s(70)), sub, fill=(150, 90, 120, 255), font=f2)

    # Arrow from the app (x=170) to Applications (x=490), at icon height (y=205).
    y = s(200)
    x0, x1 = s(258), s(400)
    dash, gap = s(10), s(7)
    x = x0
    while x < x1 - s(14):
        d.rounded_rectangle((x, y - s(3), min(x + dash, x1 - s(14)), y + s(3)), radius=s(3), fill=(238, 98, 112, 255))
        x += dash + gap
    d.polygon([(x1, y), (x1 - s(18), y - s(13)), (x1 - s(18), y + s(13))], fill=(238, 98, 112, 255))

    # Instructions.
    line1 = "Drag Monorail into your Applications folder"
    f3 = font(s(15), bold=True)
    w1 = d.textlength(line1, font=f3)
    d.text(((s(W) - w1) / 2, s(318)), line1, fill=(70, 30, 70, 255), font=f3)
    line2 = "Then open it from Applications and allow Accessibility when asked."
    f4 = font(s(12))
    w2 = d.textlength(line2, font=f4)
    d.text(((s(W) - w2) / 2, s(344)), line2, fill=(140, 90, 115, 255), font=f4)
    return img.convert("RGB")


out = os.path.join(ROOT, "assets", "dmg")
os.makedirs(out, exist_ok=True)
render(1).save(os.path.join(out, "background.png"))
render(2).save(os.path.join(out, "background@2x.png"))
print("Wrote", out)
