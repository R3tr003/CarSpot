#!/usr/bin/env python3
"""Prova di riconoscimento auto con SigLIP2 zero-shot (solo Mac, nessun codice dell'app).

Uso (dalla cartella tools/recognition-trial, con il venv attivo):
    .venv/bin/python evaluate.py run    --model base   --photos photos
    .venv/bin/python evaluate.py run    --model so400m --photos photos
    .venv/bin/python evaluate.py export --model base

Verità: `<photos>/truth.csv` (colonne file,make,model[,generation]) oppure nome file
`marca_modello_qualcosa.jpg` (gli spazi nei nomi diventano '-': `alfa-romeo_giulia_1.jpg`).
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import statistics
import time
import unicodedata
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
os.environ.setdefault("HF_HOME", str(HERE / ".cache"))

import numpy as np  # noqa: E402
import torch  # noqa: E402
from PIL import Image  # noqa: E402
from pillow_heif import register_heif_opener  # noqa: E402
from transformers import AutoModel, AutoProcessor  # noqa: E402

register_heif_opener()  # foto .heic dell'iPhone

MODELS = {
    "base": "google/siglip2-base-patch16-256",
    "so400m": "google/siglip2-so400m-patch14-384",
}

# Prompt ensemble (inglese). {n} = "Marca Modello" oppure "Marca Modello (anni)".
TEMPLATES = [
    "a photo of a {n}.",
    "a photo of a {n}, a type of car.",
    "a {n} parked on the street.",
    "a front view of a {n}.",
    "a rear view of a {n}.",
    "a side view of a {n} car.",
]

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".heic", ".webp"}


def slug(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def device() -> str:
    return "mps" if torch.backends.mps.is_available() else "cpu"


def load_labels() -> list[dict]:
    with open(HERE / "labels.csv", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def label_name(row: dict, level: str) -> str:
    base = f"{row['make']} {row['model']}"
    if level == "gen":
        return f"{base} ({row['years'].replace('-', '–')})"
    return base


def level_classes(labels: list[dict], level: str) -> list[dict]:
    """Classi del livello: 'gen' = una per riga; 'model' = una per marca+modello."""
    if level == "gen":
        return [dict(r, name=label_name(r, "gen")) for r in labels]
    seen: dict[tuple, dict] = {}
    for r in labels:
        seen.setdefault((r["make"], r["model"]), dict(r, name=label_name(r, "model"), generation="", years=""))
    return list(seen.values())


def load_model(key: str):
    name = MODELS[key]
    # so400m in fp32 (~4,5 GB) manda in swap un Mac da 8 GB: fp16 su MPS
    dtype = torch.float16 if key == "so400m" and device() == "mps" else torch.float32
    model = AutoModel.from_pretrained(name, torch_dtype=dtype).to(device()).eval()
    proc = AutoProcessor.from_pretrained(name)
    return model, proc


def _as_tensor(x):
    return x if isinstance(x, torch.Tensor) else x.pooler_output


@torch.no_grad()
def text_embeddings(model, proc, names: list[str]) -> np.ndarray:
    """Media dei prompt per etichetta, poi L2-normalizzata. Shape (N, D) float32."""
    out = []
    for n in names:
        texts = [t.format(n=n).lower() for t in TEMPLATES]  # SigLIP2 è addestrato su testo minuscolo
        inp = proc(text=texts, padding="max_length", max_length=64, truncation=True, return_tensors="pt").to(device())
        f = _as_tensor(model.get_text_features(**inp)).float()
        f = f / f.norm(dim=-1, keepdim=True)
        m = f.mean(0)
        out.append((m / m.norm()).cpu().numpy())
    return np.stack(out)


@torch.no_grad()
def image_embedding(model, proc, path: Path) -> tuple[np.ndarray, float]:
    """Embedding normalizzato + millisecondi (preprocess + encoder)."""
    img = Image.open(path).convert("RGB")
    t0 = time.perf_counter()
    inp = proc(images=img, return_tensors="pt").to(device())
    inp["pixel_values"] = inp["pixel_values"].to(model.dtype)
    f = _as_tensor(model.get_image_features(**inp)).float()
    if device() == "mps":
        torch.mps.synchronize()
    ms = (time.perf_counter() - t0) * 1000
    f = f / f.norm(dim=-1, keepdim=True)
    return f[0].cpu().numpy(), ms


def softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - x.max())
    return e / e.sum()


def read_truth(photos: Path) -> list[dict]:
    rows = []
    tcsv = photos / "truth.csv"
    if tcsv.exists():
        with open(tcsv, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                rows.append({"file": r["file"], "make": r["make"], "model": r["model"], "generation": r.get("generation", "") or ""})
        return rows
    for p in sorted(photos.iterdir()):
        if p.suffix.lower() in IMAGE_EXT:
            parts = p.stem.split("_")
            if len(parts) >= 2:
                rows.append({"file": p.name, "make": parts[0], "model": parts[1], "generation": ""})
    return rows


def topk_distinct(order: np.ndarray, probs_by_key: dict, k: int) -> list:
    return sorted(probs_by_key, key=lambda x: -probs_by_key[x])[:k]


def run(args) -> None:
    labels = load_labels()
    photos = Path(args.photos).resolve()
    truth = read_truth(photos)
    if not truth:
        raise SystemExit(f"Nessuna foto con verità in {photos}")
    model, proc = load_model(args.model)
    scale = float(model.logit_scale.detach().exp())
    print(f"modello {MODELS[args.model]} su {device()}, logit_scale={scale:.1f}")

    cls_gen = level_classes(labels, "gen")
    cls_mod = level_classes(labels, "model")
    t0 = time.perf_counter()
    T_gen = text_embeddings(model, proc, [c["name"] for c in cls_gen])
    T_mod = text_embeddings(model, proc, [c["name"] for c in cls_mod])
    print(f"testo: {len(cls_gen)}+{len(cls_mod)} etichette in {time.perf_counter()-t0:.1f}s")

    make_slugs = {slug(c["make"]): c["make"] for c in cls_mod}
    model_keys = {(slug(c["make"]), slug(c["model"])): (c["make"], c["model"]) for c in cls_mod}

    # warmup (non conteggiato nei tempi)
    first = photos / truth[0]["file"]
    image_embedding(model, proc, first)

    res, times, skipped = [], [], []
    for t in truth:
        tk = (slug(t["make"]), slug(t["model"]))
        if tk not in model_keys:
            skipped.append(t["file"])
            continue
        v, ms = image_embedding(model, proc, photos / t["file"])
        times.append(ms)
        # livello modello: softmax sulle classi marca+modello
        p_mod = softmax(scale * (T_mod @ v))
        by_model = {(c["make"], c["model"]): float(p) for c, p in zip(cls_mod, p_mod)}
        by_make = defaultdict(float)
        for (mk, _), p in by_model.items():
            by_make[mk] += p
        # livello generazione: softmax sulle classi con anni, poi aggregato per modello
        p_gen = softmax(scale * (T_gen @ v))
        by_model_g = defaultdict(float)
        for c, p in zip(cls_gen, p_gen):
            by_model_g[(c["make"], c["model"])] += float(p)
        top_gen = np.argsort(-p_gen)[:3]
        res.append({
            "file": t["file"], "truth": model_keys[tk], "truth_gen": t["generation"],
            "make3": topk_distinct(None, by_make, 3), "model3": topk_distinct(None, by_model, 3),
            "model3_g": topk_distinct(None, by_model_g, 3),
            "gen3": [(cls_gen[i]["make"], cls_gen[i]["model"], cls_gen[i]["generation"], float(p_gen[i])) for i in top_gen],
            "p_model": by_model, "p_make": dict(by_make), "ms": ms,
        })

    n = len(res)

    def acc(pred_key, truth_fn, k):
        return sum(truth_fn(r) in pred_key(r)[:k] for r in res) / n if n else float("nan")

    summary = {
        "model": MODELS[args.model], "device": device(), "n_images": n, "n_skipped_out_of_catalog": len(skipped),
        "make_top1": acc(lambda r: r["make3"], lambda r: r["truth"][0], 1),
        "make_top3": acc(lambda r: r["make3"], lambda r: r["truth"][0], 3),
        "model_top1": acc(lambda r: r["model3"], lambda r: r["truth"], 1),
        "model_top3": acc(lambda r: r["model3"], lambda r: r["truth"], 3),
        "model_top1_from_gen_prompts": acc(lambda r: r["model3_g"], lambda r: r["truth"], 1),
        "model_top3_from_gen_prompts": acc(lambda r: r["model3_g"], lambda r: r["truth"], 3),
        "ms_per_image_mean": statistics.mean(times) if times else None,
        "ms_per_image_median": statistics.median(times) if times else None,
        "catalog": {"generation_classes": len(cls_gen), "model_classes": len(cls_mod)},
    }
    with_gen = [r for r in res if r["truth_gen"]]
    if with_gen:
        hit = lambda r, k: any(r["truth"] == (g[0], g[1]) and slug(r["truth_gen"]) == slug(g[2]) for g in r["gen3"][:k])
        summary["gen_n"] = len(with_gen)
        summary["gen_top1"] = sum(hit(r, 1) for r in with_gen) / len(with_gen)
        summary["gen_top3"] = sum(hit(r, 3) for r in with_gen) / len(with_gen)

    # confidenza: top1 corretti vs sbagliati
    ok = [max(r["p_model"].values()) for r in res if r["model3"][0] == r["truth"]]
    ko = [max(r["p_model"].values()) for r in res if r["model3"][0] != r["truth"]]
    summary["conf_top1_mean_correct"] = statistics.mean(ok) if ok else None
    summary["conf_top1_mean_wrong"] = statistics.mean(ko) if ko else None

    # confusioni più frequenti (verità -> predetto sbagliato)
    conf = defaultdict(int)
    for r in res:
        if r["model3"][0] != r["truth"]:
            conf[(" ".join(r["truth"]), " ".join(r["model3"][0]))] += 1
    summary["top_confusions"] = [{"truth": a, "pred": b, "n": c} for (a, b), c in sorted(conf.items(), key=lambda x: -x[1])[:15]]

    outdir = HERE / "results"
    outdir.mkdir(exist_ok=True)
    tag = args.tag or args.model
    with open(outdir / f"predictions_{tag}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["file", "truth", "top1", "conf1", "top2", "top3", "top1_gen", "ms"])
        for r in res:
            m3 = r["model3"]
            w.writerow([r["file"], " ".join(r["truth"]), " ".join(m3[0]), f"{r['p_model'][m3[0]]:.3f}",
                        " ".join(m3[1]), " ".join(m3[2]),
                        f"{r['gen3'][0][0]} {r['gen3'][0][1]} {r['gen3'][0][2]}", f"{r['ms']:.0f}"])
    (outdir / f"summary_{tag}.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    if skipped:
        print("fuori catalogo (esclusi):", ", ".join(skipped))


def export(args) -> None:
    labels = load_labels()
    model, proc = load_model(args.model)
    out = HERE / "export" / args.model
    out.mkdir(parents=True, exist_ok=True)
    for level in ("gen", "model"):
        classes = level_classes(labels, level)
        T = text_embeddings(model, proc, [c["name"] for c in classes]).astype(np.float16)
        fname = f"label_embeddings_{level}.f16"
        T.tofile(out / fname)
        meta = {
            "model": MODELS[args.model], "level": level, "file": fname,
            "count": len(classes), "dim": int(T.shape[1]), "dtype": "float16", "layout": "row-major (count x dim), little-endian",
            "normalization": "ogni riga L2-normalizzata (poi arrotondata a float16); l'embedding immagine va normalizzato L2 prima del prodotto scalare",
            "logit_scale": float(model.logit_scale.detach().exp()), "logit_bias": float(model.logit_bias.detach()),
            "scoring": "p = softmax(logit_scale * cos) sulle classi; sigmoid(logit_scale*cos + logit_bias) per la confidenza assoluta",
            "templates": TEMPLATES,
            "labels": [
                {"index": i, "make": c["make"], "model": c["model"], "generation": c["generation"], "years": c["years"], "body": c["body"], "text": c["name"]}
                for i, c in enumerate(classes)
            ],
        }
        (out / f"labels_{level}.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False), encoding="utf-8")
        print(f"{out/fname}: {T.shape} {(out/fname).stat().st_size/1024:.0f} KB")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--model", choices=MODELS, default="base")
    r.add_argument("--photos", default="photos")
    r.add_argument("--tag", default="")
    r.set_defaults(fn=run)
    e = sub.add_parser("export")
    e.add_argument("--model", choices=MODELS, default="base")
    e.set_defaults(fn=export)
    a = ap.parse_args()
    a.fn(a)
