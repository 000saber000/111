#!/usr/bin/env python3
"""Generate the 小农场 (Little Farm) app icon assets.

Everything here is drawn from code with Pillow -- there are no external image
inputs.  Every shape is rendered at ``SUPERSAMPLE``x and then downscaled with
LANCZOS, which gives the clean antialiased edges we want for a flat-design icon.

Outputs (all written on every run):
    assets/icon/icon.png                        1024x1024  RGB  (Godot project icon)
    assets/icon/icon_192.png                     192x192   RGB  (Android launcher)
    assets/icon/adaptive_foreground_432.png      432x432   RGBA (transparent)
    assets/icon/adaptive_background_432.png      432x432   RGB  (full bleed sky+field)

The art direction mirrors the low-poly farm game: a bright sky, a green field,
a chunky isometric soil plot with two sprouts and one big gold coin.

Usage:
    python tools/icon/generate_icon.py
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

# --------------------------------------------------------------------------
# Global configuration
# --------------------------------------------------------------------------

SUPERSAMPLE = 4
ICON_SIZE = 1024
SMALL_ICON_SIZE = 192
ADAPTIVE_SIZE = 432

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "assets", "icon")

# Palette -------------------------------------------------------------------
SKY_TOP = (104, 186, 224)      # deeper blue at the very top
SKY_MID = (135, 204, 235)      # #87CCEB -- the game's sky colour
SKY_PALE = (176, 224, 245)     # hazy band just above the horizon
FIELD_LIT = (122, 176, 88)     # sunlit far grass, right under the horizon
FIELD_MID = (92, 140, 71)      # #5C8C47 -- the game's grass colour
FIELD_DEEP = (64, 104, 52)     # foreground grass
SUN_COLOR = (255, 242, 200)    # pale sun disc

SOIL_TOP = (118, 82, 55)       # #735036 -- plot top face
SOIL_LEFT = (93, 64, 42)       # left front face (catching a little light)
SOIL_RIGHT = (72, 49, 33)      # right front face (in shade)

CROP_DARK = (60, 124, 52)      # stem
CROP_MID = (76, 158, 64)       # #4C9E40 -- back leaf
CROP_LIT = (107, 190, 88)      # front leaf highlight

COIN_RIM = (198, 143, 22)      # dark gold outer rim
COIN_BODY = (242, 181, 46)     # #F2B52E -- coin body
COIN_LIT = (255, 206, 98)      # lighter inner face

FRAME_COLOR = (74, 51, 34)     # dark soil frame around the rounded tile

# Rounded tile geometry (design pixels at ICON_SIZE = 1024)
FRAME_MARGIN = 48
FRAME_RADIUS = 206
HORIZON_FRAC = 0.55

# Subject geometry in canonical units.  The plot's top face is a diamond of
# half-width 520 and half-height 250; everything else is positioned relative
# to the plot origin (the centre of the top face).
PLOT_HW = 520.0
PLOT_HH = 250.0
PLOT_D = 165.0
CROPS = (
    (-345.0, 50.0, 1.05),
    (-105.0, 155.0, 1.25),
)
SPROUT = (20.0, 150.0, 190.0, 104.0)  # stem half-width, stem height, leaf len, leaf width
COIN = (272.0, -72.0, 192.0)
SUN = (0.275, 0.235, 0.060)  # centre x/y as a fraction of the tile, radius fraction


# --------------------------------------------------------------------------
# Small colour / drawing helpers
# --------------------------------------------------------------------------


def _clamp01(t: float) -> float:
    return 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)


def mix(c0, c1, t: float):
    """Linear blend between two RGB tuples."""
    t = _clamp01(t)
    return (
        int(round(c0[0] + (c1[0] - c0[0]) * t)),
        int(round(c0[1] + (c1[1] - c0[1]) * t)),
        int(round(c0[2] + (c1[2] - c0[2]) * t)),
    )


def mix3(c0, c1, c2, t: float):
    """Three-stop gradient (0 -> c0, 0.5 -> c1, 1 -> c2)."""
    t = _clamp01(t)
    if t < 0.5:
        return mix(c0, c1, t * 2.0)
    return mix(c1, c2, (t - 0.5) * 2.0)


def paint_background(
    img: Image.Image,
    horizon_frac: float = HORIZON_FRAC,
    sun=None,
) -> None:
    """Paint a vertical sky gradient + a green field with a crisp horizon.

    ``sun`` is an optional ``(x_frac, y_frac, r_frac)`` tuple for a small pale
    sun disc in the sky (fractions of the image size).
    """
    w, h = img.size
    draw = ImageDraw.Draw(img)
    hy = int(round(h * horizon_frac))

    for y in range(hy):
        t = y / float(max(1, hy - 1))
        draw.line([(0, y), (w, y)], fill=mix3(SKY_TOP, SKY_MID, SKY_PALE, t))

    if sun is not None:
        sx, sy, sr = sun[0] * w, sun[1] * h, sun[2] * h
        draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=SUN_COLOR)

    # Thin sunlit band of far-away grass: this is the "horizon line".
    band = max(1, int(round(h * 0.028)))
    draw.rectangle([0, hy, w, hy + band], fill=FIELD_LIT)

    fy = hy + band + 1
    for y in range(fy, h):
        t = (y - fy) / float(max(1, h - fy - 1))
        draw.line([(0, y), (w, y)], fill=mix3(FIELD_LIT, FIELD_MID, FIELD_DEEP, 0.04 + 0.96 * t))


def rounded_mask(size_px: int, margin: int, radius: int) -> Image.Image:
    """Alpha mask for the rounded-square icon plate."""
    mask = Image.new("L", (size_px, size_px), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, size_px - margin - 1, size_px - margin - 1],
        radius=radius,
        fill=255,
    )
    return mask


# --------------------------------------------------------------------------
# The subject: isometric soil plot + sprouts + coin
# --------------------------------------------------------------------------


class Pen:
    """Draws subject shapes given in canonical units onto a supersampled image.

    ``(cx, cy)`` is where the plot's top-face centre lands, in design pixels,
    and ``s`` is design pixels per canonical unit.  Every point is recorded in
    canonical space so callers can measure the subject without rasterising it.
    """

    def __init__(self, img: Image.Image, cx: float, cy: float, s: float, ss: int):
        self.draw = ImageDraw.Draw(img)
        self.cx = cx
        self.cy = cy
        self.s = s
        self.ss = ss
        self.points: list[tuple[float, float]] = []

    def _pt(self, u: float, v: float) -> tuple[float, float]:
        return ((self.cx + u * self.s) * self.ss, (self.cy + v * self.s) * self.ss)

    def poly(self, uv, color) -> None:
        self.points.extend(uv)
        self.draw.polygon([self._pt(u, v) for u, v in uv], fill=color)

    def disc(self, cu: float, cv: float, r: float, color) -> None:
        steps = 24
        for i in range(steps):
            a = 2.0 * math.pi * i / steps
            self.points.append((cu + r * math.cos(a), cv + r * math.sin(a)))
        x0, y0 = self._pt(cu - r, cv - r)
        x1, y1 = self._pt(cu + r, cv + r)
        self.draw.ellipse([x0, y0, x1, y1], fill=color)

    def leaf(self, base, length, width, angle_deg, color, n=26) -> None:
        """Chunky pointed leaf, rooted at ``base`` and pointing along ``angle_deg``."""
        a = math.radians(angle_deg)
        ca, sa = math.cos(a), math.sin(a)
        outline = []
        for i in range(n + 1):
            t = i / n
            hw = 0.5 * width * math.sin(math.pi * t) ** 0.62
            outline.append((length * t, -hw))
        for i in range(n + 1):
            t = 1.0 - i / n
            hw = 0.5 * width * math.sin(math.pi * t) ** 0.62
            outline.append((length * t, hw))
        pts = [
            (base[0] + x * ca - y * sa, base[1] + x * sa + y * ca)
            for x, y in outline
        ]
        self.poly(pts, color)

    def sprout(self, bx: float, by: float, k: float) -> None:
        stem_hw, stem_h, leaf_len, leaf_w = SPROUT
        stem_hw *= k
        stem_h *= k
        leaf_len *= k
        leaf_w *= k

        # Stem: a chunky stalk that tapers to a point, so no flat cut shows
        # between the leaves.
        self.poly(
            [
                (bx - stem_hw, by),
                (bx + stem_hw, by),
                (bx + stem_hw * 0.45, by - stem_h * 0.90),
                (bx, by - stem_h * 1.14),
                (bx - stem_hw * 0.45, by - stem_h * 0.90),
            ],
            CROP_DARK,
        )
        # Back (right) leaf first, then the lighter front (left) leaf.
        self.leaf((bx + 8 * k, by - stem_h * 0.88), leaf_len * 0.95, leaf_w * 0.92, -52, CROP_MID)
        self.leaf((bx - 8 * k, by - stem_h * 0.72), leaf_len, leaf_w, -128, CROP_LIT)

    def coin(self, cu: float, cv: float, r: float) -> None:
        self.disc(cu, cv, r, COIN_RIM)
        self.disc(cu, cv, r * 0.86, COIN_BODY)
        # Lighter face: reads as a struck coin even at 14 px wide.
        self.disc(cu, cv, r * 0.52, COIN_LIT)


def draw_subject(pen: Pen) -> None:
    """Draw the soil plot, its two sprouts and the gold coin."""

    left = (-PLOT_HW, 0.0)
    top = (0.0, -PLOT_HH)
    right = (PLOT_HW, 0.0)
    bottom = (0.0, PLOT_HH)

    # Silhouette first so the faces never show a hairline seam.
    pen.poly(
        [
            left,
            top,
            right,
            (right[0], right[1] + PLOT_D),
            (bottom[0], bottom[1] + PLOT_D),
            (left[0], left[1] + PLOT_D),
        ],
        SOIL_RIGHT,
    )
    # Front faces (left face lighter than the right one).
    pen.poly(
        [left, bottom, (bottom[0], bottom[1] + PLOT_D), (left[0], left[1] + PLOT_D)],
        SOIL_LEFT,
    )
    # Top face.
    pen.poly([left, top, right, bottom], SOIL_TOP)

    for bx, by, k in CROPS:
        pen.sprout(bx, by, k)

    pen.coin(*COIN)


def subject_points() -> list[tuple[float, float]]:
    """Collect the subject's outline in canonical space without rendering it."""
    scratch = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    pen = Pen(scratch, 0.0, 0.0, 1.0, 1)
    draw_subject(pen)
    return pen.points


