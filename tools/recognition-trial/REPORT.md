# Prova riconoscimento auto — SigLIP2 zero-shot (Mac)

Data: 2026-10-25 · Mac arm64 con 8 GB di RAM, PyTorch su MPS · nessun codice dell'app toccato.

> ## ⚠️ I numeri qui sotto NON sono sulle foto dell'utente
> Sono misurati su **76 foto di Wikimedia Commons** (licenze libere, 38 modelli, 2 foto per modello;
> elenco e licenze in `samples/LICENSES.csv`, cartella ignorata da git). Sono per lo più foto da
> saloni, parcheggi e fotografi appassionati: auto pulite, ben inquadrate, spesso di 3/4 anteriore.
> Alcune potrebbero stare nei dati di addestramento di SigLIP2 (web-scale). Quindi **sono una stima
> ottimistica** di ciò che succede con foto scattate in strada. Quando arrivano le foto vere:
> `evaluate.py run --model base --photos photos` e questa tabella va rifatta (vedi README).

## Setup

- Modelli: `google/siglip2-base-patch16-256` (input 256 px, embedding 768-d) e
  `google/siglip2-so400m-patch14-384` (384 px, embedding 1152-d); Apache-2.0.
- Catalogo: `labels.csv` = **304 righe** (generazioni) = **235 modelli** di **47 marche**
  (più del "~150" richiesto: il test è quindi più duro, con tanti quasi-doppioni —
  Panda/Grande Panda, 208/2008, T-Roc/T-Cross, Octavia/Scala/Kamiq…). Anni = indicativi, scritti
  a mano, non verificati su fonti: servono come testo del prompt, non come dato.
- Prompt ensemble (6 frasi in inglese per etichetta, minuscolo): "a photo of a {n}.", "… , a type of
  car.", "a {n} parked on the street.", "a front view of …", "a rear view of …", "a side view of … car."
  Embedding di testo mediati e rinormalizzati; coseno immagine·testo; `softmax(logit_scale·cos)`.
- Due livelli di etichetta: **modello** (`Fiat Panda`) e **generazione** (`Fiat Panda (2012–present)`,
  poi le probabilità sommate per modello).
- so400m girato in fp16 (in fp32 non entrava nella RAM: swap); base in fp32.

## Risultati (76 foto Commons, 235 classi modello)

| | base 256 | so400m 384 |
|---|---:|---:|
| Marca top-1 | 93,4 % | 96,1 % |
| Marca top-3 | 98,7 % | 98,7 % |
| Modello top-1 (prompt "marca modello") | 77,6 % | 82,9 % |
| Modello top-3 | 93,4 % | 98,7 % |
| Modello top-1 (prompt con anni, somma per modello) | 85,5 % | 90,8 % |
| Modello top-3 (prompt con anni) | 90,8 % | 97,4 % |
| Confidenza media top-1 corretti / sbagliati | 0,87 / 0,44 | 0,92 / 0,57 |
| Tempo/immagine (mediana, MPS, incl. preprocess) | 49 ms | 402 ms* |
| Embedding dim | 768 | 1152 |

\* so400m misurato con il Mac in pressione di memoria (swap, altre sessioni aperte): il numero è
rumoroso, l'ordine di grandezza (~8×) è plausibile ma non preciso. I tempi PyTorch su Mac **non**
dicono nulla sull'iPhone.

Accuratezza per soglia di confidenza (top-1 modello, prompt "marca modello"):

| confidenza ≥ | base: foto tenute → corrette | so400m: foto tenute → corrette |
|---|---:|---:|
| 0 | 76 → 78 % | 76 → 83 % |
| 0,5 | 61 → 89 % | 68 → 87 % |
| 0,7 | 51 → 98 % | 59 → 95 % |
| 0,9 | 37 → 100 % | 54 → 96 % |

Nota sui prompt con anni: la sommatoria per generazione dà +8 punti, ma in parte è un artefatto —
i modelli con più generazioni nel catalogo (Golf, 911, Panda) raccolgono più massa di probabilità.
Non va letto come "gli anni aiutano l'immagine". I **generazione top-1/3 non sono misurati**: le
foto Commons non hanno la generazione nella verità (le query non la garantiscono).

### Errori tipici

- **Modelli vicini della stessa marca** (la maggior parte): Panda → Grande Panda (2 foto, entrambi
  i modelli), Octavia → Kamiq/Scala (la Octavia è una wagon, il catalogo ha SUV simili), 208 → 2008/207,
  T-Roc → T-Cross, Duster → Jogger, C3 → C3 Aircross, Audi A3 → A1, Serie 3 → M3, Model 3 → Model Y,
  Giulietta → Junior/Alfasud, 500 → 600/Cinquecento. Quasi tutti hanno il modello giusto nel top-3.
- **Foto atipiche**: due Ford Fiesta (con so400m scambiate per BYD Dolphin, una con confidenza 0,98: foto poco
  rappresentativa o verità dubbia, non ho controllato a occhio ogni immagine) e una Golf
  con poca confidenza (0,06) → il filtro per confidenza funziona.
- **Generazioni**: non misurate; ci si aspetta che sia la parte più debole (Golf 7 vs 8, Clio IV vs V),
  perché il testo "(anni)" dice poco a un modello visivo.
