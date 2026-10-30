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


os.makedirs(OUT, exist_ok=True)
for name, svg in [("banner.svg", banner()), ("how-it-works.svg", how_it_works()), ("layouts.svg", layouts())]:
    with open(os.path.join(OUT, name), "w") as f:
        f.write(svg)
    print("Wrote", os.path.join(OUT, name))
