"""Prepara l'image encoder Core ML per l'app e lo verifica contro PyTorch.

    .venv/bin/python -I convert_coreml.py [--bits 8|16]

Parte dalla conversione di FluidInference (Apache-2.0, fp16): la conversione diretta con
coremltools 9 fallisce sul tracing di SigLIP2 (cast int di shape dinamiche). Con --bits 8
palettizza i pesi a 8 bit per dimezzare il peso dell'app.

Output: export/base/CarEncoder.mlpackage
  input  `pixel_values` (1, 3, 256, 256) float32: RGB ridimensionato 256×256 bilineare
         senza crop, poi (x/255 − 0.5)/0.5 — lo fa l'app
  output `image_embeds` (1, 768) float32, da L2-normalizzare
"""
import argparse
import csv
import shutil
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from huggingface_hub import snapshot_download
from PIL import Image
from transformers import AutoModel, AutoProcessor

HERE = Path(__file__).parent
NAME = "google/siglip2-base-patch16-256"
REPO = "FluidInference/siglip2-base-patch16-256-coreml"
PKG = "siglip2-base-patch16-256-image-fp16.mlpackage"
SIZE = 256


def pixels(img: Image.Image) -> np.ndarray:
    """Stesso preprocessing che farà l'app (vedi OnDeviceRecognitionService)."""
    a = np.asarray(img.convert("RGB").resize((SIZE, SIZE), Image.BILINEAR), dtype=np.float32)
    return ((a / 255.0 - 0.5) / 0.5).transpose(2, 0, 1)[None]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bits", type=int, choices=[8, 16], default=8)
    args = ap.parse_args()

    src = Path(snapshot_download(REPO, allow_patterns=[f"{PKG}/*", "config.json"], cache_dir=HERE / ".cache")) / PKG
    out = HERE / "export" / "base" / "CarEncoder.mlpackage"
    if out.exists():
        shutil.rmtree(out)
    # La cache HF usa symlink in sola lettura: Core ML non li compila, quindi copia vera.
    shutil.copytree(src, out)
    for f in out.rglob("*"):
        f.chmod(0o755 if f.is_dir() else 0o644)
    ml = ct.models.MLModel(str(out))
    if args.bits == 8:
        # Palette k-means per tensore: 93 MB, coseno ≥ 0,996. L'int8 lineare per canale
        # scende a 0,90; le granularità più fini richiedono una spec iOS 18 che il modello non ha.
        cfg = ct.optimize.coreml.OptimizationConfig(
            global_config=ct.optimize.coreml.OpPalettizerConfig(nbits=8, mode="kmeans", granularity="per_tensor"))
        ml = ct.optimize.coreml.palettize_weights(ml, cfg)
        shutil.rmtree(out)
        ml.save(str(out))
        ml = ct.models.MLModel(str(out))

    # Verifica: Core ML (preprocessing dell'app) vs PyTorch fp32 (processor HF).
    model = AutoModel.from_pretrained(NAME, torch_dtype=torch.float32).eval()
    proc = AutoProcessor.from_pretrained(NAME)
    rows = list(csv.DictReader(open(HERE / "samples" / "truth.csv", encoding="utf-8")))[:20]
    cos = []
    for r in rows:
        img = Image.open(HERE / "samples" / r["file"]).convert("RGB")
        with torch.no_grad():
            f = model.get_image_features(**proc(images=img, return_tensors="pt"))
            ref = (f if isinstance(f, torch.Tensor) else f.pooler_output)[0].numpy()
        got = np.asarray(ml.predict({"pixel_values": pixels(img)})["image_embeds"]).reshape(-1)
        cos.append(float(ref @ got / np.linalg.norm(ref) / np.linalg.norm(got)))
    size = sum(f.stat().st_size for f in out.rglob("*") if f.is_file()) / 1e6
    print(f"{out.name}: {size:.0f} MB, {args.bits} bit · coseno vs PyTorch min {min(cos):.4f} media {np.mean(cos):.4f}")
    assert min(cos) > 0.98, "Core ML diverge da PyTorch"


if __name__ == "__main__":
    main()
