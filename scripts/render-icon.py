#!/usr/bin/env python3
"""Renders the Monorail app icon to assets/icon.png (1024x1024).

The design is an "M" built from three windows on a warm coral tile: the
outer two stand tall, the middle one has slid down out of place, leaving a
faint trace of where it was. The committed PNG is what the build uses, so this
only needs to run when the design changes:  python3 scripts/render-icon.py
(needs Pillow).
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SCALE = 2  # draw at 2x and downsample for smooth edges
SIZE = 1024 * SCALE


def s(value):
    return int(round(value * SCALE))


def gradient(size, stops, angle_xy=(0.55, 1.0)):
    """Linear gradient across `size`; stops are (t, rgba); angle_xy is the direction."""
    small = Image.new("RGBA", (96, 96))
    dx, dy = angle_xy
    norm = abs(dx) + abs(dy)
    for y in range(96):
        for x in range(96):
            t = ((x / 95) * dx + (y / 95) * dy) / norm
            for i in range(len(stops) - 1):
                (t0, c0), (t1, c1) = stops[i], stops[i + 1]
                if t0 <= t <= t1:
                    u = (t - t0) / max(t1 - t0, 1e-6)
                    small.putpixel((x, y), tuple(int(c0[k] + (c1[k] - c0[k]) * u) for k in range(4)))
                    break
    return small.resize(size, Image.BICUBIC)


def rounded_mask(box, radius):
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def composite(canvas, mask, layer, clip=None):
    layer = layer.copy() if isinstance(layer, Image.Image) else Image.new("RGBA", (SIZE, SIZE), layer)
    alpha = ImageChops.multiply(layer.getchannel("A"), mask if clip is None else ImageChops.multiply(mask, clip))
    layer.putalpha(alpha)
    canvas.alpha_composite(layer)


def soft(canvas, mask, color, blur, offset=(0, 0), opacity=1.0, clip=None):
    """A blurred copy of `mask` in `color`: shadows and glows."""
    layer = Image.new("RGBA", (SIZE, SIZE), color)
    alpha = mask.point(lambda v: int(v * opacity))
    layer.putalpha(alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    if clip is not None:
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), clip))
    canvas.alpha_composite(layer, offset)


def render(path):
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Tile: Apple's grid puts an 824pt rounded square in 1024.
    tile_box = (s(100), s(100), s(924), s(924))
    tile = rounded_mask(tile_box, s(186))
    # Nothing is drawn outside the tile: macOS shrinks icons whose artwork
    # (even a soft shadow) spills past its rounded-square shape onto a grey plate.
    composite(canvas, tile, gradient((SIZE, SIZE), [
        (0.0, (255, 158, 98, 255)),
        (0.5, (246, 98, 112, 255)),
        (1.0, (214, 58, 128, 255)),
    ]))
    # Light from the top-left, shade toward the bottom.
    light = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(light).ellipse((s(-60), s(-140), s(700), s(520)), fill=255)
    soft(canvas, light, (255, 236, 210, 255), s(130), opacity=0.32, clip=tile)
    shade = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(shade).ellipse((s(380), s(560), s(1180), s(1240)), fill=255)
    soft(canvas, shade, (120, 20, 90, 255), s(150), opacity=0.35, clip=tile)

    radius = s(40)
    top, bottom = 268, 756
    left = (s(226), s(top), s(386), s(bottom))
    right = (s(638), s(top), s(798), s(bottom))
    middle_home = (s(432), s(top), s(592), s(548))
    middle = (s(432), s(388), s(592), s(668))

    # Where the middle window slid from: a faint inset trace and motion lines.
    trace = rounded_mask(middle_home, radius)
    composite(canvas, trace, (255, 255, 255, 46), tile)
    inner = rounded_mask((middle_home[0] + s(6), middle_home[1] + s(6), middle_home[2] - s(6), middle_home[3] - s(6)), s(34))
    composite(canvas, inner, (214, 58, 128, 40), tile)
    draw = ImageDraw.Draw(canvas)
    for i, width in enumerate((70, 104, 70)):
        x = s(512) + (i - 1) * s(40)
        draw.rounded_rectangle((x - s(5), s(300), x + s(5), s(300 + width * 0.6)), radius=s(5), fill=(255, 255, 255, 70))

    # The two outer windows of the M: white glass with a title bar.
    for box in (left, right):
        m = rounded_mask(box, radius)
        soft(canvas, m, (90, 10, 40, 255), s(22), (0, s(16)), 0.42)
        composite(canvas, m, gradient((SIZE, SIZE), [(0, (255, 255, 255, 255)), (1, (255, 236, 240, 255))], (0, 1)))
        bar = (box[0] + s(24), box[1] + s(26), box[2] - s(24), box[1] + s(42))
        draw.rounded_rectangle(bar, radius=s(8), fill=(246, 98, 112, 70))

    # The middle window, slid down: deep plum, the window you're on.
    m = rounded_mask(middle, radius)
    soft(canvas, m, (40, 0, 30, 255), s(26), (0, s(20)), 0.55)
    composite(canvas, m, gradient((SIZE, SIZE), [(0, (64, 30, 72, 255)), (1, (34, 16, 44, 255))], (0, 1)))
    rim = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(rim).rounded_rectangle(middle, radius=radius, outline=255, width=s(4))
    composite(canvas, rim, (255, 170, 150, 120))
    # A warm accent line on the focused window.
    draw.rounded_rectangle((middle[0] + s(30), middle[3] - s(52), middle[2] - s(30), middle[3] - s(36)),
                           radius=s(8), fill=(255, 158, 98, 255))

    # Fine highlight around the tile edge.
    edge = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(edge).rounded_rectangle(tile_box, radius=s(186), outline=255, width=s(3))
    composite(canvas, edge, (255, 255, 255, 60), tile)

    canvas = canvas.resize((1024, 1024), Image.LANCZOS)
    # Clip to the exact tile shape (downsampling can ring a pixel or two outside it).
    shape = tile.resize((1024, 1024), Image.LANCZOS)
    canvas.putalpha(ImageChops.multiply(canvas.getchannel("A"), shape))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    canvas.save(path)
    print(f"Wrote {path}")


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    render(sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "assets", "icon.png"))
