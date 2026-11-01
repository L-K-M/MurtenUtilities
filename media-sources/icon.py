#!/usr/bin/env python3
"""Generates assets/MurtenUtilities-icon.png — the committed 1024x1024 master
that scripts/make-icon.swift explodes into the .iconset at build time.

The motif is the suite itself: a classic platinum window (the home screen)
holding a small grid of coloured tool tiles. Provisional artwork — redraw the
master when the suite gets its real icon language (docs/ui-direction.md); this
file exists so the icon is reproducible, per the fleet's icon convention.

Requires Pillow: python3 media-sources/icon.py
"""
from PIL import Image, ImageDraw

SIZE = 1024
OUT = "assets/MurtenUtilities-icon.png"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Platinum window body with a vertical gradient, like classic Mac chrome.
    body = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    grad = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        grad.putpixel((0, y), lerp((240, 240, 240), (200, 200, 200), y / SIZE))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (64, 64, SIZE - 64, SIZE - 64), radius=190, fill=255)
    body.paste(grad.resize((SIZE, SIZE)).convert("RGBA"), (0, 0), mask)
    img = Image.alpha_composite(img, body)

    d = ImageDraw.Draw(img)
    # Outer hairline + top highlight, the classic bevel pair.
    d.rounded_rectangle((64, 64, SIZE - 64, SIZE - 64), radius=190,
                        outline=(140, 140, 140, 255), width=3)
    d.line((130, 70, SIZE - 130, 70), fill=(255, 255, 255, 200), width=3)

    # Title-bar strip with the two classic pinstripe grooves.
    d.rectangle((96, 120, SIZE - 96, 128), fill=(170, 170, 170, 255))
    d.rectangle((96, 136, SIZE - 96, 140), fill=(170, 170, 170, 255))

    # A 2x2 grid of inset "tool" wells, each with a muted classic colour —
    # the toolbox home screen in miniature.
    tiles = [
        (88, 136, 150),   # steel blue
        (168, 150, 96),   # olive gold
        (150, 110, 88),   # terracotta
        (120, 132, 122),  # sage
    ]
    grid_x0, grid_y0, cell, gap = 216, 268, 280, 32
    for i, colour in enumerate(tiles):
        x = grid_x0 + (i % 2) * (cell + gap)
        y = grid_y0 + (i // 2) * (cell + gap)
        # Inset well: hairline border, white inner face, faint top shadow.
        d.rounded_rectangle((x, y, x + cell, y + cell), radius=28,
                            fill=(250, 250, 250, 255), outline=(150, 150, 150, 255), width=3)
        d.line((x + 10, y + 3, x + cell - 10, y + 3), fill=(0, 0, 0, 25), width=2)
        # The tool tile itself.
        pad = 44
        d.rounded_rectangle((x + pad, y + pad, x + cell - pad, y + cell - pad),
                            radius=20, fill=colour + (255,),
                            outline=tuple(max(0, c - 40) for c in colour) + (255,), width=3)
        # Top-left highlight dot, like the gloss on a classic icon.
        d.ellipse((x + pad + 16, y + pad + 12, x + pad + 52, y + pad + 48),
                  fill=(255, 255, 255, 90))

    img.save(OUT)
    print(f"wrote {OUT} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