def subject_bounds(points) -> tuple[float, float, float, float]:
    us = [p[0] for p in points]
    vs = [p[1] for p in points]
    return min(us), min(vs), max(us), max(vs)


def max_radius(points, cu: float, cv: float) -> float:
    return max(math.hypot(u - cu, v - cv) for u, v in points)


# --------------------------------------------------------------------------
# Renderers
# --------------------------------------------------------------------------


def render_icon(size: int = ICON_SIZE, ss: int = SUPERSAMPLE) -> Image.Image:
    """Full-bleed rounded-square icon (opaque RGB)."""
    px = size * ss
    scene = Image.new("RGB", (px, px))
    paint_background(scene, HORIZON_FRAC, sun=SUN)

    pts = subject_points()
    u0, v0, u1, v1 = subject_bounds(pts)
    s = (0.73 * size) / (u1 - u0)
    cu = (u0 + u1) * 0.5
    cv = (v0 + v1) * 0.5
    cx = size * 0.5 - cu * s
    cy = size * 0.555 - cv * s

    draw_subject(Pen(scene, cx, cy, s, ss))

    plate = Image.new("RGB", (px, px), FRAME_COLOR)
    scale = size / float(ICON_SIZE)
    mask = rounded_mask(
        px,
        int(round(FRAME_MARGIN * scale * ss)),
        int(round(FRAME_RADIUS * scale * ss)),
    )
    plate.paste(scene, (0, 0), mask)

    return plate.resize((size, size), Image.Resampling.LANCZOS)


