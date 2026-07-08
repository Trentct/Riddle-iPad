#!/usr/bin/env python3
"""
Generate Riddle's App Store icon (1024x1024) procedurally.

Design brief: a single, elegant, dark-ink calligraphic brushstroke on the
app's cream paper ground. No text/letters -- just a hand-made, warm,
literary ink mark: thick-to-thin taper, a small pool where the "pen" first
touched down, and a fine tapered tail with a couple of flicked-off droplets.

Usage:
    python3 tools/make-icon.py

Outputs:
    Riddle/Assets.xcassets/AppIcon.appiconset/Icon-1024.png  (opaque, RGB, 1024x1024)
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SIZE = 1024
SUPERSAMPLE = 4  # render at 4096 then downsample for smooth anti-aliasing
CANVAS = SIZE * SUPERSAMPLE

PAPER = (242, 237, 225)       # #F2EDE1 cream paper
PAPER_SHADOW = (223, 216, 199)  # slightly deeper cream for vignette
INK = (26, 26, 46)            # #1A1A2E dark ink

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "Riddle", "Assets.xcassets", "AppIcon.appiconset")
OUT_PATH = os.path.join(OUT_DIR, "Icon-1024.png")


# ---------------------------------------------------------------------------
# Catmull-Rom spline helpers
# ---------------------------------------------------------------------------

def catmull_rom(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    x = 0.5 * (
        (2 * p1[0])
        + (-p0[0] + p2[0]) * t
        + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
        + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
    )
    y = 0.5 * (
        (2 * p1[1])
        + (-p0[1] + p2[1]) * t
        + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
        + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
    )
    return (x, y)


def sample_spline(points, samples_per_seg=60):
    """Sample a smooth Catmull-Rom curve through `points` (needs >= 4 pts,
    duplicates the first/last point as phantom control points)."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        n = samples_per_seg
        for s in range(n):
            t = s / n
            out.append(catmull_rom(p0, p1, p2, p3, t))
    out.append(points[-1])
    return out


def ease_out_cubic(x):
    return 1 - (1 - x) ** 3


def ease_in_out(x):
    return 0.5 - 0.5 * math.cos(math.pi * x)


# ---------------------------------------------------------------------------
# Stroke construction
# ---------------------------------------------------------------------------

def build_stroke_polygon(centerline_pts, width_fn):
    """Given sampled centerline points and a width(t) function, build the
    left/right ribbon boundary and return a polygon point list."""
    n = len(centerline_pts)
    left, right = [], []
    for i, (x, y) in enumerate(centerline_pts):
        t = i / (n - 1)
        # tangent via central difference
        i0 = max(0, i - 1)
        i1 = min(n - 1, i + 1)
        dx = centerline_pts[i1][0] - centerline_pts[i0][0]
        dy = centerline_pts[i1][1] - centerline_pts[i0][1]
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length  # normal
        w = width_fn(t) / 2.0
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def draw_round_cap(draw, center, radius, fill):
    x, y = center
    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=fill)


# ---------------------------------------------------------------------------
# Main render
# ---------------------------------------------------------------------------

