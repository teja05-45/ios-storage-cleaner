#!/usr/bin/env python3
"""
Generates Reclaim's original app icon (1024x1024 PNG, stdlib only).

Why a generator: the assignment requires ORIGINAL artwork. This icon is
composed from geometry defined in this file — an accent-color gradient
background with a white "reclaim" ring and arrowhead motif (storage being
reclaimed) — so its provenance is the script itself, exactly like the
project-file generator. Deterministic: re-running reproduces the identical
PNG byte-for-byte. No third-party assets, no copied branding, no image
libraries — the PNG is emitted manually (zlib is stdlib).

Design notes (Document 02 §2): accent color #2696FA-family gradient,
rounded sense of depth via a subtle inner vignette; the motif is a thick
white ring with a gap and an arrowhead sweeping into it, reading as
"space coming back".

Run: python scripts/generate_app_icon.py
Output: Reclaim/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Reclaim", "Resources", "Assets.xcassets", "AppIcon.appiconset")
OUT_PATH = os.path.join(OUT_DIR, "AppIcon.png")

SIZE = 1024
CX = CY = SIZE / 2.0

# Palette (matches AccentColor.colorset: r 0.15 g 0.59 b 0.98).
TOP_COLOR = (0x3D, 0xA8, 0xFF)
BOTTOM_COLOR = (0x12, 0x7E, 0xE6)


def gradient_background(x: int, y: int) -> tuple[int, int, int]:
    """Vertical two-stop gradient with a soft radial vignette."""
    t = y / (SIZE - 1)
    r = TOP_COLOR[0] + (BOTTOM_COLOR[0] - TOP_COLOR[0]) * t
    g = TOP_COLOR[1] + (BOTTOM_COLOR[1] - TOP_COLOR[1]) * t
    b = TOP_COLOR[2] + (BOTTOM_COLOR[2] - TOP_COLOR[2]) * t
    # Vignette: darken slightly toward the far corners for depth.
    dx, dy = x - CX, y - CY
    dist = math.hypot(dx, dy) / (SIZE * 0.5)
    vignette = 1.0 - 0.18 * max(0.0, dist - 0.55) / 0.45
    return (
        max(0, min(255, int(r * vignette))),
        max(0, min(255, int(g * vignette))),
        max(0, min(255, int(b * vignette))),
    )


def supersample_pixel(x: int, y: int, samples: int = 3) -> tuple[int, int, int]:
    """3x3 supersampling for smooth edges on the motif geometry."""
    acc = [0, 0, 0]
    for sy in range(samples):
        for sx in range(samples):
            px = x + (sx + 0.5) / samples
            py = y + (sy + 0.5) / samples
            r, g, b = gradient_background(int(px), int(py))
            if motif_alpha(px, py):
                r, g, b = 255, 255, 255
            acc[0] += r
            acc[1] += g
            acc[2] += b
    n = samples * samples
    return (acc[0] // n, acc[1] // n, acc[2] // n)


def motif_alpha(x: float, y: float) -> bool:
    """
    The mark: a thick white ring with a gap at the upper right, and an
    arrowhead flying into the gap from outside — "space reclaimed".
    """
    dx, dy = x - CX, y - CY
    dist = math.hypot(dx, dy)
    angle = math.degrees(math.atan2(-dy, dx)) % 360.0  # 0° = right, CCW positive

    ring_outer, ring_inner = 330.0, 210.0
    gap_start, gap_end = 20.0, 85.0  # degrees, upper-right

    if ring_inner <= dist <= ring_outer and not (gap_start <= angle <= gap_end):
        return True

    # Arrowhead: an isoceles triangle pointing at the ring gap.
    # Tip sits just outside the gap's bisector; base extends outward.
    bisector = math.radians((gap_start + gap_end) / 2.0)
    tip_r, base_r = 395.0, 480.0
    half_angle = math.radians(21.0)

    rel = math.atan2(-dy, dx) - bisector
    # Normalize to [-pi, pi]
    rel = (rel + math.pi) % (2 * math.pi) - math.pi
    if tip_r <= dist <= base_r and abs(rel) <= half_angle:
        # Taper the triangle toward the tip for a proper arrowhead shape.
        t = (dist - tip_r) / (base_r - tip_r)
        if abs(rel) <= half_angle * (0.25 + 0.75 * t):
            return True

    return False


def build_rows() -> list[bytes]:
    rows = []
    for y in range(SIZE):
        row = bytearray([0])  # filter byte 0
        for x in range(SIZE):
            row.extend(supersample_pixel(x, y))
        rows.append(bytes(row))
    return rows


def write_png(rows: list[bytes]) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB
    idat = zlib.compress(b"".join(rows), 9)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", idat)
        + chunk(b"IEND", b"")
    )
    with open(OUT_PATH, "wb") as f:
        f.write(png)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(build_rows())
    print(f"Wrote {OUT_PATH} ({os.path.getsize(OUT_PATH)} bytes, {SIZE}x{SIZE})")


if __name__ == "__main__":
    sys.exit(main())
