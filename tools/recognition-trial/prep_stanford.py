"""Estrae da Stanford Cars (HF tanganke/stanford_cars, split test) le foto dei modelli
presenti in labels.csv e scrive stanford/ con truth.csv per evaluate.py.

    .venv/bin/python -I prep_stanford.py [--per-class 25]

Foto reali e varie (non da salone), ma auto USA fino al 2012: i modelli europei recenti
non ci sono. Generazione non nella verità.
"""
import argparse
import csv
import io
import json
from pathlib import Path

import pyarrow.parquet as pq
from huggingface_hub import hf_hub_download
from PIL import Image

HERE = Path(__file__).parent
REPO = "tanganke/stanford_cars"
SHARDS = ["data/test-00000-of-00002.parquet", "data/test-00001-of-00002.parquet"]

# Classe Stanford → (marca, modello) di labels.csv. Solo abbinamenti certi; le varianti
# sportive (S4, M5…) vanno sul modello base che il catalogo conosce.
MAP = {
    "Aston Martin V8 Vantage Convertible 2012": ("Aston Martin", "Vantage"),
    "Aston Martin V8 Vantage Coupe 2012": ("Aston Martin", "Vantage"),
    "Audi A5 Coupe 2012": ("Audi", "A5"),
    "Audi S5 Convertible 2012": ("Audi", "A5"),
    "Audi S5 Coupe 2012": ("Audi", "A5"),
    "Audi S4 Sedan 2007": ("Audi", "A4"),
    "Audi S4 Sedan 2012": ("Audi", "A4"),
    "Audi S6 Sedan 2011": ("Audi", "A6"),
    "Audi R8 Coupe 2012": ("Audi", "R8"),
    "Audi TT Hatchback 2011": ("Audi", "TT"),
    "Audi TT RS Coupe 2012": ("Audi", "TT"),
    "Audi TTS Coupe 2012": ("Audi", "TT"),
    "BMW 1 Series Convertible 2012": ("BMW", "Serie 1"),
    "BMW 1 Series Coupe 2012": ("BMW", "Serie 1"),
    "BMW 3 Series Sedan 2012": ("BMW", "Serie 3"),
    "BMW 3 Series Wagon 2012": ("BMW", "Serie 3"),
    "BMW ActiveHybrid 5 Sedan 2012": ("BMW", "Serie 5"),
    "BMW M5 Sedan 2010": ("BMW", "Serie 5"),
    "BMW M3 Coupe 2012": ("BMW", "M3"),
    "BMW X3 SUV 2012": ("BMW", "X3"),
    "BMW X5 SUV 2007": ("BMW", "X5"),
    "BMW Z4 Convertible 2012": ("BMW", "Z4"),
    "Bentley Continental GT Coupe 2007": ("Bentley", "Continental GT"),
    "Bentley Continental GT Coupe 2012": ("Bentley", "Continental GT"),
    "Bentley Continental Supersports Conv. Convertible 2012": ("Bentley", "Continental GT"),
    "Chevrolet Corvette Convertible 2012": ("Chevrolet", "Corvette"),
    "Chevrolet Corvette Ron Fellows Edition Z06 2007": ("Chevrolet", "Corvette"),
    "Chevrolet Corvette ZR1 2012": ("Chevrolet", "Corvette"),
    "Dodge Challenger SRT8 2011": ("Dodge", "Challenger"),
    "FIAT 500 Convertible 2012": ("Fiat", "500"),
    "Ferrari 458 Italia Convertible 2012": ("Ferrari", "458 Italia"),
    "Ferrari 458 Italia Coupe 2012": ("Ferrari", "458 Italia"),
    "Ferrari California Convertible 2012": ("Ferrari", "California"),
    "Ford Fiesta Sedan 2012": ("Ford", "Fiesta"),
    "Ford Focus Sedan 2007": ("Ford", "Focus"),
    "Ford Mustang Convertible 2007": ("Ford", "Mustang"),
    "Hyundai Tucson SUV 2012": ("Hyundai", "Tucson"),
    "Jeep Compass SUV 2012": ("Jeep", "Compass"),
    "Jeep Grand Cherokee SUV 2012": ("Jeep", "Grand Cherokee"),
    "Jeep Wrangler SUV 2012": ("Jeep", "Wrangler"),
    "Lamborghini Aventador Coupe 2012": ("Lamborghini", "Aventador"),
    "Lamborghini Gallardo LP 570-4 Superleggera 2012": ("Lamborghini", "Gallardo"),
    "MINI Cooper Roadster Convertible 2012": ("Mini", "Cooper"),
    "Mercedes-Benz C-Class Sedan 2012": ("Mercedes-Benz", "Classe C"),
    "Mercedes-Benz E-Class Sedan 2012": ("Mercedes-Benz", "Classe E"),
    "Mercedes-Benz SL-Class Coupe 2009": ("Mercedes-Benz", "SL"),
    "Nissan Juke Hatchback 2012": ("Nissan", "Juke"),
    "Nissan Leaf Hatchback 2012": ("Nissan", "Leaf"),
    "Tesla Model S Sedan 2012": ("Tesla", "Model S"),
    "Toyota Corolla Sedan 2012": ("Toyota", "Corolla"),
    "Volkswagen Beetle Hatchback 2012": ("Volkswagen", "Maggiolino (Beetle)"),
    "Volkswagen Golf Hatchback 1991": ("Volkswagen", "Golf"),
    "Volkswagen Golf Hatchback 2012": ("Volkswagen", "Golf"),
    "Volvo 240 Sedan 1993": ("Volvo", "240"),
    "Volvo XC90 SUV 2007": ("Volvo", "XC90"),
    "smart fortwo Convertible 2012": ("Smart", "Fortwo"),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-class", type=int, default=25, help="max foto per classe Stanford")
    ap.add_argument("--out", default="stanford")
    args = ap.parse_args()

    catalog = {(r["make"], r["model"]) for r in csv.DictReader(open(HERE / "labels.csv", encoding="utf-8"))}
    missing = {v for v in MAP.values() if v not in catalog}
    assert not missing, f"Modelli non in labels.csv: {missing}"

    out = HERE / args.out
    out.mkdir(exist_ok=True)
    counts: dict[str, int] = {}
    rows = []
    for shard in SHARDS:
        path = hf_hub_download(REPO, shard, repo_type="dataset", cache_dir=HERE / ".cache")
        names = json.loads(pq.read_schema(path).metadata[b"huggingface"])["info"]["features"]["label"]["names"]
        table = pq.read_table(path)
        for img, label in zip(table.column("image").to_pylist(), table.column("label").to_pylist()):
            cls = names[label]
            if cls not in MAP or counts.get(cls, 0) >= args.per_class:
                continue
            counts[cls] = counts.get(cls, 0) + 1
            make, model = MAP[cls]
            name = f"sc_{label:03d}_{counts[cls]:02d}.jpg"
            Image.open(io.BytesIO(img["bytes"])).convert("RGB").save(out / name, quality=92)
            rows.append({"file": name, "make": make, "model": model, "generation": ""})

    with open(out / "truth.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["file", "make", "model", "generation"])
        w.writeheader()
        w.writerows(rows)
    print(f"{len(rows)} foto, {len(counts)} classi Stanford, {len(set(MAP[c] for c in counts))} modelli → {out}")


if __name__ == "__main__":
    main()
