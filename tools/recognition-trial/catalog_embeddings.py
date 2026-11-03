"""Embedding per TUTTI i modelli del catalogo dell'app (catalog-snapshot.json) e misura.

    .venv/bin/python -I catalog_embeddings.py build      # testo + prototipi immagine → export/catalog/
    .venv/bin/python -I catalog_embeddings.py measure    # accuratezza su samples/degraded/stanford
    .venv/bin/python -I catalog_embeddings.py export-app # file per l'app (solo testo) → CarSpot/…/Resources

Due matrici, una riga per modello del catalogo (stesso ordine di `models.json`):
- `text.f16`  : media dei prompt "a photo of a {marca} {modello}." (text encoder PyTorch)
- `image.f16` : media degli embedding delle immagini standard delle versioni (encoder Core ML
                dell'app), righe a zero se il modello non ha immagini
Le immagini delle foto da misurare passano dallo stesso encoder Core ML che va nell'app.
"""
import argparse
import csv
import json
import shutil
import ssl
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import certifi  # noqa: E402
import coremltools as ct  # noqa: E402
import numpy as np  # noqa: E402
import torch  # noqa: E402
from PIL import Image  # noqa: E402

from convert_coreml import pixels  # noqa: E402
from evaluate import load_model, slug, text_embeddings  # noqa: E402

SNAPSHOT = HERE.parent.parent / "CarSpot" / "Services" / "Catalog" / "Resources" / "catalog-snapshot.json"
OUT = HERE / "export" / "catalog"
IMAGES = HERE / ".cache" / "catalog-images"
ENCODER = HERE / "export" / "base" / "CarEncoder.mlpackage"


def load_catalog():
    s = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    makes = {m["id"]: m for m in s["makes"]}
    return s, makes, s["models"]


def encoder():
    return ct.models.MLModel(str(ENCODER))


def embed(ml, path: Path) -> np.ndarray:
    v = np.asarray(ml.predict({"pixel_values": pixels(Image.open(path))})["image_embeds"]).reshape(-1)
    return v / np.linalg.norm(v)


def fetch(url: str, dest: Path) -> Path | None:
    if dest.exists():
        return dest
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        ctx = ssl.create_default_context(cafile=certifi.where())  # il Python del venv non ha i certificati di sistema
        with urllib.request.urlopen(url, timeout=30, context=ctx) as r:
            dest.write_bytes(r.read())
        return dest
    except Exception as e:  # immagine mancante: il modello resta solo testo
        print("skip", url, e)
        return None


