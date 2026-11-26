#!/usr/bin/env python3
"""Write the app icon, H1, as an Icon Composer file: icon.json and three SVG layers (icon and name design §5).

Usage: python3 -I scripts/make-icon.py app/Resources/AppIcon.icon
tests/icon_test.sh checks that the committed icon is what this writes.
"""
import json
import os
import sys

out = sys.argv[1]
K, O = 40, 512 - 9 * 40   # the menu bar's 18 pt glyph (MenuIcon+Image.swift), 40 px a point, centred on the 1024 canvas
W = 1.6 * K               # a bar's width
# (x, y, height) in points: the glyph's 10 bars, then the heart in the middle column's gap
BARS = [(0.9, 7.8, 2.4), (3.3, 5.3, 7.4), (5.8, 3, 5.6), (5.8, 9.4, 5.6), (8.2, 0.5, 5.6),
        (8.2, 11.9, 5.6), (10.6, 3, 5.6), (10.6, 9.4, 5.6), (13.1, 5.3, 7.4), (15.5, 7.8, 2.4), (8.2, 6.9, 4.2)]
BLACK, RED = (22, 22, 22), (212, 42, 47)
LINEN = ("#f7f2e8", "#e6dcc8")
SHADOW = 18               # how far a bar's shadow falls, down; a third of that to the right

def colour(dx, dy):
    """Black on the rhombus through the bars' ends (d = 1) and in the heart, red between."""
    d = (abs(dx) + abs(dy)) / 8.5
    mix = lambda a, b, t: tuple(round(a[i] + (b[i] - a[i]) * max(0, min(1, t))) for i in range(3))
    if d <= 0.3: return BLACK
    if d < 0.42: return mix(BLACK, RED, (d - 0.3) / 0.12)
    if d < 0.7: return RED
    return mix(RED, BLACK, (d - 0.7) / 0.27)

ROD = ('<linearGradient id="cyl" x1="0" y1="0" x2="1" y2="0">'   # a round rod lit from the top left
       '<stop offset="0" stop-color="#000" stop-opacity=".30"/><stop offset=".22" stop-color="#fff" stop-opacity=".38"/>'
       '<stop offset=".42" stop-color="#fff" stop-opacity="0"/><stop offset=".72" stop-color="#000" stop-opacity="0"/>'
       '<stop offset="1" stop-color="#000" stop-opacity=".50"/></linearGradient>'
       '<linearGradient id="cap" x1="0" y1="0" x2="0" y2="1">'
       '<stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".12" stop-color="#fff" stop-opacity="0"/>'
       '<stop offset=".88" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".30"/></linearGradient>')

def svg(defs, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs>{defs}</defs>{body}</svg>'

def rect(x, y, h, fill, extra=""):
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{W:.1f}" height="{h:.1f}" rx="{0.4*W:.1f}" fill="{fill}"{extra}/>'

def gradient(n, x, y, h):
    """A bar's colour from top to bottom, sampled in 24 steps."""
    stops = "".join(f'<stop offset="{t:.3f}" stop-color="rgb{colour(x + 0.8 - 9, y + h * t - 9)}"/>' for t in [i / 24 for i in range(25)])
    return f'<linearGradient id="g{n}" gradientUnits="userSpaceOnUse" x1="0" y1="{O+y*K:.1f}" x2="0" y2="{O+(y+h)*K:.1f}">{stops}</linearGradient>'

def bars_and_shadow():
    defs, shadow, bars = [ROD], [], []
    for n, (x, y, h) in sorted(enumerate(BARS), key=lambda b: b[1][1]):
        X, Y, H = O + x * K, O + y * K, h * K
        defs.append(gradient(n, x, y, h))
        for t in range(1, 11):   # a soft shadow from ten faint copies
            shadow.append(rect(X + 0.35 * SHADOW * t / 10, Y + SHADOW * t / 10, H, "#000", ' fill-opacity=".045"'))
        bars.append(rect(X, Y, H, f"url(#g{n})") + rect(X, Y, H, "url(#cyl)") + rect(X, Y, H, "url(#cap)"))
    return svg("".join(defs), "".join(bars)), svg("", "".join(shadow))

def weave():
    """B2's linen weave, drawn on its 824 body and scaled to the canvas."""
    x0, x1 = 100, 924
    lines = "".join(f"M{v} {x0}V{x1}M{x0} {v}H{x1}" for v in range(x0 + 4, x1, 8))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><g transform="scale({1024 / 824}) translate(-100 -100)">'
            f'<path d="{lines}" stroke="#d6c9ae" stroke-width="1" opacity=".55"/></g></svg>')

def srgb(hex):
    return "srgb:" + ",".join(f"{int(hex[i:i+2], 16) / 255:.5f}" for i in (1, 3, 5)) + ",1.00000"

bars, shadow = bars_and_shadow()
os.makedirs(f"{out}/Assets", exist_ok=True)
for name, content in (("bars", bars), ("shadow", shadow), ("weave", weave())):
    with open(f"{out}/Assets/{name}.svg", "w") as f:
        f.write(content)
icon = {
    "fill": {"linear-gradient": [srgb(LINEN[0]), srgb(LINEN[1])]},
    "groups": [   # the first is on top
        {"layers": [{"image-name": "bars.svg", "name": "bars"}], "shadow": {"kind": "neutral", "opacity": 0.5},
         "translucency": {"enabled": False, "value": 0.5}},
        {"layers": [{"image-name": "shadow.svg", "name": "shadow", "glass": False}]},
        {"layers": [{"image-name": "weave.svg", "name": "weave", "glass": False}]},
    ],
    "supported-platforms": {"squares": ["macOS"]},
}
with open(f"{out}/icon.json", "w") as f:
    json.dump(icon, f, indent=2)
