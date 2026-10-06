#!/usr/bin/env python3
"""Builds design/logo-12.svg: the Claude logo as 12 overlapping bars.

Each bar keeps its arm's real outer shape (from radius R_JOIN outward). Inside that, the arm's two side
edges are extended in straight lines (least-squares fit of the visible edges) toward the logo's center and
finish in a semicircular cap placed where the bar's centerline passes closest to the center. The between-arm hub detail is dropped.
Standard library only.  Run from the project root:  python3 tools/build-bars.py
"""
import math, re, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from logo_geom import *

SRC, OUT = "Resources/claude.svg", "design/logo-12.svg"
R_JOIN = 6.5        # arms are clean, parallel-ish bars beyond this radius
TIP_MARGIN = 1.6    # ignore the blunt tip when fitting the edges
EXTEND = {11: float(os.environ.get("EXTEND11", "0.15"))}   # push a bar's rounded end further past the center (units)

def section(poly, P, n):
    """Intervals (t0, t1) along P + t*n that lie inside the polygon."""
    ts = []
    for i in range(len(poly)):
        a, b = poly[i-1], poly[i]
        ex, ey = b[0]-a[0], b[1]-a[1]
        den = n[0]*ey - n[1]*ex
        if abs(den) < 1e-12: continue
        t = ((a[0]-P[0])*ey - (a[1]-P[1])*ex) / den
        u = ((a[0]-P[0])*n[1] - (a[1]-P[1])*n[0]) / den
        if 0 <= u < 1: ts.append(t)
    ts.sort()
    return [(ts[k], ts[k+1]) for k in range(0, len(ts) - 1, 2)]

def linfit(xs, ys):
    n = len(xs); mx, my = sum(xs)/n, sum(ys)/n
    m = sum((x-mx)*(y-my) for x, y in zip(xs, ys)) / sum((x-mx)**2 for x in xs)
    return my - m*mx, m          # intercept, slope

def dp_open(pts, tol):
    if len(pts) < 3: return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    L = math.hypot(x2-x1, y2-y1) or 1e-12
    idx, dmax = 0, 0
    for k in range(1, len(pts)-1):
        dd = abs((x2-x1)*(y1-pts[k][1]) - (x1-pts[k][0])*(y2-y1)) / L
        if dd > dmax: idx, dmax = k, dd
    if dmax > tol: return dp_open(pts[:idx+1], tol)[:-1] + dp_open(pts[idx:], tol)
    return [pts[0], pts[-1]]

d = re.search(r'\sd="([^"]*)"', open(SRC).read()).group(1)
logo = parse_path(d)
C = (12.0, 12.0)
spans = [(GAPS[-1], GAPS[0] + 360)] + [(GAPS[i], GAPS[i+1]) for i in range(len(GAPS) - 1)]
fmt = lambda v: f"{v:.3f}".rstrip("0").rstrip(".") or "0"
paths, report, polys = [], [], []