@torch.no_grad()
def build(_args) -> None:
    snap, makes, models = load_catalog()
    OUT.mkdir(parents=True, exist_ok=True)

    names = [f"{makes[m['makeId']]['name']} {m['name']}" for m in models]
    model, proc = load_model("base")
    T = text_embeddings(model, proc, names)
    print("testo:", T.shape)

    # Prototipi: immagini standard delle versioni (Storage pubblico), raggruppate per modello.
    by_model: dict[str, list[str]] = {}
    for v in snap["variants"]:
        if v.get("image"):
            by_model.setdefault(v["modelId"], []).append(v["image"]["path"])
    jobs = [(p, IMAGES / p) for paths in by_model.values() for p in paths]
    with ThreadPoolExecutor(8) as ex:
        list(ex.map(lambda j: fetch(snap["imageBaseURL"] + j[0], j[1]), jobs))
    ml = encoder()
    I = np.zeros_like(T)
    for i, m in enumerate(models):
        vs = [embed(ml, IMAGES / p) for p in by_model.get(m["id"], []) if (IMAGES / p).exists()]
        if vs:
            v = np.mean(vs, 0)
            I[i] = v / np.linalg.norm(v)
    print("prototipi:", int((np.abs(I).sum(1) > 0).sum()), "modelli con immagine su", len(models))

    T.astype(np.float16).tofile(OUT / "text.f16")
    I.astype(np.float16).tofile(OUT / "image.f16")
    meta = {
        "catalogVersion": snap["version"], "count": len(models), "dim": int(T.shape[1]),
        "logitScale": float(model.logit_scale.exp()), "logitBias": float(model.logit_bias),
        "modelIds": [m["id"] for m in models],
    }
    (OUT / "models.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    print("→", OUT)


def families(models) -> list[int]:
    """Indice della "famiglia" di ogni modello: il modello della stessa marca col nome più corto
    di cui questo è il nome intero o un prefisso ("A5 8T" → "A5"). Il catalogo divide spesso le
    generazioni in modelli separati: in classifica contano come una sola auto."""
    by_make: dict[str, list[int]] = {}
    for i, m in enumerate(models):
        by_make.setdefault(m["makeId"], []).append(i)
    fam = list(range(len(models)))
    for idx in by_make.values():
        names = {i: slug(models[i]["name"]) for i in idx}
        for i in idx:
            roots = [j for j in idx if names[i] == names[j] or names[i].startswith(names[j] + "-")]
            fam[i] = min(roots, key=lambda j: (len(names[j]), -models[j]["popularity"], j))
    return fam


def ranked(p: np.ndarray, fam: list[int], k: int = 3) -> list[tuple[int, float]]:
    """Top-k per famiglia: probabilità sommate, rappresentante = il modello più probabile."""
    tot: dict[int, float] = {}
    best: dict[int, int] = {}
    for i in np.argsort(-p)[:50]:
        f = fam[i]
        tot[f] = tot.get(f, 0.0) + float(p[i])
        best.setdefault(f, int(i))
    return sorted(((best[f], t) for f, t in tot.items()), key=lambda x: -x[1])[:k]


def truth_ids(models, makes) -> dict[tuple[str, str], set[str]]:
    """(slug marca, slug modello) → id del catalogo che lo rappresentano (nome o alias)."""
    out: dict[tuple[str, str], set[str]] = {}
    for m in models:
        mk = slug(makes[m["makeId"]]["name"])
        for n in [m["name"]] + m["aliases"]:
            out.setdefault((mk, slug(n)), set()).add(m["id"])
    return out


def scores(T, I, e, w: float, scale: float, prior: np.ndarray, beta: float) -> np.ndarray:
    """Logit: testo (scala del modello) + w × somiglianza ai prototipi + β × log(popolarità)."""
    return scale * (T @ e) + w * scale * (I @ e) + beta * prior


def leaked() -> set[str]:
    """Foto di prova Commons che sono anche immagini standard del catalogo: falserebbero i prototipi."""
    snap, _, _ = load_catalog()
    src = {v["image"]["title"] for v in snap["variants"] if v.get("image")}
    rows = csv.DictReader(open(HERE / "samples" / "LICENSES.csv", encoding="utf-8"))
    return {r["file"] for r in rows if r["title"] in src}


def measure(args) -> None:
    _, makes, models = load_catalog()
    skip = leaked()
    meta = json.loads((OUT / "models.json").read_text())
    T = np.fromfile(OUT / "text.f16", dtype=np.float16).astype(np.float32).reshape(meta["count"], meta["dim"])
    I = np.fromfile(OUT / "image.f16", dtype=np.float16).astype(np.float32).reshape(meta["count"], meta["dim"])
    lookup = truth_ids(models, makes)
    fam = families(models)
    index = {mid: i for i, mid in enumerate(meta["modelIds"])}
    prior = np.log1p(np.array([m["popularity"] for m in models], dtype=np.float32))
    ml = encoder()
    for folder in args.sets:
        rows = list(csv.DictReader(open(HERE / folder / "truth.csv", encoding="utf-8")))[: args.limit]
        data, missing = [], set()
        for r in rows:
            if r["file"] in skip:
                continue
            ids = lookup.get((slug(r["make"]), slug(r["model"].split(" (")[0])))
            if not ids:
                missing.add(f"{r['make']} {r['model']}")
                continue
            data.append((embed(ml, HERE / folder / r["file"]), ids))
        print(f"\n{folder}: {len(data)} foto (fuori catalogo: {sorted(missing) or 'nessuna'})")
        for w in args.weights:
            for beta in args.betas:
                top1 = top3 = mk1 = 0
                confs = []
                for e, ids in data:
                    fams = {fam[index[i]] for i in ids}
                    s = scores(T, I, e, w, meta["logitScale"], prior, beta)
                    p = np.exp(s - s.max()); p /= p.sum()
                    top = ranked(p, fam)
                    ok1 = fam[top[0][0]] in fams
                    top1 += ok1; top3 += any(fam[i] in fams for i, _ in top)
                    mk1 += models[top[0][0]]["makeId"] in {models[index[i]]["makeId"] for i in ids}
                    confs.append((top[0][1], ok1))
                n = len(data)
                hi = [ok for c, ok in confs if c >= 0.7]
                lo = [ok for c, ok in confs if c < 0.5]
                print(f"  w={w:<4} β={beta:<4} marca {mk1/n:.1%} · modello top1 {top1/n:.1%} top3 {top3/n:.1%}"
                      f" · conf≥0,7: {len(hi)/n:.0%} tenute {sum(hi)/max(1,len(hi)):.0%} giuste"
                      f" · conf<0,5: {len(lo)/n:.0%}")


APP = HERE.parent.parent / "CarSpot" / "Services" / "Recognition" / "Resources"
# Scelti con `measure` (2026-11-03): i prototipi immagine peggiorano (w=0), il peso della
# popolarità aiuta senza schiacciare i modelli rari (β=2; 3+ non provato per non adattarsi a 76 foto).
APP_BETA = 2.0


def export_app(_args) -> None:
    """Scrive nel bundle dell'app la matrice testo e le etichette (con famiglia e popolarità)."""
    _, makes, models = load_catalog()
    meta = json.loads((OUT / "models.json").read_text())
    assert meta["modelIds"] == [m["id"] for m in models], "export/catalog non allineato allo snapshot: rifai build"
    APP.mkdir(parents=True, exist_ok=True)
    (APP / "car-embeddings.f16").write_bytes((OUT / "text.f16").read_bytes())
    # Encoder (93 MB, gitignorato: si rigenera con convert_coreml.py). Senza, l'app usa il mock.
    shutil.rmtree(APP / ENCODER.name, ignore_errors=True)
    shutil.copytree(ENCODER, APP / ENCODER.name)
    fam = families(models)
    labels = {
        "catalogVersion": meta["catalogVersion"], "dim": meta["dim"], "logitScale": meta["logitScale"],
        "popularityWeight": APP_BETA,
        "models": [{"id": m["id"], "make": makes[m["makeId"]]["name"], "model": m["name"],
                    "family": fam[i], "popularity": m["popularity"],
                    "yearStart": m["yearStart"], "yearEnd": m["yearEnd"]} for i, m in enumerate(models)],
    }
    (APP / "car-labels.json").write_text(json.dumps(labels, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("→", APP, [f.name for f in APP.iterdir()])


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("build").set_defaults(fn=build)
    m = sub.add_parser("measure")
    m.add_argument("--sets", nargs="+", default=["samples", "degraded", "stanford"])
    m.add_argument("--weights", nargs="+", type=float, default=[0.0, 0.25])
    m.add_argument("--betas", nargs="+", type=float, default=[0.0, 1.0, 2.0])
    m.add_argument("--limit", type=int, default=400)
    m.set_defaults(fn=measure)
    sub.add_parser("export-app").set_defaults(fn=export_app)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
