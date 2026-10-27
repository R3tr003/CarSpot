"""Passo 4: scontorno (CLI Swift) e conversione in WebP con trasparenza.

Ingresso: out/raw/, out/attribution.json. Uscita: out/cut/*.png, out/images/<make>/<variant>.webp,
out/images_manifest.json, out/images_report.md. Uso: python3 -I process_images.py
"""
import subprocess
import sys
from collections import Counter
from io import BytesIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # solo i moduli della pipeline
from catalog_common import OUT, ROOT, read_json, write_json

from PIL import Image

LONG_SIDE = 512
MAX_BYTES = 60_000


def encode_webp(png: Path) -> tuple[bytes, int, int]:
    im = Image.open(png).convert("RGBA")
    im.thumbnail((LONG_SIDE, LONG_SIDE), Image.LANCZOS)
    data = b""
    for quality in (80, 72, 66, 60):
        buf = BytesIO()
        im.save(buf, "WEBP", quality=quality, method=6, alpha_quality=90)
        data = buf.getvalue()
        if len(data) <= MAX_BYTES:
            break
    return data, im.width, im.height


def main() -> None:
    cutout = OUT / "bin" / "cutout"
    if not cutout.exists():
        subprocess.run([str(ROOT / "cutout" / "build.sh")], check=True)
    results = subprocess.run([str(cutout), str(OUT / "raw"), str(OUT / "cut")],
                             capture_output=True, text=True).stdout
    log_path = OUT / "cutout.log"
    with log_path.open("a", encoding="utf-8") as f:
        f.write(results)

    outcome = {}
    for line in log_path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            outcome[parts[0]] = parts[1:]

    catalog = read_json(OUT / "catalog.json")
    make_of = {m["id"]: m["makeId"] for m in catalog["models"]}
    model_of = {v["id"]: v["modelId"] for v in catalog["variants"]}
    attribution = read_json(OUT / "attribution.json")
    manifest = {}
    sizes = []
    for vid in attribution:
        png = OUT / "cut" / f"{vid}.png"
        if not png.exists() or vid not in model_of:
            continue
        path = f"{make_of[model_of[vid]]}/{vid}.webp"
        dest = OUT / "images" / path
        if not dest.exists():
            data, w, h = encode_webp(png)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        with Image.open(dest) as im:
            w, h = im.size
        manifest[vid] = {"path": path, "width": w, "height": h}
        sizes.append(dest.stat().st_size)
    write_json(OUT / "images_manifest.json", manifest)

    counts = Counter(v[0] for v in outcome.values())
    plates = sum(int(v[1]) for v in outcome.values() if v[0] == "ok" and len(v) > 1 and v[1].isdigit())
    rejected = read_json(OUT / "rejected.json") if (OUT / "rejected.json").exists() else {}
    lic = Counter(a["license"] for a in attribution.values())
    lines = ["# Immagini", "",
             f"- WebP pronti: {len(manifest)} (media {sum(sizes) // max(len(sizes), 1) // 1000} KB, "
             f"totale {sum(sizes) // 1_000_000} MB)",
             f"- Esiti scontorno: {dict(counts)}", f"- Targhe sfocate: {plates}",
             f"- Scartate prima del download: {len(rejected)}", "", "## Licenze", ""]
    lines += [f"- {k}: {v}" for k, v in lic.most_common()]
    lines += ["", "## Motivi di scarto (download)", ""]
    lines += [f"- {k}: {v}" for k, v in Counter(r.split(":")[0] for r in rejected.values()).most_common()]
    lines += ["", "Da rivedere a mano: foto con più auto (lo scontorno tiene la più grande) e targhe "
              "piccole o storte che l'OCR non legge."]
    (OUT / "images_report.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"webp {len(manifest)}")


if __name__ == "__main__":
    sys.exit(main())
