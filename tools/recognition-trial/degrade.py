"""Simula scatti "da strada" peggiorando le foto pulite (default samples/ di Commons):
inquadratura parziale, poca risoluzione, mosso, sera/controluce, compressione.
Ogni foto riceve 2–3 difetti scelti a caso ma in modo riproducibile (seed fisso).

    .venv/bin/python -I degrade.py [--src samples] [--out degraded]

Copia truth.csv aggiungendo la colonna `effects`. È una stima, non foto vere.
"""
import argparse
import csv
import io
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

HERE = Path(__file__).parent


def crop(im, r):  # auto tagliata dal bordo o vista solo in parte
    w, h = im.size
    keep = r.uniform(0.55, 0.8)
    cw, ch = int(w * keep), int(h * r.uniform(0.7, 0.95))
    x, y = r.randint(0, w - cw), r.randint(0, h - ch)
    return im.crop((x, y, x + cw, y + ch))


def lowres(im, r):  # auto lontana: pochi pixel utili
    w, h = im.size
    s = r.uniform(160, 260) / max(w, h)
    return im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.BILINEAR).resize((w, h), Image.BILINEAR)


def blur(im, r):  # mosso o fuori fuoco
    if r.random() < 0.5:
        return im.filter(ImageFilter.GaussianBlur(r.uniform(2, 4)))
    return im.filter(ImageFilter.BoxBlur(r.uniform(2, 3.5)))


def dark(im, r):  # sera / ombra con rumore del sensore
    im = ImageEnhance.Brightness(im).enhance(r.uniform(0.3, 0.5))
    a = np.asarray(im).astype(np.float32)
    a += np.random.default_rng(r.randint(0, 1 << 30)).normal(0, r.uniform(8, 16), a.shape)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def glare(im, r):  # controluce: contrasto e colori slavati
    im = ImageEnhance.Contrast(im).enhance(r.uniform(0.45, 0.65))
    return ImageEnhance.Brightness(im).enhance(r.uniform(1.2, 1.4))


def tilt(im, r):  # telefono storto
    return im.rotate(r.uniform(-12, 12), resample=Image.BICUBIC, expand=False, fillcolor=(90, 90, 90))


def jpeg(im, r):  # compressione forte (screenshot, chat)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=r.randint(15, 30))
    return Image.open(io.BytesIO(buf.getvalue())).convert("RGB")


EFFECTS = {"crop": crop, "lowres": lowres, "blur": blur, "dark": dark, "glare": glare, "tilt": tilt}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="samples")
    ap.add_argument("--out", default="degraded")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    src, out = HERE / args.src, HERE / args.out
    out.mkdir(exist_ok=True)
    rows = list(csv.DictReader(open(src / "truth.csv", encoding="utf-8")))
    for row in rows:
        r = random.Random(f"{args.seed}:{row['file']}")
        im = ImageOps.exif_transpose(Image.open(src / row["file"])).convert("RGB")
        names = r.sample(sorted(EFFECTS), r.choice([2, 3]))
        for n in names:
            im = EFFECTS[n](im, r)
        im = jpeg(im, r)
        im.save(out / row["file"], quality=95)
        row["effects"] = "+".join(names)

    with open(out / "truth.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"{len(rows)} foto peggiorate → {out}")


if __name__ == "__main__":
    main()