def render_adaptive_background(size: int = ADAPTIVE_SIZE, ss: int = SUPERSAMPLE) -> Image.Image:
    """Full-bleed sky + field, no subject (opaque RGB)."""
    px = size * ss
    bg = Image.new("RGB", (px, px))
    paint_background(bg, HORIZON_FRAC)
    return bg.resize((size, size), Image.Resampling.LANCZOS)


def render_adaptive_foreground(
    size: int = ADAPTIVE_SIZE,
    ss: int = SUPERSAMPLE,
    safe_radius: float = 138.0,
) -> Image.Image:
    """The plot + sprouts + coin on a transparent canvas, inside the safe zone."""
    pts = subject_points()
    u0, v0, u1, v1 = subject_bounds(pts)
    cu = (u0 + u1) * 0.5
    cv = (v0 + v1) * 0.5
    r_max = max_radius(pts, cu, cv)

    s = safe_radius / r_max
    cx = size * 0.5 - cu * s
    cy = size * 0.5 - cv * s

    px = size * ss
    layer = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    draw_subject(Pen(layer, cx, cy, s, ss))
    return layer.resize((size, size), Image.Resampling.LANCZOS)


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------


def save(img: Image.Image, name: str) -> str:
    path = os.path.join(OUT_DIR, name)
    img.save(path, "PNG", optimize=True)
    return path


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)

    icon = render_icon(ICON_SIZE)
    icon_192 = icon.resize((SMALL_ICON_SIZE, SMALL_ICON_SIZE), Image.Resampling.LANCZOS)
    fg = render_adaptive_foreground(ADAPTIVE_SIZE)
    bg = render_adaptive_background(ADAPTIVE_SIZE)

    written = [
        save(icon, "icon.png"),
        save(icon_192, "icon_192.png"),
        save(fg, "adaptive_foreground_432.png"),
        save(bg, "adaptive_background_432.png"),
    ]

    for path in written:
        with Image.open(path) as im:
            im.load()
            stat = os.stat(path)
            print(f"{os.path.relpath(path, ROOT):48s} {im.size[0]}x{im.size[1]} "
                  f"{im.mode:4s} {stat.st_size:7d} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
