#!/usr/bin/env python3
"""Shared geometry helpers for the logo tools (standard library only)."""
import math, re

GAPS = [26, 66, 94, 118, 138, 165, 194, 221, 252, 285, 319, 358]   # the 12 gaps between rays
FLATTEN_STEPS, SIMPLIFY_TOL = 16, 0.003

def parse_path(d):
    """Flattens the path (commands m l h v c L Z) to one polygon."""
    toks = re.findall(r"[A-Za-z]|-?\d*\.?\d+(?:e-?\d+)?", d)
    pts, i, cmd, x, y = [], 0, None, 0.0, 0.0
    num = lambda: float(toks[next_i()])
    def next_i():
        nonlocal i; i += 1; return i - 1
    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]): cmd = toks[next_i()]
        if cmd in "mM":
            dx, dy = num(), num(); x, y = (x + dx, y + dy) if cmd == "m" else (dx, dy); pts.append((x, y))
            cmd = "l" if cmd == "m" else "L"
        elif cmd in "lL":
            dx, dy = num(), num(); x, y = (x + dx, y + dy) if cmd == "l" else (dx, dy); pts.append((x, y))
        elif cmd == "h": x += num(); pts.append((x, y))
        elif cmd == "v": y += num(); pts.append((x, y))
        elif cmd == "c":
            c1 = (x + num(), y + num()); c2 = (x + num(), y + num()); e = (x + num(), y + num())
            p0 = (x, y)
            for k in range(1, FLATTEN_STEPS + 1):
                t = k / FLATTEN_STEPS; u = 1 - t
                pts.append(tuple(u**3*p0[j] + 3*u*u*t*c1[j] + 3*u*t*t*c2[j] + t**3*e[j] for j in (0, 1)))
            x, y = e
        elif cmd in "zZ": pass
        else: raise ValueError(f"unsupported command {cmd}")
    return pts

def area(p):
    return 0.5 * sum(p[i][0]*p[(i+1) % len(p)][1] - p[(i+1) % len(p)][0]*p[i][1] for i in range(len(p)))

def clip(poly, inside, intersect):
    """One Sutherland–Hodgman pass against a half-plane."""
    out = []
    for i, cur in enumerate(poly):
        prev = poly[i - 1]
        a, b = inside(prev), inside(cur)
        if a != b: out.append(intersect(prev, cur))
        if b: out.append(cur)
    return out

def clip_wedge(poly, c, a1, a2):
    u = lambda deg: (math.sin(math.radians(deg)), -math.cos(math.radians(deg)))
    u1, u2 = u(a1), u(a2)
    cross = lambda a, b: a[0]*b[1] - a[1]*b[0]
    def half(side):   # side 0: left of u1 ray; side 1: right of u2 ray
        f = (lambda p: cross(u1, (p[0]-c[0], p[1]-c[1]))) if side == 0 else (lambda p: cross((p[0]-c[0], p[1]-c[1]), u2))
        def inter(p, q):
            fp, fq = f(p), f(q); t = fp / (fp - fq)
            return (p[0] + t*(q[0]-p[0]), p[1] + t*(q[1]-p[1]))
        return (lambda p: f(p) >= 0), inter
    for side in (0, 1):
        ins, inter = half(side)
        poly = clip(poly, ins, inter)
        if not poly: return []
    return poly

def simplify(p, tol):
    """Douglas–Peucker on a closed ring (split at the two farthest-apart points)."""
    def dp(pts):
        if len(pts) < 3: return pts
        (x1, y1), (x2, y2) = pts[0], pts[-1]
        L = math.hypot(x2-x1, y2-y1) or 1e-12
        idx, dmax = 0, 0
        for k in range(1, len(pts)-1):
            d = abs((x2-x1)*(y1-pts[k][1]) - (x1-pts[k][0])*(y2-y1)) / L
            if d > dmax: idx, dmax = k, d
        if dmax > tol: return dp(pts[:idx+1])[:-1] + dp(pts[idx:])
        return [pts[0], pts[-1]]
    h = len(p) // 2
    return dp(p[:h+1])[:-1] + dp(p[h:] + [p[0]])[:-1]

