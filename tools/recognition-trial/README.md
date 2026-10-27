# Prova riconoscimento auto (SigLIP2 zero-shot) — solo Mac

Misura quanto bene SigLIP2 riconosce marca/modello confrontando la foto con etichette
testuali ("a photo of a Fiat Panda (2012–present)"). **Non tocca l'app.** Risultati in
[REPORT.md](REPORT.md).

## Foto tue (cartella `photos/`, ignorata da git)

Metti 30–50 foto scattate in strada in `tools/recognition-trial/photos/` e dimmi come le hai
etichettate. Due modi:

1. **Nome file** `marca_modello_qualcosa.jpg`: marca e modello come in `labels.csv`, spazi →
   trattino, minuscolo (`fiat_panda_01.jpg`, `alfa-romeo_giulia_roma.jpg`,
   `mercedes-benz_classe-a_2.jpg`).
2. **`photos/truth.csv`** con colonne `file,make,model[,generation]` (es.
   `IMG_1234.jpg,Fiat,Panda,III (319)`). Più comodo se i nomi sono già `IMG_xxxx`.

Foto `.heic` dell'iPhone vanno bene. Se un modello non è in `labels.csv` la foto viene esclusa
dai conteggi e segnalata ("fuori catalogo").

## Comandi

```bash
cd tools/recognition-trial
.venv/bin/python -I evaluate.py run --model base   --photos photos     # SigLIP2 base 256
.venv/bin/python -I evaluate.py run --model so400m --photos photos     # SigLIP2 so400m 384
.venv/bin/python -I evaluate.py export --model base                    # embedding per l'app → export/base/
```

Output: `results/summary_<tag>.json`, `results/predictions_<tag>.csv`.
`fetch_samples.py` scarica immagini di prova da Wikimedia Commons in `samples/` (solo licenze
libere, vedi `samples/LICENSES.csv`).

Setup venv: `python3 -m venv .venv && .venv/bin/pip install torch transformers pillow numpy
huggingface_hub sentencepiece protobuf accelerate certifi pillow-heif`. I modelli finiscono in `.cache/`.
