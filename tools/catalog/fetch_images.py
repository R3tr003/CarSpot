"""Passo 3: attribuzione e download delle immagini di Commons per le versioni del catalogo.

Ingresso: out/catalog.json. Uscita: out/raw/<variant_id>.<ext>, out/attribution.json, out/rejected.json.
Riprende da dove si era fermato. Uso: python3 -I fetch_images.py [--limit N]
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # solo i moduli della pipeline
from catalog_common import COMMONS_API, OUT, download, http_get, read_json, write_json

ALLOWED = re.compile(r"^(public domain|pd\b|pd-|cc0|cc[- ]zero|cc by(-sa)?(\s|-|$))", re.IGNORECASE)
TAG = re.compile(r"<[^>]+>")


def clean_html(value: str) -> str:
    text = html.unescape(TAG.sub("", value or ""))
    return " ".join(text.split())[:200]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    catalog = read_json(OUT / "catalog.json")
    wanted = [(v["id"], urllib.parse.unquote(v["commonsFile"]))
              for v in catalog["variants"] if v.get("commonsFile")]
    # Prima le versioni dei modelli più noti: se la corsa si ferma, il meglio c'è già.
    popularity = {m["id"]: m["popularity"] for m in catalog["models"]}
    model_of = {v["id"]: v["modelId"] for v in catalog["variants"]}
    wanted.sort(key=lambda w: -popularity.get(model_of[w[0]], 0))
    if args.limit:
        wanted = wanted[:args.limit]

    attr_path, rej_path = OUT / "attribution.json", OUT / "rejected.json"
    attribution = read_json(attr_path) if attr_path.exists() else {}
    rejected = read_json(rej_path) if rej_path.exists() else {}
    raw_dir = OUT / "raw"
    todo = [w for w in wanted if w[0] not in attribution and w[0] not in rejected]
    print(f"{len(wanted)} immagini, {len(todo)} da fare", flush=True)

    for i in range(0, len(todo), 50):
        chunk = todo[i:i + 50]
        titles = {"File:" + name: vid for vid, name in chunk}
        data = json.loads(http_get(COMMONS_API, {
            "action": "query", "format": "json", "prop": "imageinfo", "iiprop": "url|extmetadata",
            "iiurlwidth": "960", "titles": "|".join(titles)}))
        norm = {n["to"]: n["from"] for n in data["query"].get("normalized", [])}
        for page in data["query"]["pages"].values():
            title = page["title"]
            vid = titles.get(norm.get(title, title)) or titles.get(title)
            if not vid:
                continue
            info = (page.get("imageinfo") or [None])[0]
            if not info:
                rejected[vid] = "file non trovato"
                continue
            meta = info.get("extmetadata", {})
            lic = clean_html(meta.get("LicenseShortName", {}).get("value", ""))
            if not ALLOWED.match(lic):
                rejected[vid] = f"licenza non ammessa: {lic or '?'}"
                continue
            url = info.get("thumburl") or info["url"]
            ext = Path(urllib.parse.urlparse(url).path).suffix.lower() or ".jpg"
            status = download(url, raw_dir / f"{vid}{ext}")
            if status != 200:
                rejected[vid] = f"download HTTP {status}"
                (raw_dir / f"{vid}{ext}").unlink(missing_ok=True)
                continue
            attribution[vid] = {
                "title": title,
                "author": clean_html(meta.get("Artist", {}).get("value", "")) or "Autore sconosciuto",
                "license": lic,
                "licenseURL": meta.get("LicenseUrl", {}).get("value") or None,
                "sourceURL": info.get("descriptionurl"),
                "file": f"{vid}{ext}",
            }
            time.sleep(1.0)  # ritmo educato verso upload.wikimedia.org
        write_json(attr_path, attribution)
        write_json(rej_path, rejected)
        print(f"  {min(i + 50, len(todo))}/{len(todo)} · ok {len(attribution)} · scartate {len(rejected)}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
