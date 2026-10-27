"""Passo 6a: carica marche, modelli e versioni nelle tabelle del catalogo (upsert via REST).

Legge lo snapshot dell'app (stessi dati) e usa la chiave service role dall'ambiente, come
upload_images.py. Idempotente: rilanciarlo aggiorna le righe esistenti.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # solo i moduli della pipeline
from export import SNAPSHOT  # noqa: E402

BATCH = 500


def rows(snapshot: dict) -> list[tuple[str, list[dict]]]:
    makes = [{"id": m["id"], "name": m["name"], "country": m.get("country"), "aliases": m["aliases"],
              "deleted_at": None} for m in snapshot["makes"]]
    models = [{"id": m["id"], "make_id": m["makeId"], "name": m["name"], "body_type": m["bodyType"],
               "year_start": m["yearStart"], "year_end": m["yearEnd"], "popularity": m["popularity"],
               "aliases": m["aliases"], "deleted_at": None} for m in snapshot["models"]]
    variants = []
    for v in snapshot["variants"]:
        img = v.get("image") or {}
        variants.append({"id": v["id"], "model_id": v["modelId"], "name": v["name"], "is_base": v["isBase"],
                         "year_start": v["yearStart"], "year_end": v["yearEnd"], "aliases": v["aliases"],
                         "image_path": img.get("path"), "image_width": img.get("width"),
                         "image_height": img.get("height"), "image_title": img.get("title"),
                         "image_author": img.get("author"), "image_license": img.get("license"),
                         "image_license_url": img.get("licenseURL"), "image_source_url": img.get("sourceURL"),
                         "image_modified": bool(img), "deleted_at": None})
    return [("car_makes", makes), ("car_models", models), ("car_variants", variants)]


def main() -> int:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        print("Mancano SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY nell'ambiente.")
        return 1
    snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    # La chiave passa a curl da stdin (-K -), mai sulla riga di comando.
    config = (f'header = "Authorization: Bearer {key}"\nheader = "apikey: {key}"\n'
              'header = "Content-Type: application/json"\n'
              'header = "Prefer: resolution=merge-duplicates,return=minimal"\n')
    for table, data in rows(snapshot):
        for i in range(0, len(data), BATCH):
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
                json.dump(data[i:i + BATCH], f, ensure_ascii=False)
                body = f.name
            proc = subprocess.run(
                ["curl", "-sS", "-K", "-", "-X", "POST", "--data-binary", f"@{body}",
                 "-w", "\n%{http_code}", f"{url}/rest/v1/{table}?on_conflict=id"],
                input=config, capture_output=True, text=True)
            Path(body).unlink(missing_ok=True)
            out, _, code = proc.stdout.rpartition("\n")
            if code not in ("200", "201", "204"):
                print(f"  errore {code} su {table} (blocco {i // BATCH + 1}): {out[:300]}")
                return 2
        print(f"  {table}: {len(data)} righe", flush=True)
    print("dati del catalogo caricati")
    return 0


if __name__ == "__main__":
    sys.exit(main())