for n, (a1, a2) in enumerate(spans, 1):
    piece = clip_wedge(logo, C, a1 % 360, a2 % 360)
    far = max(math.hypot(x-C[0], y-C[1]) for x, y in piece)
    tip = [(x, y) for x, y in piece if math.hypot(x-C[0], y-C[1]) > 0.8*far]
    th = math.atan2(sum(x-C[0] for x, _ in tip)/len(tip), -sum(y-C[1] for _, y in tip)/len(tip))
    ax = (math.sin(th), -math.cos(th)); nm = (-ax[1], ax[0])
    loc = lambda p: ((p[0]-C[0])*ax[0] + (p[1]-C[1])*ax[1], (p[0]-C[0])*nm[0] + (p[1]-C[1])*nm[1])
    glob = lambda x, s: (C[0] + ax[0]*x + nm[0]*s, C[1] + ax[1]*x + nm[1]*s)

    # 1. measure the arm's two side edges along its length and fit a straight line to each
    rs, sL, sR = [], [], []
    r = R_JOIN
    while r <= far - TIP_MARGIN:
        P = glob(r, 0)
        ivs = section(logo, P, nm)
        ivs = [iv for iv in ivs if iv[1] >= -3 and iv[0] <= 3]
        if ivs:
            iv = min(ivs, key=lambda v: 0 if v[0] <= 0 <= v[1] else min(abs(v[0]), abs(v[1])))
            rs.append(r); sL.append(iv[0]); sR.append(iv[1])
        r += 0.25
    aL, mL = linfit(rs, sL); aR, mR = linfit(rs, sR)

    # 2. the arm's real outer part: everything at or beyond R_JOIN
    def inside(p): return loc(p)[0] >= R_JOIN
    def inter(p, q):
        fp, fq = loc(p)[0] - R_JOIN, loc(q)[0] - R_JOIN; t = fp / (fp - fq)
        return (p[0] + t*(q[0]-p[0]), p[1] + t*(q[1]-p[1]))
    outer = clip(piece, inside, inter)
    cut = [i for i, p in enumerate(outer) if abs(loc(p)[0] - R_JOIN) < 1e-6]
    assert len(cut) == 2, f"ray {n}: expected one clean cut, got {len(cut)} points"
    i0 = cut[0] if (cut[0] + 1) % len(outer) == cut[1] else cut[1]
    A, B = outer[i0], outer[(i0 + 1) % len(outer)]          # cut edge runs A -> B
    walk = [outer[(i0 + 1 + k) % len(outer)] for k in range(len(outer))]    # B ... A (the long way round)
    walk = dp_open(walk, SIMPLIFY_TOL)

    # 3. straight extension of each side toward the center, closed by a semicircular cap
    sA, sB = loc(A)[1], loc(B)[1]
    mA, mB = (mL, mR) if sA < sB else (mR, mL)
    wj = abs(sB - sA); dw = (mB - mA) * (1 if sB > sA else -1)
    # Stop the bar where its own centerline passes closest to the logo's center (arms aren't perfectly radial).
    aM, mM = (aL + aR) / 2, (mL + mR) / 2
    x_tip = -aM * mM / (1 + mM*mM)
    miss = abs(aM + mM*x_tip) / math.sqrt(1 + mM*mM)          # how far the centerline passes from the center
    x_tip -= EXTEND.get(n, 0.0)
    x_end = (x_tip + 0.5*(wj - dw*R_JOIN)) / (1 - 0.5*dw)     # cap center such that the cap tip sits at x_tip
    rho = 0.5 * (wj + dw*(x_end - R_JOIN))
    A_end = glob(x_end, sA + mA*(x_end - R_JOIN)); B_end = glob(x_end, sB + mB*(x_end - R_JOIN))
    M = ((A_end[0]+B_end[0])/2, (A_end[1]+B_end[1])/2)
    T = glob(x_end - rho, (loc(A_end)[1] + loc(B_end)[1]) / 2)
    cross = (A_end[0]-M[0])*(T[1]-M[1]) - (A_end[1]-M[1])*(T[0]-M[0])
    sweep = 1 if cross > 0 else 0
    d_out = ("M" + " L".join(f"{fmt(x)} {fmt(y)}" for x, y in walk)
             + f" L{fmt(A_end[0])} {fmt(A_end[1])} A{fmt(rho)} {fmt(rho)} 0 0 {sweep} {fmt(B_end[0])} {fmt(B_end[1])} Z")
    paths.append(f'  <path id="ray-{n:02d}" d="{d_out}"/>')
    # same outline as plain points for the app (cap arc sampled), so Swift needs no SVG parser
    th0 = math.atan2(A_end[1]-M[1], A_end[0]-M[0])
    def arc_pt(sign, t): a = th0 + sign*math.pi*t; return (M[0] + rho*math.cos(a), M[1] + rho*math.sin(a))
    sign = min((1, -1), key=lambda sg: math.dist(arc_pt(sg, 0.5), T))
    cap = [arc_pt(sign, k/16) for k in range(1, 16)]
    polys.append(walk + [A_end] + cap + [B_end])
    report.append(f"ray-{n:02d}  width {wj:4.2f}  taper {dw:+.3f}  cap r {rho:4.2f}  centerline misses center by {miss:4.2f}")

print("\n".join(report))
svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">\n'
       '  <title>Claude logo, 12 bars</title>\n'
       '  <!-- ray-01 is the top bar; ray-02..ray-12 go clockwise. Bars overlap at the center; each ends in a round cap. -->\n'
       + "\n".join(paths) + "\n</svg>\n")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w").write(svg)
print("wrote", OUT)

# App/LogoRays.swift: the 12 outlines, 24x24 coordinates, y down (SVG), ray 0 = top, clockwise
swift = ["// Generated by tools/build-bars.py. Do not edit.", "// The Claude logo as 12 ray outlines in a 24x24 box (y down); index 0 is the top ray, then clockwise.",
         "enum LogoRays {", "    static let rays: [[(Double, Double)]] = ["]
for poly in polys:
    swift.append("        [" + ", ".join(f"({x:.3f}, {y:.3f})" for x, y in poly) + "],")
swift += ["    ]", "}", ""]
open("App/LogoRays.swift", "w").write("\n".join(swift))
print("wrote App/LogoRays.swift")
