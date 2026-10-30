#!/usr/bin/env python3
"""Renders the MacSlider app icon to assets/icon.png (1024x1024).

The committed PNG is what the build uses, so this only needs to run when
the design changes:  python3 scripts/render-icon.py  (needs Pillow)
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SCALE = 2  # draw at 2x and downsample for smooth edges
SIZE = 1024 * SCALE


def s(value):
    return int(round(value * SCALE))


def vertical_gradient(size, top, bottom):
    width, height = size
    gradient = Image.new("RGBA", (1, height))
    for y in range(height):
        t = y / max(height - 1, 1)
        gradient.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    return gradient.resize((width, height))


def diagonal_gradient(size, start, end):
    width, height = size
    small = Image.new("RGBA", (64, 64))
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            small.putpixel((x, y), tuple(int(start[i] + (end[i] - start[i]) * t) for i in range(4)))
    return small.resize((width, height), Image.BICUBIC)


def rounded_mask(size, box, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def paste_shadow(canvas, mask, offset, blur, opacity):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = mask.point(lambda v: int(v * opacity))
    shadow.putalpha(alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow, offset)


def window_card(canvas, clip, box, radius, fill_top, fill_bottom, bar_color, dots, opacity=1.0, glow=False):
    """Draws a window: body gradient, title bar, traffic lights, content lines."""
    x0, y0, x1, y1 = box
    mask = rounded_mask(canvas.size, box, radius)
    mask = ImageChops.multiply(mask, clip)
    if glow:
        halo = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
        halo.putalpha(mask.point(lambda v: int(v * 0.55)))
        canvas.alpha_composite(halo.filter(ImageFilter.GaussianBlur(s(38))))
    paste_shadow(canvas, mask, (0, s(18)), s(28), 0.45 * opacity)

    body = vertical_gradient(canvas.size, fill_top, fill_bottom)
    body.putalpha(mask.point(lambda v: int(v * opacity)))
    canvas.alpha_composite(body)

    draw = ImageDraw.Draw(canvas)
    bar_height = (y1 - y0) * 0.16
    bar = Image.new("RGBA", canvas.size, bar_color)
    bar_mask = rounded_mask(canvas.size, (x0, y0, x1, y0 + bar_height + radius), radius)
    bar_mask = ImageChops.multiply(bar_mask, rounded_mask(canvas.size, (x0, y0, x1, y0 + bar_height), 0))
    bar_mask = ImageChops.multiply(bar_mask, clip)
    bar.putalpha(bar_mask.point(lambda v: int(v * opacity)))
    canvas.alpha_composite(bar)

    if dots:
        r = bar_height * 0.17
        cy = y0 + bar_height / 2
        for i, color in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
            cx = x0 + bar_height * 0.55 + i * r * 3.1
            draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color + (int(255 * opacity),))

    # Content: a few soft lines.
    line_color = (90, 80, 170, int(70 * opacity))
    top = y0 + bar_height + (y1 - y0) * 0.1
    widths = [0.62, 0.78, 0.48, 0.7]
    for i, w in enumerate(widths):
        ly = top + i * (y1 - y0) * 0.12
        if ly + s(18) > y1 - s(20):
            break
        lx = x0 + (x1 - x0) * 0.1
        line = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(line).rounded_rectangle(
            (lx, ly, lx + (x1 - x0) * w * 0.85, ly + s(18)), radius=s(9), fill=line_color)
        line.putalpha(ImageChops.multiply(line.getchannel("A"), clip))
        canvas.alpha_composite(line)


def render(path):
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # The tile: Apple's icon grid puts an 824pt rounded square in 1024.
    tile_box = (s(100), s(100), s(924), s(924))
    tile_radius = s(186)
    tile_mask = rounded_mask(canvas.size, tile_box, tile_radius)
    paste_shadow(canvas, tile_mask, (0, s(14)), s(24), 0.35)

    background = diagonal_gradient(canvas.size, (24, 22, 74, 255), (112, 52, 214, 255))
    # A soft light from the top-left.
    light = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(light).ellipse((s(40), s(-80), s(760), s(560)), fill=(130, 160, 255, 90))
    background.alpha_composite(light.filter(ImageFilter.GaussianBlur(s(120))))
    background.putalpha(tile_mask)
    canvas.alpha_composite(background)

    # Windows on the strip: neighbours cut off by the tile edge, the focused one in the middle.
    card_top, card_bottom = s(270), s(700)
    window_card(canvas, tile_mask, (s(-30), s(310), s(250), s(660)), s(34),
                (226, 222, 255, 255), (186, 176, 246, 255), (246, 244, 255, 255), dots=False, opacity=0.42)
    window_card(canvas, tile_mask, (s(774), s(310), s(1054), s(660)), s(34),
                (226, 222, 255, 255), (186, 176, 246, 255), (246, 244, 255, 255), dots=False, opacity=0.42)
    window_card(canvas, tile_mask, (s(290), card_top, s(734), card_bottom), s(40),
                (255, 255, 255, 255), (232, 228, 255, 255), (244, 242, 255, 255), dots=True, glow=True)

    # Slider: a track with a glowing knob under the focused window.
    draw = ImageDraw.Draw(canvas)
    track_y = s(790)
    track = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(track).rounded_rectangle((s(240), track_y - s(11), s(784), track_y + s(11)),
                                            radius=s(11), fill=(255, 255, 255, 70))
    canvas.alpha_composite(track)
    knob_box = (s(410), track_y - s(30), s(614), track_y + s(30))
    knob_mask = rounded_mask(canvas.size, knob_box, s(30))
    glow = Image.new("RGBA", canvas.size, (255, 110, 90, 0))
    glow.putalpha(knob_mask)
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(s(26))))
    knob = diagonal_gradient(canvas.size, (255, 158, 64, 255), (255, 72, 120, 255))
    knob.putalpha(knob_mask)
    canvas.alpha_composite(knob)
    draw.rounded_rectangle((s(440), track_y - s(20), s(584), track_y - s(8)), radius=s(6), fill=(255, 255, 255, 90))

    # Subtle inner edge highlight on the tile.
    edge = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(tile_box, radius=tile_radius, outline=(255, 255, 255, 40), width=s(3))
    canvas.alpha_composite(edge)

    canvas = canvas.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    canvas.save(path)
    print(f"Wrote {path}")


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    render(sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "assets", "icon.png"))
