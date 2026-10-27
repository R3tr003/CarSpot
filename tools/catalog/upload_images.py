"""Passo 6: carica le immagini WebP nel bucket pubblico `car-models`.

Serve la chiave service role, che solo l'utente può mettere nel suo terminale (vedi upload-wizard.sh):
    export SUPABASE_URL=https://rdezjqbxqekteextolvh.supabase.co
    export SUPABASE_SERVICE_ROLE_KEY=...
La chiave non viene mai scritta su disco né stampata. Salta i file già caricati (x-upsert false → 409).
"""
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # solo i moduli della pipeline
from catalog_common import OUT, read_json


def main() -> int:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        print("Mancano SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY nell'ambiente.")
        return 1
    manifest = read_json(OUT / "images_manifest.json")
    ok = skipped = failed = 0
    for i, entry in enumerate(manifest.values(), 1):
        src = OUT / "images" / entry["path"]
        # La chiave passa a curl da stdin (-K -), così non compare nella lista dei processi.
        config = (f'header = "Authorization: Bearer {key}"\nheader = "apikey: {key}"\n'
                  f'header = "Content-Type: image/webp"\nheader = "x-upsert: false"\n')
        proc = subprocess.run(
            ["curl", "-sS", "-K", "-", "-X", "POST", "--data-binary", f"@{src}", "-o", "/dev/null",
             "-w", "%{http_code}", f"{url}/storage/v1/object/car-models/{entry['path']}"],
            input=config, capture_output=True, text=True)
        code = proc.stdout.strip()
        if code in ("200", "201"):
            ok += 1
        elif code in ("409", "400") and "exists" in (proc.stderr or "") or code == "409":
            skipped += 1
        else:
            failed += 1
            print(f"  errore {code} su {entry['path']}")
        if i % 200 == 0:
            print(f"  {i}/{len(manifest)} · caricate {ok} · già presenti {skipped} · errori {failed}", flush=True)
    print(f"fatto: caricate {ok}, già presenti {skipped}, errori {failed}")
    return 0 if failed == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