def render():
    img = Image.new("RGB", (CANVAS, CANVAS), PAPER)

    # --- subtle radial vignette on the paper ground -------------------------
    vign = Image.new("L", (CANVAS, CANVAS), 0)
    vd = ImageDraw.Draw(vign)
    cx, cy = CANVAS / 2, CANVAS / 2
    max_r = CANVAS * 0.75
    steps = 60
    for i in range(steps, 0, -1):
        frac = i / steps
        r = max_r * frac
        alpha = int(60 * (frac ** 2))  # darkens softly toward the edges
        vd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=alpha)
    vign = vign.filter(ImageFilter.GaussianBlur(CANVAS * 0.03))
    shadow_layer = Image.new("RGB", (CANVAS, CANVAS), PAPER_SHADOW)
    img = Image.composite(shadow_layer, img, vign)

    # --- faint paper noise ---------------------------------------------------
    import random
    random.seed(7)
    noise = Image.new("L", (CANVAS // 4, CANVAS // 4), 0)
    npx = noise.load()
    for yy in range(noise.height):
        for xx in range(noise.width):
            npx[xx, yy] = random.randint(0, 10)
    noise = noise.resize((CANVAS, CANVAS), Image.BILINEAR)
    noise_rgb = Image.merge("RGB", (noise, noise, noise))
    img = Image.blend(img, Image.blend(img, noise_rgb, 0.5), 0.12)

    # The ink mark is rasterized onto its own mask layer first (rather than
    # straight onto the paper) so we can run a morphological closing pass
    # afterwards -- offset ribbons around a curving centerline can pinch into
    # tiny self-intersection notches at tight turns, and a small dilate+erode
    # irons those out without needing to solve the geometry analytically.
    ink_mask = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(ink_mask)
    INK_MASK_FILL = 255

    def C(x, y):
        return (x * SUPERSAMPLE, y * SUPERSAMPLE)

    # --- the ink mark: a single calligraphic flourish, slightly off-center --
    # Control points in 1024-space (y down): one confident arc -- a big
    # comma-like swoosh, thick round head easing down and curling into a
    # fine tail. Only one gentle inflection near the tip (like a real
    # calligraphic comma), not a wiggly S, so it reads as one deliberate
    # stroke rather than a scribble.
    control_pts = [
        C(560, 250),
        C(640, 302),
        C(648, 440),
        C(596, 572),
        C(506, 674),
        C(420, 746),
        C(360, 798),
    ]
    centerline = sample_spline(control_pts, samples_per_seg=80)
    n = len(centerline)

    START_W = 132 * SUPERSAMPLE
    END_W = 9 * SUPERSAMPLE

    def width_fn(t):
        # A single monotonic taper from a thick round brush-dab (the ink
        # "pool" where the pen touches down) to a fine tip. Held near full
        # width briefly before easing into a long natural taper, so the
        # thick end reads as a deliberate dab rather than a mechanical cone.
        if t < 0.025:
            return START_W
        tt = (t - 0.025) / 0.975
        taper = (1 - tt) ** 1.5
        return END_W + (START_W - END_W) * taper

    poly = build_stroke_polygon(centerline, width_fn)
    draw.polygon(poly, fill=INK_MASK_FILL)

    # round caps at both ends so the brush touch-down and fine tip look like
    # natural pen strokes rather than flat-cut polygon edges
    start_r = width_fn(0.0) / 2.0
    draw_round_cap(draw, centerline[0], start_r, INK_MASK_FILL)
    end_r = width_fn(1.0) / 2.0
    draw_round_cap(draw, centerline[-1], end_r, INK_MASK_FILL)

    # two tiny flicked-off ink droplets trailing past the fine tip, following
    # the tail's exit direction, shrinking as they go -- a natural pen flourish
    ex0, ey0 = centerline[-8]
    ex1, ey1 = centerline[-1]
    tail_ang = math.atan2(ey1 - ey0, ex1 - ex0)
    tip = centerline[-1]
    gap = 24 * SUPERSAMPLE
    r1 = 8 * SUPERSAMPLE
    r2 = 4.5 * SUPERSAMPLE
    d1 = (tip[0] + math.cos(tail_ang) * gap, tip[1] + math.sin(tail_ang) * gap)
    d2 = (tip[0] + math.cos(tail_ang) * gap * 2.2, tip[1] + math.sin(tail_ang) * gap * 2.2)
    draw_round_cap(draw, d1, r1, INK_MASK_FILL)
    draw_round_cap(draw, d2, r2, INK_MASK_FILL)

    # --- morphological closing (dilate then erode) --------------------------
    # irons out the small self-intersection notches that a constant-offset
    # ribbon can produce at tight turns, without softening the overall taper.
    close_radius = 24  # in supersampled px (~6px at final 1024 size)
    ink_mask = ink_mask.filter(ImageFilter.MaxFilter(close_radius * 2 + 1))
    ink_mask = ink_mask.filter(ImageFilter.MinFilter(close_radius * 2 + 1))

    # slight blur + threshold to keep the edge crisp but smoothly anti-aliased
    ink_mask = ink_mask.filter(ImageFilter.GaussianBlur(SUPERSAMPLE * 0.6))

    ink_layer = Image.new("RGB", (CANVAS, CANVAS), INK)
    img = Image.composite(ink_layer, img, ink_mask)

    # --- downsample for clean anti-aliasing ----------------------------------
    img = img.resize((SIZE, SIZE), Image.LANCZOS)

    # ensure fully opaque RGB, no alpha
    img = img.convert("RGB")

    os.makedirs(OUT_DIR, exist_ok=True)
    img.save(OUT_PATH, "PNG")
    print(f"wrote {OUT_PATH} ({img.size[0]}x{img.size[1]}, mode={img.mode})")


if __name__ == "__main__":
    render()
