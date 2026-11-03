#!/usr/bin/env python3
"""Genera i livelli dell'icona CarSpot (glifo C2f) in SVG e PNG trasparenti 1024x1024.

Uso: python3 design/icon/build_icon_layers.py <cartella-output>
     python3 design/icon/build_icon_layers.py CarSpot/Assets.xcassets/BrandMark.imageset --brand-mark
Le varianti chiara/scura servono a Icon Composer (image-name-specializations).
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supersampling per bordi lisci

STROKE = 84
# Tetto della coupé (in alto) e scia (in basso): insieme formano la C.
PATHS = [
    [(170, 540), (170, 448), (250, 404), (362, 390),
     (428, 316), (512, 272), (610, 272),
     (700, 272), (774, 312), (856, 356)],
    [(176, 636), (290, 734), (420, 774), (552, 762),
     (696, 748), (800, 676), (860, 576)],
]
DOT = (376, 548, 74)  # cx, cy, r: la ruota/occhio ambra

# Stessi colori su sfondo chiaro e scuro: cambia solo il fill dell'icona.
# Le varianti per livello non vengono applicate dal renderer di Icon Composer.
COLORS = {
    "glyph": {"c": "#12C3E8", "dot": "#FFAD2E"},
}


def svg_path(points):
    d = f"M{points[0][0]} {points[0][1]}"
    for i in range(1, len(points), 3):
        (a, b), (c, e), (f, g) = points[i:i + 3]
        d += f" C{a} {b} {c} {e} {f} {g}"
    return d


def bezier(p0, p1, p2, p3, steps=200):
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        yield (mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0],
               mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1])


def png_layer(kind, color):
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    if kind == "c":
        r = STROKE * SS / 2
        for pts in PATHS:
            for i in range(0, len(pts) - 1, 3):
                for x, y in bezier(*pts[i:i + 4]):
                    x, y = x * SS, y * SS
                    draw.ellipse((x - r, y - r, x + r, y + r), fill=color)
    else:
        cx, cy, r = (v * SS for v in DOT)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def svg_layer(kind, color):
    head = f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">\n'
    if kind == "c":
        body = (f'  <g fill="none" stroke="{color}" stroke-width="{STROKE}" '
                f'stroke-linecap="round" stroke-linejoin="round">\n'
                + "".join(f'    <path d="{svg_path(p)}"/>\n' for p in PATHS) + "  </g>\n")
    else:
        cx, cy, r = DOT
        body = f'  <circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}"/>\n'
    return head + body + "</svg>\n"


def brand_mark_svg():
    """Marchio per l'interno dell'app: glifo ritagliato, colori CSColor (accent + accentWarm)."""
    cx, cy, r = DOT
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="784" height="584" viewBox="124 226 784 584">\n'
        f'  <g fill="none" stroke="#1CD5F3" stroke-width="{STROKE}" '
        'stroke-linecap="round" stroke-linejoin="round">\n'
        + "".join(f'    <path d="{svg_path(p)}"/>\n' for p in PATHS)
        + "  </g>\n"
        f'  <circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFB23E"/>\n'
        "</svg>\n"
    )


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    if len(sys.argv) > 2 and sys.argv[2] == "--brand-mark":
        (out / "BrandMark.svg").write_text(brand_mark_svg())
        return
    for mode, cols in COLORS.items():
        for kind in ("c", "dot"):
            png_layer(kind, cols[kind]).save(out / f"{kind}-{mode}.png")
            (out / f"{kind}-{mode}.svg").write_text(svg_layer(kind, cols[kind]))


if __name__ == "__main__":
    main()
