#!/usr/bin/env python3
"""Render the original Hermes paper-plane mark using only the Python stdlib."""
from pathlib import Path
import math
import struct
import zlib

SIZE = 1024
SAMPLES = 2
OUTPUT = Path(__file__).parent / "Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def inside_polygon(x, y, points):
    inside = False
    previous_x, previous_y = points[-1]
    for current_x, current_y in points:
        if (current_y > y) != (previous_y > y):
            crossing = (previous_x - current_x) * (y - current_y) / (previous_y - current_y) + current_x
            if x < crossing:
                inside = not inside
        previous_x, previous_y = current_x, current_y
    return inside


def color_at(x, y):
    # Full-bleed opaque blue. The operating system supplies the icon mask.
    glow = max(0, 1 - math.hypot(x - 300, y - 180) / 1050)
    background = (26 + 24 * glow, 60 + 37 * glow, 171 + 50 * glow)
    plane = [(219, 470), (806, 239), (634, 796), (489, 574)]
    fold = [(489, 574), (806, 239), (562, 650)]
    wing = [(219, 470), (806, 239), (489, 574)]
    if inside_polygon(x, y, fold):
        return (161, 191, 255)
    if inside_polygon(x, y, wing):
        return (255, 255, 255)
    if inside_polygon(x, y, plane):
        return (231, 240, 255)
    return background


pixels = bytearray()
for row in range(SIZE):
    pixels.append(0)  # PNG filter: None
    for column in range(SIZE):
        colors = [color_at(column + (sx + 0.5) / SAMPLES, row + (sy + 0.5) / SAMPLES)
                  for sy in range(SAMPLES) for sx in range(SAMPLES)]
        pixels.extend(round(sum(sample[channel] for sample in colors) / len(colors))
                      for channel in range(3))


def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xffffffff)


header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # truecolor RGB, no alpha
OUTPUT.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(pixels, 9)) + chunk(b"IEND", b""))
print(f"Created {OUTPUT}: {SIZE}x{SIZE}, RGB, no alpha")
