#!/usr/bin/env python3
"""Generates Resources/AppIcon-1024.png and Resources/AppIcon.icns (needs Pillow).

Follows Apple's macOS icon grid: 1024 px canvas, ~824 px rounded-square body centred with a soft
drop shadow, a single simple glyph, no text.
"""
import struct, io, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 1024 * 2                      # draw at 2x, downsample for smooth edges
body = 824 * 2
off = (S - body) // 2

def squircle_mask(size, n=5.0):
    """Superellipse approximating Apple's continuous-corner rounded rectangle."""
    m = Image.new("L", (size, size), 0)
    px = m.load()
    r = size / 2
    for y in range(size):
        ny = abs((y + 0.5 - r) / r) ** n
        if ny >= 1: continue
        span = (1 - ny) ** (1 / n)
        x0 = int(r - span * r); x1 = int(r + span * r)
        for x in range(max(x0 - 1, 0), min(x1 + 2, size)):
            nx = abs((x + 0.5 - r) / r) ** n
            v = 1 - (nx + ny)
            if v > 0.004: px[x, y] = 255
            elif v > -0.004: px[x, y] = int(255 * (v + 0.004) / 0.008)
    return m

def vgradient(size, top, bottom):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((size, size))

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
mask = squircle_mask(body)

# Soft shadow under the body
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sm = Image.new("L", (S, S), 0); sm.paste(mask, (off, off + 14))
shadow.putalpha(sm.point(lambda v: int(v * 0.30)))
shadow = shadow.filter(ImageFilter.GaussianBlur(22))
canvas = Image.alpha_composite(canvas, shadow)

# Body: indigo → teal gradient
grad = vgradient(body, (88, 86, 214), (20, 168, 190)).convert("RGBA")
grad.putalpha(mask)
canvas.alpha_composite(grad, (off, off))

# Glyph: three staggered Gantt bars + a milestone diamond, optically centred, with a soft shadow
glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(glyph)
unit = body * 0.56
x0 = S / 2 - unit / 2
h = body * 0.085
rows = [(0.00, 0.52, 0.285), (0.20, 0.80, 0.405), (0.42, 1.00, 0.525)]
for a, b, ytop in rows:
    y = off + body * ytop
    d.rounded_rectangle((x0 + unit * a, y, x0 + unit * b, y + h), radius=h / 2, fill=(255, 255, 255, 255))
cx, cy, r = x0 + unit * 0.86, off + body * 0.68 + h / 2, body * 0.066
d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=(255, 214, 10, 255))

gshadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gshadow.putalpha(glyph.getchannel("A").point(lambda v: int(v * 0.22)))
gshadow = ImageChops.offset(gshadow, 0, 10).filter(ImageFilter.GaussianBlur(10))
canvas = Image.alpha_composite(canvas, gshadow)
canvas = Image.alpha_composite(canvas, glyph)

icon = canvas.resize((1024, 1024), Image.LANCZOS)
os.makedirs("Resources", exist_ok=True)
icon.save("Resources/AppIcon-1024.png")

# --- .icns (PNG payloads) ---
types = {"icp4": 16, "icp5": 32, "icp6": 64, "ic07": 128, "ic08": 256, "ic09": 512, "ic10": 1024,
         "ic11": 32, "ic12": 64, "ic13": 256, "ic14": 512}
chunks = b""
for t, px in types.items():
    buf = io.BytesIO(); icon.resize((px, px), Image.LANCZOS).save(buf, "PNG")
    data = buf.getvalue()
    chunks += t.encode() + struct.pack(">I", len(data) + 8) + data
with open("Resources/AppIcon.icns", "wb") as f:
    f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
print("wrote Resources/AppIcon-1024.png and AppIcon.icns")
