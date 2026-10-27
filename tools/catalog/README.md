# Pipeline del catalogo (prova)

Costruisce il catalogo Marca → Modello → Versione della Collezione album da Wikidata, con immagini
libere di Wikimedia Commons scontornate. Design: `docs/superpowers/specs/2026-10-25-catalog-album-design.md`,
ADR `docs/adr/0001-catalogo-modelli.md`. Tutto l'output va in `out/` (ignorato da git).

```bash
python3 -I tools/catalog/test_catalog.py      # regole pure
python3 -I tools/catalog/fetch_wikidata.py    # 1. grezzo Wikidata (incrementale)
python3 -I tools/catalog/build_catalog.py     # 2. out/catalog.json + out/build_report.md
python3 -I tools/catalog/fetch_images.py      # 3. attribuzione + download (≤ 1/s, riprende)
python3 -I tools/catalog/process_images.py    # 4. scontorno Vision + targhe + WebP
python3 -I tools/catalog/export.py            # 5. snapshot dell'app, out/labels.csv, out/seed/*.sql
tools/catalog/upload-wizard.sh                # 6. dati (seed_data.py) + immagini nel bucket, con la chiave service role dell'utente
```

- Correzioni a mano in `curated/`: `variants.csv` (versioni; `=Nome` = nome completo, es. `=GR Yaris`),
  `make_aliases.csv`, `make_merge.csv` (unisce o esclude marche, `to` vuoto = esclusa), `exclude.csv`
  (qid da scartare).
- Licenze ammesse: pubblico dominio, CC0, CC BY, CC BY-SA. Le immagini sono modificate (scontorno, targhe
  sfocate): l'attribuzione nell'app lo dice.
- Il seed SQL si applica su Supabase dopo la migration 0010; `out/labels.csv` è la lista di etichette per il
  riconoscimento.
- Limiti noti: anni e carrozzerie da Wikidata sono incompleti (circa metà dei modelli senza anno); qualche
  targa piccola o storta sfugge all'OCR; nelle foto con più auto resta la più grande.
