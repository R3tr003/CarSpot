# Catalogo dei modelli e Collezione album — design

Data: 2026-10-25 · Stato: **approvato dall'utente (2026-10-25)**.
Mockup nel visual companion (`.superpowers/brainstorm/71266-1792946177/content/`): `album-home.html`
(scelta: **C, album continuo**), `album-c-search.html` (ricerca e filtri), `album-cards-detail.html`
(carte, ombre, dettaglio). Spike di scontorno: 8 foto di Wikipedia scontornate con Vision su Mac, risultato
buono (auto isolata, sagoma pulita; in una foto entra il pezzo di un'altra auto dietro).

## Perché

L'utente trova la Collezione attuale "troppo blanda, quasi senza idee": una griglia delle proprie foto,
tutte simili, con tre numeri sopra. Non mostra cosa manca e non spinge a cercare la prossima auto.
Vuole un **album da completare** come la collezione di carte di Royal Match: ogni modello ha un'**immagine
standard uguale per tutti**, quelli trovati brillano, quelli mancanti si vedono come **ombra**, e il
progresso per marca invoglia a completare. Le proprie foto restano nella cronologia (tab Cattura) e nel
dettaglio. Le immagini standard per ora sono **di prova, scaricate da internet** (Wikimedia Commons); quelle
professionali arriveranno dopo e devono sostituirle senza toccare l'app.

Il catalogo serve anche al riconoscimento: la sessione `prova-siglip` sta provando SigLIP2 zero-shot contro
una lista di etichette; quella lista diventerà il catalogo, quindi le etichette si esportano da qui.

## Obiettivi

1. **Catalogo su Supabase** il più ampio possibile, con marche, modelli e versioni, immagine standard,
   dati per i filtri e attribuzione/licenza dell'immagine.
2. **Pipeline di prova** (`tools/catalog/`) che costruisce il catalogo da Wikidata/Wikipedia, scarica le
   immagini libere da Commons, le scontorna e sfoca le targhe, registra autore e licenza, carica tutto.
3. **Collezione album** (tab Collezione) nello stile approvato: album continuo con ricerca e filtri,
   carte trovate con immagine standard + colore/materiale di rarità, ombre per le mancanti (con rarità
   visibile), dettaglio del modello con la lista delle versioni e le tue foto.
4. **Servizio catalogo dietro protocollo**, con versione locale/offline e remota (Supabase).

## Non-obiettivi (per ora)

- **Premio per il set completato** (PE quando completi una marca). Piace all'utente, ma l'XP è deciso dal
  server (`private.award_card`) e il premio richiede di replicare lato server l'abbinamento carta↔modello.
  Va in un progetto successivo, con il suo momento di reveal. In questo progetto il progresso per marca si
  vede ma non dà premi. *(Mia proposta: l'utente può chiederlo dentro.)*
- Immagini professionali (imagin.studio o simili) e specifiche tecniche reali (cv, peso) per la rarità.
- Toccare il riconoscimento, la cattura, la sync delle carte o le regole dei doppioni.
- Marchi/loghi delle case (trademark): niente loghi, solo il nome della marca.

## Anti-obiettivi

- AI slop: aloni colorati, arcobaleni, bordi al neon, maiuscolo spaziato, numeri che rotolano, rimbalzi
  sulla UI, card identiche in fila senza gerarchia.
- Un album che scoraggia: niente "23 / 4.800" come numero principale.
- Mostrare le foto degli utenti come immagine standard, o mandare al server qualcosa dell'utente per
  costruire l'album.
- Usare immagini senza licenza compatibile o senza attribuzione.

## Vincoli

- CLAUDE.md e DESIGN.md: SwiftUI iOS 26, Swift 6 strict con `@MainActor` espliciti, `@Observable`,
  token del design system (`CSColor`, `CSFont`, `CSSpace`, `CSRadius`, `CSSize`), `Surface`, `Rarity.color`
  + `Rarity.finish`, `CSPressStyle`, Dynamic Type, Reduce Motion, `Logger`, Swift Testing, commenti brevi
  in italiano, copy in italiano (EN lo aggiunge la sessione principale nel catalogo stringhe).
- Supabase (ref `rdezjqbxqekteextolvh`): RLS `to authenticated`, niente `anon` sulle tabelle; migration
  **0010** in `supabase/migrations/<versione>_0010_<nome>.sql`, applicata sul remoto solo dopo ok esplicito
  dell'utente, poi `get_advisors` security + performance.
- File che questa sessione **non può toccare** (altre sessioni ci lavorano): `StoredCard.swift`,
  `CaptureViewModel.swift`, `MapBackground.swift`, `RootShellView.swift`, `TodayView.swift`,
  `ChallengeEngine.swift`, `PlayerProfile.swift`, Sync, `Localizable.xcstrings`, `CLAUDE.md`,
  `tools/recognition-trial/`. Modificabili: `CollectionView.swift`, `CardDetailView.swift`,
  `SpotCardView.swift`; nuovi file in `CarSpot/Features/Collection/`, `CarSpot/Services/Catalog/`,
  `tools/catalog/`, `supabase/migrations/` (solo 0010), `docs/`. Anche `AppServices.swift` è fuori elenco:
  il servizio catalogo si collega da solo (vedi App), e il collegamento in `AppServices` si segnala come
  seguito per la sessione principale.
- Verifica solo con `xcodebuild … build-for-testing` generico; niente simulatori né installazioni.
- Wikimedia: thumbnail solo a larghezze standard (500/960/1280 px; 800 px risponde errore), User-Agent
  descrittivo senza dati personali, ritmo educato (≤ 1 richiesta/s per i file).

## Decisioni

### Il modello di dominio (deciso con l'utente)

**Marca → Modello → Versione.**
- La **casella dell'album** è il **Modello** (Golf, Panda, 911). Le marche sono i "set".
- Ogni **Versione** (Golf GTI, Golf R, Giulia Quadrifoglio, 911 Turbo) è **una carta diversa**, ma vive
  *dentro* la casella del suo modello come sotto-carta, così l'album non esplode. Ogni modello ha sempre
  una versione base (il nome del modello). Nel dettaglio del modello c'è la **lista delle versioni** trovate
  e da trovare: "la lista di quello che ti manca da prendere".
- Un modello è **trovato** se hai almeno una delle sue versioni. Una marca è **completa** quando tutti i suoi
  modelli sono trovati. *(Mia scelta: "completa al 100%" con tutte le versioni è un livello in più che si
  può aggiungere dopo.)*
- **Generazioni**: non sono carte separate (una Golf del 1985 e una del 2020 riempiono "Golf"). Eccezione:
  quando Wikidata le tratta come modelli distinti con lo stesso nome (Fiat 500 del 1957 e del 2007),
  restano due modelli distinti, mostrati con l'anno ("500 (1957)"). *(Mia scelta.)*
- Le regole dei doppioni non cambiano: `CardCopies.key(make:model:)` usa il nome che il riconoscimento
  scrive nella carta, che è già a livello di versione ("Golf GTI"). Quindi versione diversa = carta nuova,
  come vuole l'utente, senza toccare il server.

### Ampiezza del catalogo (deciso con l'utente)

Auto che si vedono per strada in **Italia ed Europa, dagli anni '80 a oggi**, più le **classiche famose**.
Ordine di grandezza: su Wikidata ci sono ~11.000 voci "modello di automobile" dal 1980 con ~1.200
marche (conteggio del 2026-10-25); dopo i filtri ne restano qualche migliaio. Filtri del builder:
- tenere: modelli di serie con articolo su it/de/fr wiki (indizio di diffusione europea), dal 1980; prima
  del 1980 solo se molto noti (soglia di sitelink da tarare);
- togliere: concept, prototipi, auto da corsa, veicoli commerciali pesanti, voci che sono generazioni di un
  modello già presente (si fondono nel modello);
- marche con meno di N modelli rimasti o tutte senza immagine: fuori. Le soglie le sceglie il builder
  guardando i numeri, con l'obiettivo di un catalogo ampio ma non pieno di rumore.
**Versioni**: Wikidata le copre poco. Si parte da quelle con una voce Wikidata propria legata al modello,
più una lista curata in `tools/catalog/` delle versioni sportive/di nicchia più comuni (GTI, R, RS, AMG,
M, Abarth, Quadrifoglio, Cupra, ST, GR, Type R…). La versione base esiste sempre.

### Immagini di prova (spike riuscito)

- Fonte: immagine principale della voce Wikidata (P18) / Wikipedia del modello o della versione, da
  Wikimedia Commons. Licenze ammesse: pubblico dominio, CC0, CC BY, CC BY-SA. **Escluse** le sole GFDL e
  tutto il resto.
- Lavorazione sul Mac: **scontorno** con Vision (`VNGenerateForegroundInstanceMaskRequest`, solo l'istanza
  più grande), **targhe sfocate** (rilevate con Vision; la stessa regola di privacy dell'app), ritaglio
  sull'auto, ridimensionata a ~512 px di lato lungo, **WebP con trasparenza** (~30–60 KB).
- Una sola immagine per versione: l'**ombra** è la stessa immagine resa in tinta unita dall'app (alpha come
  maschera), non un file a parte.
- Versioni senza immagine propria: usano quella del modello. Modelli senza immagine: niente immagine, l'app
  mostra una sagoma generica per carrozzeria.
- **Attribuzione** per ogni immagine: titolo del file, autore, licenza (nome breve + URL), URL della pagina
  Commons, flag "modificata" (scontornata/sfocata). Le CC BY-SA modificate restano CC BY-SA. Si vede nel
  dettaglio del modello.
- Scarti automatici: nessun soggetto trovato o soggetto troppo piccolo → la versione resta senza immagine;
  la pipeline produce un report da rivedere a mano (es. foto con due auto).
- Le immagini professionali future sostituiscono il file nel bucket e i campi di attribuzione: l'app non
  cambia.

### Supabase (dettagli nell'ADR `docs/adr/0001-catalogo-modelli.md`)

Migration **0010** con tre tabelle in `public`, sola lettura per `authenticated`, scrittura solo dal
service role (nessuna policy di insert/update/delete):
- `car_makes`: `id` (slug, es. `volkswagen`), `name`, `country` (ISO 3166 alpha-2, può mancare),
  `wikidata_id`, `updated_at`.
- `car_models`: `id` (slug, es. `volkswagen-golf`), `make_id` → `car_makes`, `name`, `body_type`
  (insieme chiuso: utilitaria, berlina, station wagon, SUV, monovolume, coupé, cabrio/spider, sportiva,
  pick-up, furgone), `year_start`, `year_end` (null = in produzione), `popularity` (sitelink Wikipedia,
  per l'ordine), `aliases text[]`, `wikidata_id`, `updated_at`.
- `car_variants`: `id` (slug, es. `volkswagen-golf-gti`), `model_id` → `car_models`, `name` (nome completo
  come lo scrive il riconoscimento, es. "Golf GTI"), `is_base`, `year_start`, `year_end`, `aliases text[]`,
  `image_path` (nel bucket), `image_width`, `image_height`, `image_title`, `image_author`,
  `image_license`, `image_license_url`, `image_source_url`, `image_modified`, `wikidata_id`, `updated_at`.
- Tutte e tre hanno `deleted_at` (cancellazione logica): la sync per `updated_at` vede anche le righe tolte.
- Indici sulle FK e su `updated_at`; `updated_at` aggiornato da trigger.
- Bucket **pubblico** `car-models` (solo `image/webp`, ≤ 200 KB) per le immagini standard: sono contenuti
  pubblici con licenza libera; nessun dato utente.
- Caricamento: i dati con SQL generato dallo script ed eseguito tramite MCP (a blocchi); le immagini con
  lo script che usa la chiave service role **messa dall'utente** nel suo terminale (passo che solo lui
  può fare: script guidato con la skill `wizard`). La chiave non entra mai nel repo né nell'app.
- **Rarità**: nessuna colonna. L'app la calcola con `RarityEngine.assess(make:model:year:)` usando il nome
  della versione e `year_start`, così è la stessa regola delle carte catturate. *(Mia scelta: con le
  specifiche reali, in futuro, diventerà un dato del catalogo.)*

### Abbinamento carta ↔ catalogo

Una carta salvata (`StoredCard`: make, model, year) trova la sua versione così, in ordine:
1. marca: nome normalizzato (come `CardCopies.key`) uguale a `car_makes.name` o a un alias noto;
2. versione: nome normalizzato uguale a `car_variants.name` o a un suo alias, dentro quella marca;
3. altrimenti modello: il nome di modello (o alias) più lungo che è prefisso del nome della carta
   ("Golf Variant 1.6 TDI" → Golf). La carta riempie il modello come **"Altra versione"** (sotto-carta
   senza immagine standard, con la tua foto);
4. se due modelli omonimi si contendono la carta (500 del 1957 e del 2007) vince quello con gli anni più
   vicini all'anno della carta;
5. nessun abbinamento: la carta va in **"Fuori catalogo"**, in fondo alla sua marca (o in fondo all'album se
   anche la marca manca), mostrata con la tua foto come oggi. Non sparisce mai niente.
Le ripetizioni (`isRepeat`) non contano, come oggi.

### Export per il riconoscimento

Lo script produce `tools/catalog/out/labels.csv` (marca, modello, versione, id versione, anni) dal
catalogo finale. Non tocca `tools/recognition-trial/`: alla sessione `prova-siglip` si lascia una nota
nella cartella condivisa con il percorso e il formato.

### App

**Servizio** in `CarSpot/Services/Catalog/`:
- protocollo `CatalogService` (Sendable, async) che restituisce il catalogo completo; implementazioni
  **locale** (snapshot JSON incluso nell'app, generato dallo script: funziona offline e per l'ospite) e
  **remota** (Supabase via il client già usato in `SupabaseBackend`, solo con utente autenticato; scarica
  tutto la prima volta e poi solo le righe con `updated_at` più recente, cache su disco).
- un `@Observable @MainActor` store che l'album legge: catalogo + indice di ricerca + abbinamento con le
  carte. Si crea da solo (accesso condiviso) scegliendo locale/remoto come gli altri servizi in
  `AppConfig`; agganciarlo ad `AppServices` è un seguito per la sessione principale.
- immagini caricate in modo lazy dall'URL pubblico del bucket, decodificate in miniatura (come
  `SpotCardView` fa con le foto) e messe in cache su disco.
- logica pura (abbinamento, ricerca, filtri, progresso) separata dalle view e coperta da test Swift Testing.

**Collezione** (sostituisce l'attuale `CollectionView`), dall'alto:
1. `SheetHeader("Collezione")` come oggi.
2. **Riquadro eroe** (`Surface(.hero)`, `KPIStrip`): Modelli trovati · Marche iniziate · Complete. Si nasconde
   mentre si cerca.
3. **Ricerca** "Cerca marca o modello": senza accenti/maiuscole, tollerante a un errore di battitura per
   parola, con suggerimenti mentre scrivi.
4. **Filtro principale**: Tutte / Trovate / Da trovare (segmentato nativo).
5. **Pillole**: Rarità, Carrozzeria, Paese, Epoca (decennio di `year_start`). Pillola attiva = piena con ✕
   per toglierla; scorrono di lato e non tagliano il testo con Dynamic Type grande.
6. **Album**: marche una dopo l'altra (in ordine alfabetico), intestazione agganciata in alto con nome,
   barretta e "5/9"; dentro, griglia a 3 colonne di **carte modello** in ordine di `popularity`. Griglia
   lazy (migliaia di carte). **Indice A–Z** sul bordo per saltare alla lettera.
7. **Nessun risultato**: messaggio con via d'uscita ("Togli il filtro SUV", "Mostra tutte").
8. **Stato vuoto** (nessuna carta catturata): l'album c'è comunque, tutto ombre, con un invito in cima a
   catturare la prima auto.

**Carta modello** (nuovo componente in `Features/Collection/`, separato da `SpotCardView`):
- trovata: immagine standard scontornata con ombra a terra, sulla base della carta con colore + materiale
  della rarità (quella più alta tra le tue copie del modello); marca come eyebrow nel colore della rarità,
  nome del modello; "×N" se hai più copie; "Nuova" se la prima copia è degli ultimi 7 giorni; "2/5" se il
  modello ha più versioni;
- mancante: ombra (immagine in tinta unita), nome in inchiostro terziario, **pallino del colore della rarità**
  del catalogo (decisione dell'utente: la rarità si vede anche sulle mancanti);
- VoiceOver: un solo elemento, "Marca Modello, rarità, trovata/da trovare, N versioni su M".
- tocco: apre il dettaglio del modello con la transizione zoom già usata.

**Dettaglio del modello** (nuova view; `CardDetailView` resta per la singola carta/foto):
- carta grande standard (inclinabile come oggi, foil per rarità, ferma con Reduce Motion), badge rarità;
- se mancante: "Non l'hai ancora trovata. Fotografala per sbloccare la carta.";
- gruppo **Versioni**: una riga per versione, trovata (miniatura, nome, rarità, ×N) o da trovare (ombra,
  nome, pallino di rarità), più eventuali "Altra versione";
- gruppo **Le tue foto**: le tue catture del modello, dalla più recente; il tocco apre `CardDetailView`;
- gruppo dati: Carrozzeria, Anni, Paese;
- attribuzione dell'immagine (autore · licenza · Wikimedia Commons), tocco = pagina della fonte.

**Motion**: solo feedback. Molle senza rimbalzo per filtri e comparsa dei risultati; zoom nativo verso il
dettaglio; nessuna animazione d'ingresso a cascata sulle carte. Reduce Motion rispettato ovunque.

## Scelte prese dopo la revisione (mie, da controllare)

1. **Nomi che il riconoscimento scrive nelle carte**: il provider reale non è ancora scelto e il mock scrive
   già versioni ("Golf GTI", "Giulia Quadrifoglio"). L'abbinamento è *best effort*: alias generati dalla
   pipeline (abbreviazioni come VW, nomi senza trattini, numeri romani delle generazioni tolti) + prefisso
   del modello + "Fuori catalogo". Diventerà esatto quando il riconoscimento userà le etichette del catalogo.
2. **Rarità**: una carta trovata mostra la rarità **salvata** nelle tue copie (la più alta), la stessa che
   vedi in cronologia e nel dettaglio della foto. Le mancanti mostrano la rarità **del catalogo**, che è una
   stima: la carta vera può uscire diversa (es. un'auto d'epoca sale di rarità).
3. **Snapshot e ordine dei lavori**: lo snapshot JSON (solo dati e URL delle immagini, non le immagini) è
   generato dalla pipeline e committato nel repo; l'app funziona con lo snapshot anche prima che il bucket
   sia pieno, mostrando le sagome generiche per carrozzeria dove l'immagine non si carica. Ordine: pipeline
   e snapshot → app → migration 0010 + caricamento (dopo l'ok dell'utente e il suo passo con la chiave).
4. **Fonte di verità**: Supabase. Lo snapshot è il punto di partenza offline; all'avvio si usa il più recente
   tra snapshot e cache (per `updated_at` massimo), poi si chiedono al server solo le righe più nuove,
   comprese le cancellate (`deleted_at`).
5. **Conteggi e filtri**: "Altra versione" rende il modello trovato (conta nel progresso), ma la versione
   base resta da trovare nella lista. Le carte "Fuori catalogo" si vedono con Tutte e Trovate e con la
   ricerca per nome; spariscono quando è attiva una pillola (non hanno quei dati) e non contano nei
   progressi delle marche.
6. **Collegamento**: `CollectionView()` resta senza parametri (nessuna modifica a `RootShellView`); legge le
   carte con `@Query` e le passa alla logica pura dello store condiviso del catalogo.

## Lasciato al builder

Nomi dei tipi e dei file, struttura del JSON snapshot, soglie dei filtri del catalogo, algoritmo esatto di
tolleranza agli errori, layout fine (misure, raggi) nel rispetto dei token, formato della cache, come
dividere la pipeline in passi (`fetch`, `process`, `upload`, `export`), strategia di batch per l'SQL.

## Seguiti noti (fuori da questa sessione)

- Premio per marca completata (server + reveal).
- Collegare lo store del catalogo in `AppServices`; stringhe EN nel catalogo; analytics per ricerca/filtri
  (oggi si riusa `collectionFiltered`).
- Usare il catalogo come lista di etichette nel riconoscimento e come scelta guidata nella conferma.
