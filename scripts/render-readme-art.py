#!/usr/bin/env python3
"""Writes the README illustrations to assets/readme/*.svg.

They are hand-built SVG (no screenshots), so they stay sharp, small and free of
anyone's private windows. Run after changing the design: python3 scripts/render-readme-art.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "readme")
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, sans-serif"
CORAL, PINK, PLUM, DEEP = "#FF9E62", "#F66270", "#D63A80", "#2A1430"

# Colours for the windows on the strip (one per app).
APPS = ["#5B8CFF", "#B06BFF", "#FF5F9E", "#FF9445", "#45D18C", "#33CCDB", "#FFCC40"]


def window(x, y, w, h, color, focused=False, opacity=1.0):
    """A little window: title bar with traffic lights, a coloured header, content lines."""
    r = 10
    lines = "".join(
        f'<rect x="{x + 14}" y="{y + 44 + i * 16}" width="{(w - 28) * f:.0f}" height="7" rx="3.5" fill="#000" opacity="0.10"/>'
        for i, f in enumerate([0.8, 0.6, 0.9, 0.5, 0.7]) if 44 + i * 16 + 7 < h - 10
    )
    ring = f'<rect x="{x - 3}" y="{y - 3}" width="{w + 6}" height="{h + 6}" rx="{r + 3}" fill="none" stroke="#fff" stroke-width="3"/>' if focused else ""
    return f'''<g opacity="{opacity}">
  {ring}
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="#fff"/>
  <path d="M{x} {y + r} a{r} {r} 0 0 1 {r} -{r} h{w - 2 * r} a{r} {r} 0 0 1 {r} {r} v18 h-{w} z" fill="{color}"/>
  <circle cx="{x + 13}" cy="{y + 14}" r="4" fill="#FF5F57"/>
  <circle cx="{x + 26}" cy="{y + 14}" r="4" fill="#FEBC2E"/>
  <circle cx="{x + 39}" cy="{y + 14}" r="4" fill="#28C840"/>
  {lines}
</g>'''


def strip_windows(x0, y, h, widths, gap, focused=None, opacity=1.0):
    parts, x = [], x0
    for i, w in enumerate(widths):
        if isinstance(w, tuple):  # a slide of two tiles stacked side by side
            w1, w2 = w
            parts.append(window(x, y, w1, h, APPS[i % len(APPS)], focused == i, opacity))
            parts.append(window(x + w1 + 6, y, w2, h, APPS[(i + 3) % len(APPS)], focused == i, opacity))
            x += w1 + 6 + w2 + gap
        else:
            parts.append(window(x, y, w, h, APPS[i % len(APPS)], focused == i, opacity))
            x += w + gap
    return "\n".join(parts), x - gap - x0


def m_icon(x, y, size):
    """The Monorail mark: an M of three windows, the middle one slid down."""
    s = size / 100
    return f'''<g transform="translate({x} {y}) scale({s})">
  <rect width="100" height="100" rx="23" fill="#fff" opacity="0.18"/>
  <rect x="15" y="17" width="19" height="66" rx="5" fill="#fff"/>
  <rect x="66" y="17" width="19" height="66" rx="5" fill="#fff"/>
  <rect x="40.5" y="17" width="19" height="40" rx="5" fill="#fff" opacity="0.25"/>
  <rect x="40.5" y="34" width="19" height="40" rx="5" fill="{DEEP}"/>
  <rect x="44" y="66" width="12" height="3" rx="1.5" fill="{CORAL}"/>
</g>'''


def banner():
    W, H = 1280, 460
    sx, sy, sw, sh = 650, 64, 560, 300  # the "screen"
    widths = [260, (170, 170), 260, 300, (160, 160), 260, 240]
    content, total = strip_windows(0, 0, sh - 56, widths, 14, focused=2)
    ghost, _ = strip_windows(0, 0, sh - 56, widths, 14, opacity=0.28)
    travel = total - (sw - 40)
    anim = (f'<animateTransform attributeName="transform" type="translate" dur="14s" repeatCount="indefinite" '
            f'calcMode="spline" keyTimes="0;0.2;0.45;0.7;1" '
            f'keySplines="0.45 0 0.2 1;0.45 0 0.2 1;0.45 0 0.2 1;0.45 0 0.2 1" '
            f'values="{sx + 20} {sy + 28};{sx + 20 - travel * 0.35:.0f} {sy + 28};{sx + 20 - travel:.0f} {sy + 28};'
            f'{sx + 20 - travel * 0.6:.0f} {sy + 28};{sx + 20} {sy + 28}"/>')
    # Slider bar under the screen: tiles for every slide and a frame for what's on screen.
    bx, by, bw = sx + 30, sy + sh + 22, sw - 60
    scale = (bw - 20) / total
    tiles, x = [], 0
    for i, w in enumerate(widths):
        width = (w[0] + 6 + w[1]) if isinstance(w, tuple) else w
        tiles.append(f'<rect x="{bx + 10 + x * scale:.1f}" y="{by + 9}" width="{max(width * scale - 3, 4):.1f}" height="22" rx="5" fill="#fff" opacity="0.35"/>')
        x += width + 14
    frame_w = (sw - 40) * scale
    frame_anim = (f'<animateTransform attributeName="transform" type="translate" dur="14s" repeatCount="indefinite" '
                  f'calcMode="spline" keyTimes="0;0.2;0.45;0.7;1" '
                  f'keySplines="0.45 0 0.2 1;0.45 0 0.2 1;0.45 0 0.2 1;0.45 0 0.2 1" '
                  f'values="0 0;{travel * 0.35 * scale:.1f} 0;{travel * scale:.1f} 0;{travel * 0.6 * scale:.1f} 0;0 0"/>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="Monorail by Ashforde®: every window rides one rail">
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="{CORAL}"/><stop offset="0.5" stop-color="{PINK}"/><stop offset="1" stop-color="{PLUM}"/>
  </linearGradient>
  <pattern id="dots" width="22" height="22" patternUnits="userSpaceOnUse"><circle cx="11" cy="11" r="1.3" fill="#fff" opacity="0.18"/></pattern>
  <clipPath id="card"><rect width="{W}" height="{H}" rx="28"/></clipPath>
  <clipPath id="screen"><rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="16"/></clipPath>
  <!-- Off-screen windows fade out before they reach the title. -->
  <linearGradient id="fadeGrad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0.43" stop-color="#fff" stop-opacity="0"/><stop offset="0.5" stop-color="#fff" stop-opacity="1"/>
  </linearGradient>
  <mask id="fade"><rect width="{W}" height="{H}" fill="url(#fadeGrad)"/></mask>
</defs>
<g clip-path="url(#card)">
  <rect width="{W}" height="{H}" fill="url(#bg)"/>
  <rect width="{W}" height="{H}" fill="url(#dots)"/>
  <circle cx="1180" cy="40" r="220" fill="#fff" opacity="0.08"/>
  <circle cx="120" cy="470" r="200" fill="{DEEP}" opacity="0.10"/>
  <!-- The rail runs past the screen: faint windows outside it. -->
  <g mask="url(#fade)"><g>{anim}{ghost}</g></g>
  <rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="16" fill="{DEEP}" opacity="0.55"/>
  <g clip-path="url(#screen)"><g>{anim}{content}</g></g>
  <rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="16" fill="none" stroke="#fff" stroke-opacity="0.75" stroke-width="2"/>
  <rect x="{bx}" y="{by}" width="{bw}" height="40" rx="20" fill="#fff" opacity="0.2"/>
  {''.join(tiles)}
  <g>{frame_anim}<rect x="{bx + 8}" y="{by + 5}" width="{frame_w:.1f}" height="30" rx="8" fill="#fff" fill-opacity="0.15" stroke="#fff" stroke-width="2.5"/></g>
  {m_icon(70, 96, 92)}
  <text x="70" y="262" font-family="{FONT}" font-size="76" font-weight="800" fill="#fff" letter-spacing="-1.5">Monorail<tspan dx="16" font-size="30" font-weight="600" letter-spacing="0" opacity="0.85">by Ashforde®</tspan></text>
  <text x="72" y="306" font-family="{FONT}" font-size="27" font-weight="600" fill="#fff" opacity="0.95">Every window rides one rail.</text>
  <text x="72" y="344" font-family="{FONT}" font-size="19" fill="#fff" opacity="0.8">A scrolling window manager for macOS.</text>
  <text x="72" y="372" font-family="{FONT}" font-size="19" fill="#fff" opacity="0.8">Free and open source.</text>
</g>
</svg>
'''


def how_it_works():
    W, H = 1280, 330
    widths = [230, 230, (150, 150), 300, 230, 230]
    content, total = strip_windows(0, 0, 150, widths, 16, focused=2)
    x0 = (W - total) / 2
    screen_x = x0 + 230 + 16 + 230 + 16 - 24
    screen_w = 150 + 6 + 150 + 16 + 300 + 48
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="Windows sit side by side on a strip that runs past the screen edges">
<defs><linearGradient id="bg2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF6F0"/><stop offset="1" stop-color="#FBE3EA"/></linearGradient></defs>
<rect width="{W}" height="{H}" rx="24" fill="url(#bg2)"/>
<rect x="40" y="226" width="{W - 80}" height="6" rx="3" fill="{PINK}" opacity="0.35"/>
<g transform="translate({x0} 66)">{content}</g>
<rect x="{screen_x}" y="44" width="{screen_w}" height="194" rx="16" fill="none" stroke="{PLUM}" stroke-width="3" stroke-dasharray="10 7"/>
<text x="{screen_x + screen_w / 2}" y="32" text-anchor="middle" font-family="{FONT}" font-size="17" font-weight="700" fill="{PLUM}">Your screen</text>
<text x="150" y="268" text-anchor="middle" font-family="{FONT}" font-size="16" fill="#8A5A74">← windows wait off-screen</text>
<text x="{W - 150}" y="268" text-anchor="middle" font-family="{FONT}" font-size="16" fill="#8A5A74">new windows open next →</text>
<text x="{W / 2}" y="298" text-anchor="middle" font-family="{FONT}" font-size="18" font-weight="600" fill="{DEEP}">Nothing shrinks, nothing overlaps: slide the strip with a key, a swipe or the mouse wheel.</text>
</svg>
'''


def layouts():
    import sys
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    W, H = 1280, 470
    cards = [
        ("Side by side", [(0, 0, 0.5, 1), (0.5, 0, 0.5, 1)]),
        ("Up and down", [(0, 0, 1, 0.5), (0, 0.5, 1, 0.5)]),
        ("Grid · 4", [(0, 0, .5, .5), (.5, 0, .5, .5), (0, .5, .5, .5), (.5, .5, .5, .5)]),
        ("Grid · 6", [(c / 3, r / 2, 1 / 3, .5) for r in range(2) for c in range(3)]),
        ("Main + side", [(0, 0, .6, 1), (.6, 0, .4, .5), (.6, .5, .4, .5)]),
        ("Main + bottom", [(0, 0, 1, .6), (0, .6, .5, .4), (.5, .6, .5, .4)]),
        ("Columns · 3", [(0, 0, 1 / 3, 1), (1 / 3, 0, 1 / 3, 1), (2 / 3, 0, 1 / 3, 1)]),
        ("Tabs", None),
    ]
    cw, ch, gap = 280, 160, 26
    x0 = (W - (4 * cw + 3 * gap)) / 2
    parts = []
    for n, (title, tiles) in enumerate(cards):
        cx = x0 + (n % 4) * (cw + gap)
        cy = 52 + (n // 4) * (ch + 62)
        parts.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="14" fill="#fff" stroke="#F0D5DE" stroke-width="2"/>')
        ix, iy, iw, ih = cx + 12, cy + 12, cw - 24, ch - 24
        if tiles is None:
            for t in range(3):
                parts.append(f'<rect x="{ix + t * 72}" y="{iy}" width="66" height="18" rx="6" fill="{APPS[t]}" opacity="{1 if t == 1 else 0.35}"/>')
            parts.append(window(ix, iy + 24, iw, ih - 24, APPS[1]))
        else:
            for t, (ux, uy, uw, uh) in enumerate(tiles):
                parts.append(window(ix + ux * iw + 3, iy + uy * ih + 3, uw * iw - 6, uh * ih - 6, APPS[t % len(APPS)]))
        parts.append(f'<text x="{cx + cw / 2}" y="{cy + ch + 30}" text-anchor="middle" font-family="{FONT}" font-size="18" font-weight="700" fill="{DEEP}">{title}</text>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="Slide layouts">
<rect width="{W}" height="{H}" rx="24" fill="#FFF8F5"/>
<text x="{W / 2}" y="34" text-anchor="middle" font-family="{FONT}" font-size="15" font-weight="600" fill="#9A6A84" letter-spacing="2">UP TO SIX WINDOWS PER SLIDE · ⌃⌥G CYCLES · RIGHT-CLICK TO CHOOSE</text>
{''.join(parts)}
</svg>
'''


# ---------------------------------------------------------------------------
# The tour: drawn product shots of each part of the app.

WS = ["#5B8CFF", "#B06BFF", "#FF5F9E", "#FF9445", "#45D18C"]
INK, MUTED = "#2A1430", "#8A5A74"


def brand_tag(W, H, light=False):
    """Monorail by Ashforde® in the corner of every picture."""
    fill = "#fff" if light else INK
    return (f'<text x="{W - 28}" y="{H - 22}" text-anchor="end" font-family="{FONT}" font-size="14" fill="{fill}" opacity="0.55">'
            f'<tspan font-weight="800">Monorail</tspan> by Ashforde®</text>')


def card(W, H, body, label, dark=False):
    """A rounded picture with a soft background and the brand tag."""
    bg = ('<linearGradient id="cardbg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22123A"/>'
          '<stop offset="1" stop-color="#3B1450"/></linearGradient>') if dark else (
          '<linearGradient id="cardbg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFF6F0"/>'
          '<stop offset="1" stop-color="#FBE3EA"/></linearGradient>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="{label}">
<defs>{bg}
  <linearGradient id="wall" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3A2A6E"/><stop offset="0.55" stop-color="#7A2E78"/><stop offset="1" stop-color="#C2456E"/></linearGradient>
  <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#2A1430" flood-opacity="0.28"/></filter>
</defs>
<rect width="{W}" height="{H}" rx="24" fill="url(#cardbg)"/>
{body}
{brand_tag(W, H, light=dark)}
</svg>
'''


def desktop(x, y, w, h, status="2 · 3/7"):
    """A Mac screen: wallpaper, menu bar with the Monorail item, and a Dock."""
    return f'''<g filter="url(#shadow)"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" fill="url(#wall)"/></g>
<rect x="{x}" y="{y}" width="{w}" height="22" rx="0" fill="#000" opacity="0.28"/>
<rect x="{x}" y="{y}" width="{w}" height="14" rx="14" fill="#000" opacity="0"/>
<text x="{x + 16}" y="{y + 15}" font-family="{FONT}" font-size="11" font-weight="700" fill="#fff"></text>
<text x="{x + 34}" y="{y + 15}" font-family="{FONT}" font-size="11" font-weight="700" fill="#fff">Safari</text>
<text x="{x + 80}" y="{y + 15}" font-family="{FONT}" font-size="11" fill="#fff" opacity="0.85">File   Edit   View   Window</text>
{menu_item(x + w - 150, y + 4)}
<text x="{x + w - 128}" y="{y + 15}" font-family="{FONT}" font-size="11" fill="#fff">{status}</text>
<text x="{x + w - 60}" y="{y + 15}" font-family="{FONT}" font-size="11" fill="#fff" opacity="0.85">Fri 9:41</text>
<rect x="{x + w / 2 - 110}" y="{y + h - 26}" width="220" height="20" rx="8" fill="#fff" opacity="0.22"/>
''' + "".join(
        f'<rect x="{x + w / 2 - 100 + i * 25}" y="{y + h - 23}" width="15" height="14" rx="4" fill="{APPS[i % len(APPS)]}"/>' for i in range(8))


def menu_item(x, y):
    """The menu bar glyph: an M of three windows."""
    return (f'<g transform="translate({x} {y})"><rect x="0" y="1" width="3.5" height="12" rx="1" fill="#fff"/>'
            f'<rect x="5" y="4" width="3.5" height="8" rx="1" fill="#fff"/><rect x="10" y="1" width="3.5" height="12" rx="1" fill="#fff"/></g>')


def tiles_in(x, y, w, h, frames, colors, gap=4, dim=None):
    """Windows laid out by unit frames inside a box, with gaps between them."""
    out = []
    for i, (ux, uy, uw, uh) in enumerate(frames):
        out.append(window(x + ux * w + gap / 2, y + uy * h + gap / 2, uw * w - gap, uh * h - gap, colors[i % len(colors)],
                          opacity=1 if dim is None or i in dim else 0.35))
    return "".join(out)


def overview():
    W, H = 1280, 640
    rows = [
        ("Work", WS[0], [[(0, 0, .5, 1), (.5, 0, .5, 1)], [(0, 0, 1, 1)], [(0, 0, .5, .5), (.5, 0, .5, .5), (0, .5, .5, .5), (.5, .5, .5, .5)], [(0, 0, .6, 1), (.6, 0, .4, .5), (.6, .5, .4, .5)]], True),
        ("Chat", WS[1], [[(0, 0, 1, 1)], [(0, 0, .5, 1), (.5, 0, .5, 1)], [(0, 0, 1, 1)]], False),
        ("Design", WS[2], [[(0, 0, 1, .6), (0, .6, .5, .4), (.5, .6, .5, .4)], [(0, 0, .5, 1), (.5, 0, .5, 1)]], False),
    ]
    parts = [f'''<text x="60" y="78" font-family="{FONT}" font-size="34" font-weight="800" fill="#fff">Overview</text>
<text x="232" y="78" font-family="{FONT}" font-size="15" font-weight="700" fill="#fff" opacity="0.55">Monorail by Ashforde®</text>
<text x="60" y="106" font-family="{FONT}" font-size="14" fill="#fff" opacity="0.65">Click or arrow keys to jump · drag windows between slides · drop on the bin to close · ⌥ + pinch to open</text>
<rect x="{W - 360}" y="56" width="130" height="30" rx="15" fill="#fff" opacity="0.12"/>
<text x="{W - 295}" y="76" text-anchor="middle" font-family="{FONT}" font-size="13" fill="#fff">Drop to close</text>
<rect x="{W - 216}" y="56" width="156" height="30" rx="15" fill="#fff" opacity="0.12"/>
<text x="{W - 138}" y="76" text-anchor="middle" font-family="{FONT}" font-size="13" fill="#fff">Reset to smart pairs</text>''']
    y = 132
    for name, color, slides, active in rows:
        rh = 150
        parts.append(f'<rect x="44" y="{y}" width="{W - 88}" height="{rh}" rx="18" fill="{color}" opacity="{0.2 if active else 0.1}"/>')
        parts.append(f'<rect x="44" y="{y}" width="{W - 88}" height="{rh}" rx="18" fill="none" stroke="{color}" stroke-opacity="{0.9 if active else 0.35}" stroke-width="{2 if active else 1}"/>')
        parts.append(f'<circle cx="68" cy="{y + 24}" r="5" fill="{color}"/>')
        parts.append(f'<text x="82" y="{y + 29}" font-family="{FONT}" font-size="15" font-weight="700" fill="#fff">{name}</text>')
        parts.append(f'<text x="{82 + len(name) * 9 + 12}" y="{y + 29}" font-family="{FONT}" font-size="13" fill="#fff" opacity="0.6">{len(slides)} slides</text>')
        if active:
            parts.append(f'<rect x="{82 + len(name) * 9 + 76}" y="{y + 15}" width="62" height="20" rx="10" fill="{color}" opacity="0.45"/>'
                         f'<text x="{82 + len(name) * 9 + 107}" y="{y + 29}" text-anchor="middle" font-family="{FONT}" font-size="11" font-weight="700" fill="#fff">Current</text>')
        x = 68
        for n, frames in enumerate(slides):
            cw = 200 if len(frames) == 1 else 250
            parts.append(f'<rect x="{x}" y="{y + 44}" width="{cw}" height="92" rx="10" fill="#fff" opacity="0.07"/>')
            if active and n == 0:
                parts.append(f'<rect x="{x - 2}" y="{y + 42}" width="{cw + 4}" height="96" rx="11" fill="none" stroke="{color}" stroke-width="2.5"/>')
            parts.append(tiles_in(x + 4, y + 48, cw - 8, 84, frames, APPS[n:] + APPS[:n]))
            x += cw + 22
        y += rh + 18
    # The arrow-key selection ring hopping between slides.
    parts.append(f'''<rect x="66" y="174" width="254" height="96" rx="11" fill="none" stroke="#fff" stroke-width="3">
  <animate attributeName="x" dur="6s" repeatCount="indefinite" values="66;66;338;338;560;560;66" keyTimes="0;0.2;0.3;0.5;0.6;0.85;1"/>
  <animate attributeName="width" dur="6s" repeatCount="indefinite" values="254;254;204;204;254;254;254" keyTimes="0;0.2;0.3;0.5;0.6;0.85;1"/>
</rect>''')
    return card(W, H, "".join(parts), "The overview: every workspace and slide on one colourful canvas", dark=True)


def slider():
    W, H = 1280, 560
    sx, sy, sw, sh = 140, 40, 1000, 470
    parts = [desktop(sx, sy, sw, sh)]
    # Two windows of the current slide, with a gap between them.
    parts.append(tiles_in(sx + 14, sy + 34, sw - 28, sh - 150, [(0, 0, .5, 1), (.5, 0, .5, 1)], [APPS[0], APPS[2]], gap=12))
    # The slider bar.
    bx, by, bw, bh = sx + 230, sy + sh - 100, 540, 46
    parts.append(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="23" fill="#fff" opacity="0.85" filter="url(#shadow)"/>')
    for i in range(3):
        parts.append(f'<circle cx="{bx + 22 + i * 13}" cy="{by + 23}" r="4" fill="{WS[0] if i == 0 else "#2A1430"}" opacity="{1 if i == 0 else 0.25}"/>')
    tx = bx + 70
    for i in range(7):
        tw = 58
        parts.append(f'<rect x="{tx}" y="{by + 9}" width="{tw}" height="28" rx="6" fill="{APPS[i % len(APPS)]}" opacity="0.3"/>')
        parts.append(f'<rect x="{tx + tw / 2 - 8}" y="{by + 15}" width="16" height="16" rx="4" fill="{APPS[i % len(APPS)]}"/>')
        tx += tw + 6
    parts.append(f'''<rect x="{bx + 132}" y="{by + 5}" width="124" height="36" rx="9" fill="none" stroke="{PLUM}" stroke-width="2.5">
  <animate attributeName="x" dur="8s" repeatCount="indefinite" values="{bx + 132};{bx + 132};{bx + 260};{bx + 260};{bx + 132}" keyTimes="0;0.3;0.45;0.8;1"/>
</rect>''')
    # Hover preview above the bar, windows drawn where they are, with gaps.
    px, py, pw, ph = bx + 150, by - 190, 300, 176
    parts.append(f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="14" fill="#fff" opacity="0.92" filter="url(#shadow)"/>')
    parts.append(f'<text x="{px + 16}" y="{py + 24}" font-family="{FONT}" font-size="13" font-weight="700" fill="{INK}">3  Safari + Notes</text>')
    parts.append(f'<rect x="{px + 10}" y="{py + 34}" width="{pw - 20}" height="{ph - 44}" rx="9" fill="{PLUM}" opacity="0.12"/>')
    parts.append(tiles_in(px + 14, py + 38, pw - 28, ph - 52, [(0, 0, .5, 1), (.5, 0, .5, 1)], [APPS[1], APPS[3]], gap=10))
    parts.append(f'<text x="{W / 2}" y="{H - 14}" text-anchor="middle" font-family="{FONT}" font-size="15" fill="{MUTED}">Drag the frame to slide · hover for a live preview · hold ⌥ to peek · swipe up to park the workspace</text>')
    return card(W, H, "".join(parts), "The slider bar with a live preview of a slide")


def menubar():
    W, H = 1280, 520
    sx, sy, sw, sh = 140, 34, 1000, 440
    parts = [desktop(sx, sy, sw, sh)]
    parts.append(tiles_in(sx + 14, sy + 34, sw - 28, sh - 66, [(0, 0, .5, 1), (.5, 0, .5, 1)], [APPS[4], APPS[5]], gap=12))
    # The panel right under the icon.
    ix = sx + sw - 150
    px, py, pw, ph = ix - 280, sy + 28, 560, 250
    parts.append(f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="16" fill="#1E1A24" opacity="0.94" filter="url(#shadow)"/>')
    parts.append(f'<rect x="{ix - 6}" y="{sy + 2}" width="40" height="18" rx="5" fill="#fff" opacity="0.25"/>')
    parts.append(f'<text x="{px + 20}" y="{py + 32}" font-family="{FONT}" font-size="16" font-weight="800" fill="#fff">Monorail <tspan font-size="11" font-weight="500" opacity="0.6">by Ashforde®</tspan></text>')
    parts.append(f'<text x="{px + 190}" y="{py + 32}" font-family="{FONT}" font-size="13" fill="#fff" opacity="0.6">Workspace 1 · 7 slides</text>')
    parts.append(f'<rect x="{px + 18}" y="{py + 50}" width="{pw - 36}" height="56" rx="28" fill="#fff" opacity="0.08"/>')
    tx = px + 70
    for i in range(7):
        parts.append(f'<rect x="{tx}" y="{py + 60}" width="54" height="36" rx="7" fill="{APPS[i % len(APPS)]}" opacity="{0.55 if i == 5 else 0.22}"/>')
        tx += 60
    tx = px + 22
    for i, title in enumerate(["Mail", "Claude Code", "Notes", "Documents"]):
        parts.append(f'<rect x="{tx}" y="{py + 124}" width="120" height="74" rx="10" fill="#fff" opacity="{0.16 if i == 2 else 0.07}"/>')
        parts.append(f'<rect x="{tx + 48}" y="{py + 146}" width="24" height="24" rx="6" fill="{APPS[(i + 2) % len(APPS)]}"/>')
        parts.append(f'<text x="{tx}" y="{py + 220}" font-family="{FONT}" font-size="12" fill="#fff" opacity="0.85">{i + 3}  {title}</text>')
        tx += 132
    parts.append(f'<text x="{W / 2}" y="{H - 14}" text-anchor="middle" font-family="{FONT}" font-size="15" fill="{MUTED}">Prefer a clean screen? Turn the slider bar off and click the menu bar icon: your slides hang right under it.</text>')
    return card(W, H, "".join(parts), "The slider panel that hangs under the menu bar icon")


def palette():
    W, H = 1280, 520
    px, py, pw, ph = 330, 40, 620, 420
    rows = [("rectangle.split", "Open pair Safari + Notes", "App pair", True),
            ("window", "Safari — Monorail on GitHub", "Go to window · Safari", False),
            ("park", "Park Chat", "Minimise its windows to the Dock", False),
            ("camera", "Restore snapshot Friday", "Session snapshot", False),
            ("person", "Switch to profile Home", "Profile", False),
            ("bolt", "Focus mode on / off", "⌃⌥B", False)]
    parts = [f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="16" fill="#fff" filter="url(#shadow)"/>',
             f'<text x="{px + 24}" y="{py + 42}" font-family="{FONT}" font-size="21" fill="{INK}">pair saf<tspan fill="{PINK}">|<animate attributeName="opacity" values="1;0;1" dur="1s" repeatCount="indefinite"/></tspan></text>',
             f'<rect x="{px}" y="{py + 62}" width="{pw}" height="1" fill="#000" opacity="0.08"/>']
    y = py + 76
    for icon, title, sub, sel in rows:
        if sel:
            parts.append(f'<rect x="{px + 8}" y="{y}" width="{pw - 16}" height="50" rx="8" fill="{PINK}"/>')
        color = "#fff" if sel else INK
        parts.append(f'<rect x="{px + 22}" y="{y + 15}" width="20" height="20" rx="5" fill="{"#fff" if sel else PINK}" opacity="{0.9 if sel else 0.85}"/>')
        parts.append(f'<text x="{px + 56}" y="{y + 22}" font-family="{FONT}" font-size="15" fill="{color}">{title}</text>')
        parts.append(f'<text x="{px + 56}" y="{y + 40}" font-family="{FONT}" font-size="12" fill="{color}" opacity="0.65">{sub}</text>')
        y += 56
    parts.append(f'<text x="{W / 2}" y="{H - 30}" text-anchor="middle" font-family="{FONT}" font-size="16" font-weight="600" fill="{INK}">⌃⌥/  ·  type what you want, press return</text>')
    return card(W, H, "".join(parts), "The command palette")


def focus_mode():
    W, H = 1280, 520
    sx, sy, sw, sh = 140, 34, 1000, 440
    parts = [desktop(sx, sy, sw, sh, status="◉ 2 · 3/7"),
             f'<defs><clipPath id="focusclip"><rect x="{sx}" y="{sy + 22}" width="{sw}" height="{sh - 22}" rx="14"/></clipPath></defs>',
             '<g clip-path="url(#focusclip)">']
    parts.append(tiles_in(sx - 300, sy + 34, 420, sh - 72, [(0, 0, 1, 1)], [APPS[3]], gap=12, dim=[]))
    parts.append(tiles_in(sx + 140, sy + 34, sw - 280, sh - 72, [(0, 0, .5, 1), (.5, 0, .5, 1)], [APPS[0], APPS[1]], gap=12))
    parts.append(tiles_in(sx + sw - 128, sy + 34, 420, sh - 72, [(0, 0, 1, 1)], [APPS[4]], gap=12, dim=[]))
    parts.append(f'<rect x="{sx}" y="{sy + 22}" width="146" height="{sh - 22}" fill="#000" opacity="0.5"/>')
    parts.append(f'<rect x="{sx + sw - 134}" y="{sy + 22}" width="134" height="{sh - 22}" fill="#000" opacity="0.5"/>')
    parts.append('</g>')
    parts.append(f'<rect x="{W / 2 - 92}" y="{sy + sh - 64}" width="184" height="30" rx="15" fill="#000" opacity="0.6"/>')
    parts.append(f'<text x="{W / 2}" y="{sy + sh - 44}" text-anchor="middle" font-family="{FONT}" font-size="13" font-weight="700" fill="#fff">Focus · 24:58 left</text>')
    parts.append(f'<text x="{W / 2}" y="{H - 14}" text-anchor="middle" font-family="{FONT}" font-size="15" fill="{MUTED}">Focus mode (⌃⌥B): the slide you’re in stays bright, the rest of the strip fades away</text>')
    return card(W, H, "".join(parts), "Focus mode")


def snap_picker():
    W, H = 1280, 520
    sx, sy, sw, sh = 140, 34, 1000, 440
    parts = [desktop(sx, sy, sw, sh)]
    groups = [[(0, 0, .5, 1), (.5, 0, .5, 1)], [(0, 0, 1 / 3, 1), (1 / 3, 0, 1 / 3, 1), (2 / 3, 0, 1 / 3, 1)],
              [(0, 0, 2 / 3, 1), (2 / 3, 0, 1 / 3, 1)], [(0, 0, 1 / 3, 1), (1 / 3, 0, 2 / 3, 1)],
              [(0, 0, .5, .5), (.5, 0, .5, .5), (0, .5, .5, .5), (.5, .5, .5, .5)], [(0, 0, 1, 1)]]
    gw, gh, gap = 76, 48, 10
    total = len(groups) * gw + (len(groups) - 1) * gap + 24
    px, py = W / 2 - total / 2, sy + 30
    parts.append(f'<rect x="{px}" y="{py}" width="{total}" height="{gh + 24}" rx="14" fill="#fff" opacity="0.92" filter="url(#shadow)"/>')
    for g, frames in enumerate(groups):
        gx = px + 12 + g * (gw + gap)
        parts.append(f'<rect x="{gx}" y="{py + 12}" width="{gw}" height="{gh}" rx="7" fill="#000" opacity="0.06"/>')
        for i, (ux, uy, uw, uh) in enumerate(frames):
            hot = g == 1 and i == 0
            parts.append(f'<rect x="{gx + ux * gw + 1.5}" y="{py + 12 + uy * gh + 1.5}" width="{uw * gw - 3}" height="{uh * gh - 3}" rx="4" fill="{PINK if hot else "#000"}" opacity="{1 if hot else 0.16}"/>')
    # The window being dragged, and the pointer.
    parts.append(window(sx + 300, sy + 140, 380, 250, APPS[2]))
    parts.append(f'<path d="M{px + 112} {py + 40} l0 18 l5 -5 l4 9 l3 -1 l-4 -9 l7 0 z" fill="#fff" stroke="#000" stroke-width="1.2"/>')
    parts.append(f'<text x="{W / 2}" y="{H - 14}" text-anchor="middle" font-family="{FONT}" font-size="15" fill="{MUTED}">Drag a window towards the top of the screen and drop it on a zone</text>')
    return card(W, H, "".join(parts), "The snap layouts picker")


def themes():
    W, H = 1280, 360
    palettes = [("Vivid", ["#5B8FFF", "#B06BFF", "#FF619E", "#FF9445", "#45D18C"], ("#21175C", "#5C2180")),
                ("Ocean", ["#339EFF", "#29D1DB", "#5973FA", "#4DE6B8", "#8CBFFF"], ("#081F4D", "#0A406B")),
                ("Sunset", ["#FF8C4D", "#FF5C80", "#D959D9", "#FFC74D", "#F27359"], ("#4D1433", "#73243D")),
                ("Forest", ["#4DBF73", "#99CC4D", "#D9B359", "#40998C", "#B38C59"], ("#0D2E1F", "#1A4026")),
                ("Monochrome", ["#EBEBEB", "#C7C7C7", "#A3A3A3", "#DBDBDB", "#B3B3B3"], ("#1A1A1A", "#292929"))]
    cw, gap = 220, 22
    x0 = (W - (5 * cw + 4 * gap)) / 2
    parts = [f'<text x="{W / 2}" y="46" text-anchor="middle" font-family="{FONT}" font-size="15" font-weight="700" fill="{MUTED}" letter-spacing="2">FIVE THEMES · SETTINGS → APPEARANCE</text>']
    for n, (name, colors, (a, b)) in enumerate(palettes):
        x = x0 + n * (cw + gap)
        parts.append(f'<defs><linearGradient id="t{n}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient></defs>')
        parts.append(f'<rect x="{x}" y="70" width="{cw}" height="200" rx="16" fill="url(#t{n})" filter="url(#shadow)"/>')
        for i, c in enumerate(colors):
            parts.append(f'<rect x="{x + 16}" y="{88 + i * 32}" width="{cw - 32}" height="24" rx="7" fill="{c}" opacity="{0.28 if i else 0.4}"/>')
            parts.append(f'<circle cx="{x + 30}" cy="{100 + i * 32}" r="5" fill="{c}"/>')
            parts.append(f'<rect x="{x + 46}" y="{94 + i * 32}" width="{40 + (i * 23) % 60}" height="12" rx="6" fill="{c}" opacity="0.8"/>')
        parts.append(f'<text x="{x + cw / 2}" y="300" text-anchor="middle" font-family="{FONT}" font-size="17" font-weight="700" fill="{INK}">{name}</text>')
    return card(W, H, "".join(parts), "Colour themes")


def choice():
    W, H = 1280, 420
    parts = []
    for n, (title, sub, bar) in enumerate([("Slider bar + menu bar icon", "A bar of your slides above the Dock", True),
                                          ("Menu bar icon only", "Windows reach down to the Dock", False)]):
        x, y, w, h = 120 + n * 540, 40, 500, 290
        parts.append(desktop(x, y, w, h))
        bottom = h - 34 - (46 if bar else 0)
        parts.append(tiles_in(x + 10, y + 30, w - 20, bottom - 30, [(0, 0, .5, 1), (.5, 0, .5, 1)], [APPS[n], APPS[n + 2]], gap=8))
        if bar:
            parts.append(f'<rect x="{x + 110}" y="{y + h - 70}" width="280" height="32" rx="16" fill="#fff" opacity="0.85"/>')
            for i in range(6):
                parts.append(f'<rect x="{x + 150 + i * 38}" y="{y + h - 63}" width="32" height="18" rx="5" fill="{APPS[i]}" opacity="0.5"/>')
        else:
            parts.append(f'<rect x="{x + w - 230}" y="{y + 24}" width="200" height="70" rx="10" fill="#1E1A24" opacity="0.94"/>')
            for i in range(5):
                parts.append(f'<rect x="{x + w - 218 + i * 36}" y="{y + 44}" width="30" height="30" rx="6" fill="{APPS[i]}" opacity="0.5"/>')
        parts.append(f'<text x="{x + w / 2}" y="{y + h + 36}" text-anchor="middle" font-family="{FONT}" font-size="18" font-weight="700" fill="{INK}">{title}</text>')
        parts.append(f'<text x="{x + w / 2}" y="{y + h + 60}" text-anchor="middle" font-family="{FONT}" font-size="14" fill="{MUTED}">{sub}</text>')
    return card(W, H, "".join(parts), "Choose: slider bar and menu bar icon, or the menu bar icon only")


def insights():
    W, H = 1280, 420
    parts = [f'<rect x="200" y="36" width="880" height="330" rx="18" fill="#fff" filter="url(#shadow)"/>']
    for i, (value, label) in enumerate([("148", "slide switches today"), ("23", "windows opened"), ("9", "slides at most"), ("2", "focus sessions")]):
        x = 240 + i * 200
        parts.append(f'<text x="{x}" y="96" font-family="{FONT}" font-size="38" font-weight="800" fill="{INK}">{value}</text>')
        parts.append(f'<text x="{x}" y="120" font-family="{FONT}" font-size="13" fill="{MUTED}">{label}</text>')
    days = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]
    values = [40, 22, 120, 96, 132, 110, 148]
    for i, (d, v) in enumerate(zip(days, values)):
        h = v * 0.7
        x = 244 + i * 44
        parts.append(f'<rect x="{x}" y="{256 - h}" width="28" height="{h}" rx="5" fill="{PINK}" opacity="{1 if i == 6 else 0.45}">'
                     f'<animate attributeName="height" from="0" to="{h}" dur="1.2s" fill="freeze"/>'
                     f'<animate attributeName="y" from="256" to="{256 - h}" dur="1.2s" fill="freeze"/></rect>')
        parts.append(f'<text x="{x + 14}" y="278" text-anchor="middle" font-family="{FONT}" font-size="12" fill="{MUTED}">{d}</text>')
    parts.append(f'<text x="600" y="170" font-family="{FONT}" font-size="14" font-weight="700" fill="{INK}">Suggested app pair</text>')
    parts.append(f'<rect x="600" y="184" width="440" height="56" rx="12" fill="{PINK}" opacity="0.1"/>')
    parts.append(f'<text x="620" y="218" font-family="{FONT}" font-size="15" fill="{INK}">Xcode + Simulator · 6.5 h together</text>')
    parts.append(f'<rect x="900" y="198" width="124" height="28" rx="8" fill="{PINK}"/>')
    parts.append(f'<text x="962" y="217" text-anchor="middle" font-family="{FONT}" font-size="13" font-weight="700" fill="#fff">Save as pair</text>')
    parts.append(f'<text x="600" y="276" font-family="{FONT}" font-size="13" fill="{MUTED}">Counted on this Mac only. Nothing is sent anywhere.</text>')
    parts.append(f'<text x="240" y="336" font-family="{FONT}" font-size="14" font-weight="700" fill="{INK}">Settings → Insights</text>')
    return card(W, H, "".join(parts), "Insights: your week and suggested app pairs")


def features():
    W, H = 1280, 640
    items = [("Profiles", "Work and home, each with its own workspaces", WS[0]),
             ("Marks", "⌃⌥; then a letter jumps back to a window", WS[1]),
             ("Scratchpad", "One window drops in and hides with ⌃⌥`", WS[2]),
             ("App pairs", "Open two apps side by side in one go", WS[3]),
             ("Snapshots", "Bring a whole session back, apps and all", WS[4]),
             ("Peek", "Hold ⌥ over a slide to see it without switching", "#33CCDB"),
             ("Picture in picture", "A live window in a screen corner", WS[0]),
             ("Auto rules", "Switch profile at 9:00 or on office Wi-Fi", WS[1]),
             ("Title rules", "A window titled “Meet” floats by itself", WS[2]),
             ("Quick launch", "⌃⌥U then T opens your terminal", WS[3]),
             ("Sync", "Settings and layouts on every Mac, via iCloud", WS[4]),
             ("Shortcuts app", "monorail:// links for every action", "#33CCDB")]
    cw, ch, gap = 280, 150, 22
    x0 = (W - (4 * cw + 3 * gap)) / 2
    parts = [f'<text x="{W / 2}" y="52" text-anchor="middle" font-family="{FONT}" font-size="28" font-weight="800" fill="{INK}">And a lot more</text>']
    for n, (title, sub, color) in enumerate(items):
        x = x0 + (n % 4) * (cw + gap)
        y = 84 + (n // 4) * (ch + gap)
        parts.append(f'<rect x="{x}" y="{y}" width="{cw}" height="{ch}" rx="16" fill="#fff" filter="url(#shadow)"/>')
        parts.append(f'<rect x="{x + 20}" y="{y + 20}" width="40" height="40" rx="11" fill="{color}" opacity="0.18"/>')
        parts.append(f'<rect x="{x + 30}" y="{y + 30}" width="20" height="20" rx="5" fill="{color}"/>')
        parts.append(f'<text x="{x + 20}" y="{y + 92}" font-family="{FONT}" font-size="18" font-weight="800" fill="{INK}">{title}</text>')
        words, line, lines = sub.split(), "", []
        for word in words:
            if len(line) + len(word) > 30:
                lines.append(line)
                line = word
            else:
                line = f"{line} {word}".strip()
        lines.append(line)
        for i, text in enumerate(lines[:2]):
            parts.append(f'<text x="{x + 20}" y="{y + 116 + i * 18}" font-family="{FONT}" font-size="13" fill="{MUTED}">{text}</text>')
    return card(W, H, "".join(parts), "More features: profiles, marks, scratchpad, app pairs, snapshots and more")


os.makedirs(OUT, exist_ok=True)
for name, svg in [("banner.svg", banner()), ("how-it-works.svg", how_it_works()), ("layouts.svg", layouts()),
                  ("overview.svg", overview()), ("slider.svg", slider()), ("menubar.svg", menubar()),
                  ("palette.svg", palette()), ("focus.svg", focus_mode()), ("snap.svg", snap_picker()),
                  ("themes.svg", themes()), ("choice.svg", choice()), ("insights.svg", insights()),
                  ("features.svg", features())]:
    with open(os.path.join(OUT, name), "w") as f:
        f.write(svg)
    print("Wrote", os.path.join(OUT, name))
