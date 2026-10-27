"""Passo 5: export del catalogo finale.

Ingresso: out/catalog.json, out/attribution.json, out/images_manifest.json.
Uscita: snapshot dell'app (CarSpot/Services/Catalog/Resources/catalog-snapshot.json), out/labels.csv per
il riconoscimento, out/seed/NNNN.sql per Supabase (upsert a blocchi).
"""
import csv
import json
from collections import Counter
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # solo i moduli della pipeline
from catalog_common import OUT, ROOT, read_json

SNAPSHOT = ROOT.parent.parent / "CarSpot" / "Services" / "Catalog" / "Resources" / "catalog-snapshot.json"
IMAGE_BASE = "https://rdezjqbxqekteextolvh.supabase.co/storage/v1/object/public/car-models/"
BODY_TYPES = {"utilitaria", "berlina", "station_wagon", "suv", "monovolume", "coupe", "cabrio",
              "sportiva", "pickup", "furgone"}
BATCH = 500


def sql_text(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, list):
        return "array[" + ",".join(sql_text(x) for x in v) + "]::text[]" if v else "'{}'::text[]"
    return "'" + str(v).replace("'", "''") + "'"


def upserts(table: str, cols: list[str], rows: list[dict]) -> list[str]:
    out = []
    update = ", ".join(f"{c} = excluded.{c}" for c in cols if c != "id") + ", deleted_at = null"
    for i in range(0, len(rows), BATCH):
        values = ",\n".join("(" + ", ".join(sql_text(r[c]) for c in cols) + ")" for r in rows[i:i + BATCH])
        out.append(f"insert into public.{table} ({', '.join(cols)}) values\n{values}\n"
                   f"on conflict (id) do update set {update};")
    return out


def main() -> None:
    cat = read_json(OUT / "catalog.json")
    attribution = read_json(OUT / "attribution.json") if (OUT / "attribution.json").exists() else {}
    manifest = read_json(OUT / "images_manifest.json") if (OUT / "images_manifest.json").exists() else {}
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    makes = [{"id": m["id"], "name": m["name"], "country": m.get("country"), "aliases": m["aliases"],
              "updatedAt": now} for m in cat["makes"]]
    models = [{"id": m["id"], "makeId": m["makeId"], "name": m["name"], "bodyType": m["bodyType"],
               "yearStart": m["yearStart"], "yearEnd": m["yearEnd"], "popularity": m["popularity"],
               "aliases": m["aliases"], "updatedAt": now} for m in cat["models"]]
    variants = []
    for v in cat["variants"]:
        image = None
        if v["id"] in manifest and v["id"] in attribution:
            a, mf = attribution[v["id"]], manifest[v["id"]]
            image = {"path": mf["path"], "width": mf["width"], "height": mf["height"],
                     "title": a["title"], "author": a["author"], "license": a["license"],
                     "licenseURL": a["licenseURL"], "sourceURL": a["sourceURL"], "modified": True}
        variants.append({"id": v["id"], "modelId": v["modelId"], "name": v["name"], "isBase": v["isBase"],
                         "yearStart": v["yearStart"], "yearEnd": v["yearEnd"], "aliases": v["aliases"],
                         "updatedAt": now, "image": image})

    # Validazione: id unici e riferimenti esistenti.
    make_ids = {m["id"] for m in makes}
    model_ids = {m["id"] for m in models}
    assert len(make_ids) == len(makes), "id di marca duplicati"
    assert len(model_ids) == len(models), "id di modello duplicati"
    assert len({v["id"] for v in variants}) == len(variants), "id di versione duplicati"
    assert all(m["makeId"] in make_ids for m in models), "modello senza marca"
    assert all(v["modelId"] in model_ids for v in variants), "versione senza modello"
    assert all(m["bodyType"] in BODY_TYPES for m in models), "carrozzeria non valida"
    bases = Counter(v["modelId"] for v in variants if v["isBase"])
    assert all(bases[mid] == 1 for mid in model_ids), "modello senza versione base unica"

    snapshot = {"version": 1, "generatedAt": now, "imageBaseURL": IMAGE_BASE,
                "makes": makes, "models": models, "variants": variants}
    SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
    SNAPSHOT.write_text(json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
                        encoding="utf-8")

    make_name = {m["id"]: m["name"] for m in makes}
    model_by_id = {m["id"]: m for m in models}
    with (OUT / "labels.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["make", "model", "variant", "variant_id", "year_start", "year_end"])
        for v in variants:
            m = model_by_id[v["modelId"]]
            w.writerow([make_name[m["makeId"]], m["name"], v["name"], v["id"], v["yearStart"] or "", v["yearEnd"] or ""])

    seed = OUT / "seed"
    seed.mkdir(exist_ok=True)
    for old in seed.glob("*.sql"):
        old.unlink()
    rows_makes = [{"id": m["id"], "name": m["name"], "country": m["country"], "aliases": m["aliases"]} for m in makes]
    rows_models = [{"id": m["id"], "make_id": m["makeId"], "name": m["name"], "body_type": m["bodyType"],
                    "year_start": m["yearStart"], "year_end": m["yearEnd"], "popularity": m["popularity"],
                    "aliases": m["aliases"]} for m in models]
    rows_variants = []
    for v in variants:
        img = v["image"] or {}
        rows_variants.append({"id": v["id"], "model_id": v["modelId"], "name": v["name"], "is_base": v["isBase"],
                              "year_start": v["yearStart"], "year_end": v["yearEnd"], "aliases": v["aliases"],
                              "image_path": img.get("path"), "image_width": img.get("width"),
                              "image_height": img.get("height"), "image_title": img.get("title"),
                              "image_author": img.get("author"), "image_license": img.get("license"),
                              "image_license_url": img.get("licenseURL"), "image_source_url": img.get("sourceURL"),
                              "image_modified": bool(img)})
    stmts = (upserts("car_makes", list(rows_makes[0]), rows_makes)
             + upserts("car_models", list(rows_models[0]), rows_models)
             + upserts("car_variants", list(rows_variants[0]), rows_variants))
    for i, stmt in enumerate(stmts, 1):
        (seed / f"{i:04d}.sql").write_text(stmt + "\n", encoding="utf-8")
    with_img = sum(1 for v in variants if v["image"])
    print(f"snapshot: {len(makes)} marche, {len(models)} modelli, {len(variants)} versioni "
          f"({with_img} con immagine), {SNAPSHOT.stat().st_size // 1000} KB · seed {len(stmts)} file")


if __name__ == "__main__":
    sys.exit(main())