- Le auto d'epoca (500 Nuova, Ape) sono andate bene; c'è però solo una foto per ciascuna.

## Raccomandazione

1. **Base, non so400m.** Per l'iPhone conta il peso: l'image encoder base è già convertito in Core ML
   (FluidInference, 176 MB fp16, Apache-2.0; dichiarano ~5 ms su ANE su un M5 Pro e embedding
   identici al PyTorch con coseno medio 0,9999 — **cifre loro, non verificate da me**). so400m guadagna
   ~5 punti top-1 e ~5 su top-3, ma ha un encoder da stimare in ~0,8–0,9 GB fp16 (non convertito, stima
   mia), 1152-d, e sul Mac è ~8× più lento.
2. **Procedere sì, ma come "suggerimento + conferma"**: mostrare top-3 e far scegliere all'utente; con
   soglia 0,7 si salta la conferma sul ~2/3 delle foto con ~98 % di correttezza (su queste foto
   facili). Marca quasi sempre giusta (93 %); il collo di bottiglia sono i modelli vicini e le generazioni.
3. **Decisione finale solo dopo le foto vere**: se top-1 modello su foto di strada scende sotto ~60 %,
   passare ai miglioramenti sotto prima di cablare l'app.
4. Il testo non serve sul telefono: si spediscono gli embedding delle etichette già calcolati
   (0,35–0,7 MB), e sul device gira solo l'image encoder. Ogni modello nuovo si aggiunge rieseguendo
   `evaluate.py export` (il tokenizer/text encoder non entrano nell'app).

## Cosa servirebbe per migliorare

- **Più prompt / alias**: nomi italiani e commerciali ("Panda 4x4", "500 Abarth", sigle di
  piattaforma), descrizioni di carrozzeria ("a small italian city car"); costa solo testo.
- **Prototipi immagine**: 3–10 foto di riferimento per modello/generazione → media degli embedding
  immagine (rinormalizzata) combinata con il testo (`cos_testo + λ·cos_prototipo`). È il rimedio più
  efficace per le generazioni e per i quasi-doppioni, senza addestrare nulla; le carte già raccolte
  dagli utenti (con conferma) possono alimentare i prototipi nel tempo.
- **Fine-tune leggero**: una linear probe / adapter sugli embedding immagine (non sul backbone) con
  poche decine di foto per classe; resta compatibile con l'encoder Core ML.
- **Gerarchia**: decidere prima la marca (93–96 %), poi il modello solo fra i modelli di quella marca;
  taglia gli errori "Fiesta → BYD".
- **Soglia "non è un'auto/non lo so"**: usare la `sigmoid(scale·cos + bias)` assoluta per rifiutare
  foto senza auto o modelli fuori catalogo (non misurata qui).

## File prodotti (`tools/recognition-trial/`)

| File | Contenuto |
|---|---|
| `labels.csv` | catalogo: make, model, generation, years, body (304 righe) |
| `evaluate.py` | `run` (valutazione, tempi) / `export` (embedding per l'app) |
| `fetch_samples.py` | scarica le foto Commons (licenze libere) in `samples/` |
| `results/` | `summary_*.json`, `predictions_*.csv` per ogni run |
| `export/base/` | `label_embeddings_gen.f16` 456 KB (304×768) · `label_embeddings_model.f16` 352 KB (235×768) · `labels_gen.json` 55 KB · `labels_model.json` 36 KB |
| `export/so400m/` | `label_embeddings_gen.f16` 684 KB (304×1152) · `label_embeddings_model.f16` 529 KB (235×1152) · json come sopra |

Gitignorati: `.venv/` (942 MB), `.cache/` (5,7 GB modelli), `samples/` (22 MB), `photos/`.

### Formato dell'export per l'app

- `label_embeddings_*.f16`: float16 little-endian, row-major, `count × dim`, **nessun header**.
- Ogni riga **L2-normalizzata** (poi arrotondata a f16: errore ~1e-3, trascurabile). L'embedding
  dell'immagine dal Core ML è già normalizzato; in ogni caso normalizzarlo prima del prodotto scalare.
- `labels_*.json`: stesso ordine delle righe (`labels[i]` ↔ riga `i`) con make, model, generation,
  years, body, testo usato; più `dim`, `logit_scale` (base 112,90 · so400m 109,9), `logit_bias` (base
  −16,77 · so400m −15,93), i template e le istruzioni di scoring: `p = softmax(logit_scale · cos)`; confidenza assoluta
  `sigmoid(logit_scale·cos + logit_bias)`.
- Gli embedding sono calcolati con il text encoder **PyTorch fp32** di `google/siglip2-base-patch16-256`
  (base) — stesso spazio dell'image encoder Core ML base; **non vanno mescolati con so400m**.
- Preprocessing immagine (da `config.json` del repo Core ML): resize 256×256 bilineare, [0,1], poi
  `(x−0.5)/0.5`.

### Cosa NON è stato verificato

- Nessun numero su foto vere dell'utente (in attesa).
- Nessun test dell'encoder Core ML: la compatibilità con gli embedding PyTorch è quella dichiarata nel
  README del repo FluidInference.
- Gli anni in `labels.csv` e la verità Commons (modello giusto nel titolo del file) non sono stati
  controllati foto per foto.
- Nessuna misura di generazione, di "fuori catalogo" o di tempo su iPhone.
