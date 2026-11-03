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

## Prova "da strada" senza foto dell'utente (2026-11-03, solo base 256)

Le foto vere non ci sono, quindi due sostituti (stesso catalogo da 235 modelli):

- **Commons peggiorate** (`degrade.py` → `degraded/`): le stesse 76 foto con 2–3 difetti a caso
  (seed fisso) fra inquadratura parziale, bassa risoluzione, mosso, sera con rumore, controluce,
  telefono storto, più JPEG forte. Simula lo scatto al volo; resta una simulazione.
- **Stanford Cars** (`prep_stanford.py` → `stanford/`): split test HF `tanganke/stanford_cars`,
  56 classi abbinate a 41 modelli del catalogo, 25 foto per classe = 1.400 foto.

| base 256 | Commons pulite | Commons peggiorate | Stanford Cars |
|---|---:|---:|---:|
| Marca top-1 | 93,4 % | 88,2 % | 99,8 % |
| Modello top-1 | 77,6 % | 75,0 % | 98,1 % |
| Modello top-3 | 93,4 % | 92,1 % | 99,5 % |
| Modello top-3 (prompt con anni) | 90,8 % | 97,4 % | 99,1 % |
| conf ≥ 0,7: foto tenute → corrette | 67 % → 98 % | 64 % → 94 % | 95 % → 99 % |
| conf ≥ 0,9: foto tenute → corrette | 49 % → 100 % | 42 % → 100 % | 84 % → 99,6 % |

Come leggerli:
- **Stanford non va preso come stima**: è un benchmark storico da web/concessionarie (le foto non
  sono "da strada") e quasi certamente dentro i dati di addestramento di SigLIP2; inoltre sono auto
  USA 2007–2012 ben distinte fra loro. Dice solo che sulle foto "facili" il modello è saturo.
- **Le peggiorate sono il numero utile**: marca −5 punti, modello top-1 −3, top-3 quasi invariato.
  La confidenza resta affidabile (sopra 0,9 nessun errore), ma tiene meno foto senza conferma.
- Conclusione: niente di quanto visto spinge sotto la soglia del 60 % → si può procedere con il
  piano "top-3 + conferma". Il numero vero arriverà dalle conferme degli utenti.

## Catalogo completo e app on-device (2026-11-03)

Nell'app il riconoscimento gira sul telefono (`OnDeviceRecognitionService`) contro **tutti i
3.771 modelli** del catalogo (`catalog-snapshot.json`), non più le 235 righe di `labels.csv`.

- **Encoder**: la conversione Core ML di FluidInference (fp16, coseno 0,9999 vs PyTorch),
  palettizzata a 8 bit k-means per tensore → **93 MB**, coseno ≥ 0,996 (`convert_coreml.py`).
  L'int8 lineare scendeva a 0,90; la conversione diretta con coremltools 9 fallisce sul tracing.
- **Famiglie**: il catalogo divide le generazioni in modelli separati ("A5" / "A5 8T", "TT" /
  "TT 8J"): erano la maggior parte degli "errori". Ora i modelli con lo stesso prefisso di nome
  nella stessa marca formano una famiglia, e la top-3 somma le probabilità per famiglia.
- **Popolarità**: `+ β·log(1 + popolarità)` ai logit. β=2 scelto qui sotto; non spinto oltre
  per non adattarsi a 76 foto e per non schiacciare le auto rare (sono il gioco).
- **Prototipi immagine** (immagini standard delle versioni, 2.537 modelli): **peggiorano** a ogni
  peso provato (una sola immagine per versione, spesso atipica) → fuori dall'app.

| catalogo completo, base 8 bit | Commons pulite | Commons peggiorate | Stanford (400) |
|---|---:|---:|---:|
| Solo testo, senza famiglie | 56,9 % / 70,8 % | 52,3 % / 75,4 % | 57,2 % / 94,8 % |
| Testo + famiglie | 64,6 % / 75,4 % | 61,5 % / 78,5 % | 85,5 % / 95,1 % |
| **Testo + famiglie + popolarità β=2 (app)** | **75,4 % / 87,7 %** | **72,3 % / 86,2 %** | **95,1 % / 98,2 %** |
| con prototipi w=0,25 (β=2) | 61,5 % / 76,9 % | 60,0 % / 73,8 % | 87,1 % / 90,8 % |

Valori = modello top-1 / top-3. Escluse le 5 foto Commons che sono anche immagini del catalogo.
Con la configurazione dell'app, sulle peggiorate: confidenza ≥ 0,7 sul 46 % delle foto con il 97 %
giuste; < 0,5 (scelta manuale in app) sul 29 %.

**Verifica Swift**: lo stesso `OnDeviceRecognitionService.swift` compilato per macOS dà embedding
con coseno ≥ 0,986 (media 0,993) rispetto al preprocessing Python (miniatura ImageIO 512 px +
interpolazione `.high`, la variante più vicina al bilineare di PIL fra quelle provate) e ~15 ms per
foto sul Mac. Non misurato su iPhone.

**Problemi del catalogo emersi** (da sistemare nel catalogo, non nel modello):
- Mancano modelli comuni: **Mini Cooper/Hatch, Hyundai i10, Ferrari 458** (c'è come "458").
- Voci generiche con popolarità alta che rubano il primo posto: "Ford full-size Ford (1908)" (65)
  sopra la Fiesta, "Daihatsu sport utility vehicle", "Daihatsu coupe", "Renault A-segment".
- Doppioni lingua: "Mercedes-Benz Classe E" ed "E-Class" sono due modelli distinti.
- Rebadge regionali (Ford Ikon/Del Rio/Versailles) vicinissimi alle Fiesta/Focus europee.

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
| `degrade.py` | peggiora `samples/` in `degraded/` (difetti "da strada", seed fisso) |
| `prep_stanford.py` | estrae da Stanford Cars i modelli del catalogo in `stanford/` |
| `convert_coreml.py` | encoder Core ML 8 bit per l'app (`export/base/CarEncoder.mlpackage`) + verifica vs PyTorch |
| `catalog_embeddings.py` | `build` / `measure` / `export-app`: vettori di tutto il catalogo, misura, file nel bundle |
| `results/` | `summary_*.json`, `predictions_*.csv` per ogni run |
| `export/base/` | `label_embeddings_gen.f16` 456 KB (304×768) · `label_embeddings_model.f16` 352 KB (235×768) · `labels_gen.json` 55 KB · `labels_model.json` 36 KB |
| `export/so400m/` | `label_embeddings_gen.f16` 684 KB (304×1152) · `label_embeddings_model.f16` 529 KB (235×1152) · json come sopra |

Gitignorati: `.venv/` (942 MB), `.cache/` (5,7 GB modelli), `samples/` (22 MB), `photos/`, `degraded/`, `stanford/`.

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

- Nessun numero su foto vere dell'utente: al loro posto Commons peggiorate e Stanford Cars (vedi sopra).
- Nessun test dell'encoder Core ML: la compatibilità con gli embedding PyTorch è quella dichiarata nel
  README del repo FluidInference.
- Gli anni in `labels.csv` e la verità Commons (modello giusto nel titolo del file) non sono stati
  controllati foto per foto.
- Nessuna misura di generazione, di "fuori catalogo" o di tempo su iPhone.
