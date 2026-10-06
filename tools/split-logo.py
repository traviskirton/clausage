#!/usr/bin/env python3
"""Wedge-cut experiment: splits Resources/claude.svg into 12 wedge pieces (superseded by build-bars.py)."""
import math, re, sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
from logo_geom import *

SRC, OUT = "Resources/claude.svg", "design/logo-12-wedges.svg"
d = re.search(r'\sd="([^"]*)"', open(SRC).read()).group(1)
logo = parse_path(d)
xs, ys = [q[0] for q in logo], [q[1] for q in logo]
center = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
total = abs(area(logo))
print(f"center {center[0]:.3f},{center[1]:.3f}  original area {total:.4f}")

# rays in clockwise order starting from the top ray (the one that spans 0 degrees)
spans = [(GAPS[-1], GAPS[0] + 360)] + [(GAPS[i], GAPS[i+1]) for i in range(len(GAPS) - 1)]
pieces, summed = [], 0.0
for n, (a1, a2) in enumerate(spans, 1):
    piece = clip_wedge(logo, center, a1 % 360, a2 % 360)
    a = abs(area(piece)); summed += a
    piece = simplify(piece, SIMPLIFY_TOL)
    pieces.append((n, a1 % 360, a2 % 360, piece))
    print(f"ray-{n:02d}  {a1 % 360:3d}°→{a2 % 360:3d}°  area {a:.4f}  points {len(piece)}")
print(f"sum of pieces {summed:.4f}  vs original {total:.4f}  diff {abs(summed - total):.6f}")
assert abs(summed - total) < 0.01, "pieces do not add back up to the original logo"

fmt = lambda v: f"{v:.3f}".rstrip("0").rstrip(".")
paths = []
for n, a1, a2, piece in pieces:
    dd = "M" + " L".join(f"{fmt(x)} {fmt(y)}" for x, y in piece) + " Z"
    paths.append(f'  <path id="ray-{n:02d}" data-wedge="{a1}-{a2}" d="{dd}"/>')
svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">\n'
       '  <title>Claude logo, 12 rays</title>\n'
       '  <!-- ray-01 is the top ray; ray-02..ray-12 go clockwise. Together they tile the original logo exactly. -->\n'
       + "\n".join(paths) + "\n</svg>\n")
open(OUT, "w").write(svg)
print("wrote", OUT)
