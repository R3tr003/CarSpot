# Catalogo dei modelli e Collezione album — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Catalogo Marca→Modello→Versione (Wikidata + Commons, su Supabase e in snapshot nell'app) e nuova Collezione "album continuo" con ricerca, filtri, ombre e dettaglio del modello.

**Architecture:** Una pipeline Python + un piccolo CLI Swift (Vision) in `tools/catalog/` produce il catalogo, le immagini scontornate, lo snapshot JSON per l'app, l'SQL di seed e le etichette per il riconoscimento. Nell'app, `Services/Catalog/` contiene modelli Codable, logica pura (ricerca, abbinamento carte, costruzione dell'album) testata con Swift Testing, i servizi locale/remoto dietro protocollo e uno store `@Observable` condiviso; `Features/Collection/` contiene le view.

**Tech Stack:** Python 3.13 + Pillow (WebP ok), SPARQL Wikidata, API Commons; Swift CLI (Vision, CoreImage); SwiftUI iOS 26, Swift 6 strict, SwiftData `@Query`, supabase-swift (già nel progetto), Swift Testing; Supabase Postgres + Storage.

**Spec:** `docs/superpowers/specs/2026-10-25-catalog-album-design.md` (+ `docs/adr/0001-catalogo-modelli.md`, `docs/GLOSSARY.md`).

## Global Constraints

- Swift 6 strict, **senza** default MainActor: `@MainActor` espliciti su UI e store; tipi che attraversano isolation `Sendable`; servizi `async`; CPU pesante `@concurrent`.
- Solo token del design system: `CSColor`, `CSFont` (mai `.system(size:)` per testo), `CSSpace`, `CSRadius`, `CSSize.minTap` (44), `Surface(.hero|.group)`, `SurfaceDivider`, `KPIStrip`, `CSPressStyle`, `Rarity.color` / `Rarity.finish`.
- Reduce Motion sempre rispettato; molle `.spring(duration:bounce: 0)`; nessuna animazione a cascata sulle carte; niente aloni, arcobaleni, neon, maiuscolo spaziato, numeri che rotolano.
- Copy in italiano, del tu; commenti brevi in italiano; `Logger` di `os` (subsystem `com.carspot.andrea.app`, category `catalog`).
- **Non toccare:** `StoredCard.swift`, `CaptureViewModel.swift`, `MapBackground.swift`, `RootShellView.swift`, `TodayView.swift`, `ChallengeEngine.swift`, `PlayerProfile.swift`, `Services/Sync/*`, `Localizable.xcstrings`, `CLAUDE.md`, `AppServices.swift`, `tools/recognition-trial/`. Modificabili: `CollectionView.swift`, `CardDetailView.swift`, `SpotCardView.swift`. Nuovi file solo in `CarSpot/Features/Collection/`, `CarSpot/Services/Catalog/`, `CarSpotTests/`, `tools/catalog/`, `supabase/migrations/` (solo 0010), `docs/`.
- Niente commit, branch, stash (li fa la sessione principale): i passi "Commit" di questo piano diventano "lascia le modifiche nel working tree".
- Verifica: `xcodebuild -project CarSpot.xcodeproj -scheme CarSpot -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/claude-501/-Users-andre-Desktop-CarSpot/5d59843f-3d3e-4791-a950-62e83e5ffdce/scratchpad/dd build-for-testing 2>&1 | grep -E "error:|TEST BUILD SUCCEEDED|BUILD FAILED"`. **Mai simulatori né installazioni**: i test Swift si compilano, non si eseguono su iOS; la logica pura si esegue anche con l'harness macOS del Task 6.
- Wikimedia: User-Agent `CarSpotCatalog/0.1 (car spotting game; trial catalog)` senza dati personali; thumbnail solo a 500/960/1280 px; ≤ 1 download/s.
- Licenze ammesse: `Public domain`, `PD*`, `CC0`, `CC BY *`, `CC BY-SA *`. Escluse: GFDL senza alternativa CC, tutto il resto.

## Review Focus

1. Nomi di marca scritti in modo diverso dal catalogo ("VW", "Mercedes", "Citroen" senza dieresi, "Alfa-Romeo") → la carta deve abbinarsi alla marca giusta, non finire in Fuori catalogo. Test in Task 5.
2. Ricerca con accenti, maiuscole, spazi doppi e un refuso ("citroen c3", "Dobló", "golff") → trova il modello. Test in Task 5.
3. Catalogo enorme (≥ 5.000 modelli) → la griglia resta fluida: lazy, costruzione dell'album fuori dal `body`, nessuna decodifica d'immagine sul main thread. Verifica nel Task 6 (tempo di `AlbumBuilder.build` < 50 ms su 5.000 modelli nell'harness) e nel Task 8.
4. Nessuna rete / ospite / bucket vuoto → l'album mostra comunque tutte le marche con sagome generiche per carrozzeria, mai celle vuote o spinner infiniti. Task 7 e 8.
5. Dynamic Type molto grande → pillole e intestazioni non tagliano il testo, la carta (proporzione fissa) limita a `.xLarge`. Task 8 e 9.

---

## Formato dello snapshot (contratto tra pipeline e app)

File: `CarSpot/Services/Catalog/Resources/catalog-snapshot.json` (incluso nel bundle dal synchronized group). Chiavi camelCase, date ISO-8601 UTC.

```json
{
  "version": 1,
  "generatedAt": "2026-10-25T18:00:00Z",
  "imageBaseURL": "https://rdezjqbxqekteextolvh.supabase.co/storage/v1/object/public/car-models/",
  "makes":   [{"id":"fiat","name":"Fiat","country":"IT","aliases":["FIAT"],"updatedAt":"…"}],
  "models":  [{"id":"fiat-panda","makeId":"fiat","name":"Panda","bodyType":"utilitaria",
               "yearStart":1980,"yearEnd":null,"popularity":85,"aliases":[],"updatedAt":"…"}],
  "variants":[{"id":"fiat-panda","modelId":"fiat-panda","name":"Panda","isBase":true,
               "yearStart":1980,"yearEnd":null,"aliases":[],"updatedAt":"…",
               "image":{"path":"fiat/fiat-panda.webp","width":512,"height":301,
                        "title":"File:2018 Fiat Panda Easy 1.2.jpg","author":"…",
                        "license":"CC BY-SA 4.0","licenseURL":"https://…","sourceURL":"https://commons.wikimedia.org/wiki/File:…",
                        "modified":true}}]
}
```
- `bodyType` ∈ `utilitaria, berlina, station_wagon, suv, monovolume, coupe, cabrio, sportiva, pickup, furgone`.
- Versione base: `id` = id del modello, `isBase: true`, `name` = nome del modello. `image` può essere `null`.
- Id = slug ASCII minuscolo con trattini (marca, poi `marca-modello`, poi `marca-modello-versione`); modelli omonimi distinti per anno: `fiat-500-1957`.
- Lo snapshot non contiene righe cancellate; le righe remote hanno anche `deleted_at`.

---

### Task 1: Pipeline — costruzione del catalogo da Wikidata

**Files:**
- Create: `tools/catalog/README.md`, `tools/catalog/catalog_common.py`, `tools/catalog/fetch_wikidata.py`, `tools/catalog/build_catalog.py`, `tools/catalog/curated/make_aliases.csv`, `tools/catalog/curated/variants.csv`, `tools/catalog/curated/exclude.csv`, `tools/catalog/test_catalog.py`
- Output (non committato, in `.gitignore` locale `tools/catalog/out/`): `out/wikidata_raw.json`, `out/catalog.json`, `out/build_report.md`

**Interfaces:**
- Produces: `out/catalog.json` con `makes/models/variants` nel formato dello snapshot, più `image.commonsFile` (nome file Commons, senza `path`) per le versioni che hanno P18. `catalog_common.slug(text) -> str`, `catalog_common.normalize(text) -> str` (minuscole, senza diacritici, spazi compressi).

- [ ] **Step 1:** test unittest in `test_catalog.py`: `slug("Alfa Romeo")=="alfa-romeo"`, `slug("Citroën ë-C4")=="citroen-e-c4"`, `normalize("  Dobló ")=="doblo"`; `merge_generations` fonde "Volkswagen Golf Mk7" e "Volkswagen Golf Mk8" nel modello "Golf" con `yearStart` minimo e `yearEnd` massimo (null se uno è null); `is_excluded` scarta concept/prototipi/auto da corsa.
- [ ] **Step 2:** `python3 -I -m unittest tools/catalog/test_catalog.py` → FAIL (moduli assenti).
- [ ] **Step 3:** `fetch_wikidata.py`: query SPARQL paginata (LIMIT/OFFSET 2000) su `?m wdt:P31/wdt:P279* wd:Q3231690`, con marca (`P1716` brand, poi `P176` produttore), `P18` immagine, `P571`/`P2754` inizio, `P2669`/`P730` fine, paese della marca (`P17`/`P495` → ISO via `P297`), `P31` (per scartare concept `Q850270`, prototipi, auto da corsa `Q673687`), `P179`/`P155`/`P156` (serie e generazioni), sitelinks totali e presenza di `itwiki`/`dewiki`/`frwiki`, etichette `it`/`en`. Salva `out/wikidata_raw.json`. Ritenta su 429/5xx con attesa.
- [ ] **Step 4:** `build_catalog.py`: filtri dello spec (dal 1980 con articolo it/de/fr; prima del 1980 solo sitelinks ≥ soglia; via concept/prototipi/corsa/commerciali pesanti; fusione generazioni nel modello per nome base senza suffissi `Mk\d+`, numeri romani, codici telaio tra parentesi; marche con < 2 modelli o senza immagini fuori). Nome del modello senza la marca davanti. `body_type` da `P279`/`P31` (berlina, SUV, cabrio…) con fallback `berlina`. Versioni: voci Wikidata con nome = modello + suffisso noto, più `curated/variants.csv` (`make,model,variant_suffix,year_start,year_end`) con almeno GTI, R, GTD (VW), RS (Audi), M (BMW), AMG (Mercedes), Abarth (Fiat 500/595/124), Quadrifoglio (Alfa), Cupra (Seat), ST (Ford), GR (Toyota), Type R (Honda), N (Hyundai), Turbo/GT3 (Porsche 911). `make_aliases.csv` con almeno VW, Mercedes, Mercedes-Benz, Citroen, Alfa, Land Rover/Range Rover. `exclude.csv` per correzioni manuali. Scrive `out/catalog.json` e `out/build_report.md` (conteggi per marca, scarti per motivo, versioni senza immagine).
- [ ] **Step 5:** unittest PASS; `python3 -I tools/catalog/fetch_wikidata.py && python3 -I tools/catalog/build_catalog.py` → report con migliaia di modelli; controllo a campione (Fiat, VW, Ferrari, Toyota) che non ci siano concept né doppioni di generazione.

### Task 2: Pipeline — immagini (attribuzione, download, scontorno, targhe, WebP)

**Files:**
- Create: `tools/catalog/fetch_images.py`, `tools/catalog/process_images.py`, `tools/catalog/cutout/main.swift`, `tools/catalog/cutout/build.sh`
- Output: `out/raw/<variant_id>.jpg`, `out/cut/<variant_id>.png`, `out/images/<make_id>/<variant_id>.webp`, `out/attribution.json`, `out/images_report.md`

**Interfaces:**
- Consumes: `out/catalog.json` (Task 1).
- Produces: `out/attribution.json` = `{variant_id: {title, author, license, licenseURL, sourceURL}}`; `out/images/...webp` con `{width,height}` registrati in `out/images_manifest.json` = `{variant_id: {path, width, height}}`.

- [ ] **Step 1:** `fetch_images.py`: API Commons `action=query&prop=imageinfo&iiprop=extmetadata|url&iiurlwidth=960` a blocchi di 50 titoli; autore da `Artist` (HTML → testo), licenza da `LicenseShortName`/`LicenseUrl`; scarta licenze non ammesse (Global Constraints) e registra il motivo; scarica `thumburl` (960 px) a ≤ 1/s, ripresa da dove si era fermato (salta file già presenti).
- [ ] **Step 2:** `cutout/main.swift` (CLI `cutout <in_dir> <out_dir>`): `VNGenerateForegroundInstanceMaskRequest`, istanza con area maggiore, scarta se l'istanza copre < 8% dell'immagine; sfoca le targhe dentro il ritaglio con `VNRecognizeTextRequest` + regex simile a `ImageAnonymizer.looksLikePlate` (2–3 lettere/cifre alternate, 5–8 caratteri) e `CIGaussianBlur` sulla regione; salva PNG RGBA ritagliato. `build.sh` compila con `swiftc -O` in `out/bin/cutout`.
- [ ] **Step 3:** `process_images.py`: PNG → lato lungo 512 px, WebP con alpha qualità 80 (`method=6`), target ≤ 60 KB (riduce qualità fino a 60 se serve); scrive manifest e `images_report.md` (scarti: senza soggetto, soggetto piccolo, licenza).
- [ ] **Step 4:** prova su 20 versioni (`--limit 20`), apri `out/images` e controlla a vista 5 risultati; poi lancia la corsa completa **in background** (può durare ore) e passa al Task 3 quando finisce.

### Task 3: Pipeline — export (snapshot app, SQL seed, etichette) e migration 0010

**Files:**
- Create: `tools/catalog/export.py`, `tools/catalog/upload_images.py`, `tools/catalog/upload-wizard.sh` (skill `wizard`), `supabase/migrations/<YYYYMMDDHHMMSS>_0010_car_catalog.sql`
- Output: `CarSpot/Services/Catalog/Resources/catalog-snapshot.json`, `out/seed/0001.sql…`, `out/labels.csv`; nota in `/Users/andre/Library/Application Support/Claude/side-session-notes/local_7e194811-a324-421e-b601-0fa1105d4fc0/catalog-labels.md`

**Interfaces:**
- Consumes: `out/catalog.json`, `out/attribution.json`, `out/images_manifest.json`.
- Produces: snapshot nel formato sopra; tabelle `public.car_makes`, `public.car_models`, `public.car_variants`; bucket `car-models`.

- [ ] **Step 1:** migration 0010: tre tabelle (colonne dello spec + `car_makes.aliases text[] not null default '{}'`, `deleted_at timestamptz` su tutte, `created_at`, `updated_at timestamptz not null default now()`), FK con indice, indici su `updated_at`, `check` su `body_type`, trigger `updated_at` (funzione in `private`, `security invoker`, `search_path = ''`), RLS on + policy `select` `to authenticated using (true)` per ciascuna, `revoke all … from anon`, bucket pubblico `car-models` (`allowed_mime_types = '{image/webp}'`, `file_size_limit = 204800`) senza policy di scrittura.
- [ ] **Step 2:** `export.py`: unisce catalogo + attribuzione + manifest (`modified: true` quando scontornata), scrive lo snapshot (ordinamento stabile per id, `updatedAt` = ora dell'export), `labels.csv` (`make,model,variant,variant_id,year_start,year_end`), SQL seed a blocchi da ~500 righe con `insert … on conflict (id) do update`. Validazione: id unici, ogni `modelId`/`makeId` esiste, `bodyType` valido.
- [ ] **Step 3:** `upload_images.py`: legge `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` dall'ambiente, carica `out/images/**.webp` su `car-models/<make_id>/<variant_id>.webp` con `x-upsert: true`, salta quelli già presenti; `upload-wizard.sh` guida l'utente (dove trovare la chiave, `export` nel suo terminale, lancio, verifica di un URL pubblico).
- [ ] **Step 4:** scrivi la nota per `prova-siglip` (percorso e colonne di `labels.csv`).
- [ ] **Step 5 (solo dopo ok esplicito dell'utente):** `apply_migration` 0010 via MCP, `get_advisors` security + performance (zero nuovi warning sulle tabelle del catalogo), seed via `execute_sql` blocco per blocco, `select count(*)` sulle tre tabelle = conteggi dello snapshot; l'utente lancia il wizard per le immagini.

### Task 4: App — modelli del catalogo e snapshot

**Files:**
- Create: `CarSpot/Services/Catalog/CatalogModels.swift`, `CarSpot/Services/Catalog/Resources/catalog-snapshot.json` (fixture piccola finché il Task 3 non scrive quello vero: 3 marche Fiat/Volkswagen/Ferrari, 8 modelli, 12 versioni, metà con `image: null`), `CarSpotTests/CatalogSnapshotTests.swift`

**Interfaces:**
- Produces (tutti `Codable, Sendable, Hashable`, `Identifiable` dove c'è `id`):
  - `enum BodyType: String, CaseIterable { utilitaria, berlina, stationWagon = "station_wagon", suv, monovolume, coupe, cabrio, sportiva, pickup, furgone }` con `displayName: LocalizedStringResource` ("Utilitaria", "Berlina", "Station wagon", "SUV", "Monovolume", "Coupé", "Cabrio", "Sportiva", "Pick-up", "Furgone") e `symbol: String` (SF Symbol di fallback: `car.side.fill`, `suv.side.fill`, `convertible.side.fill`, `truck.pickup.side.fill`, `bus.fill` per furgone/monovolume).
  - `struct CatalogMake { id, name: String; country: String?; aliases: [String]; updatedAt: Date }`
  - `struct CatalogModel { id, makeId, name: String; bodyType: BodyType; yearStart: Int?; yearEnd: Int?; popularity: Int; aliases: [String]; updatedAt: Date }`
  - `struct CatalogImage { path: String; width, height: Int; title, author, license: String; licenseURL, sourceURL: URL?; modified: Bool }`
  - `struct CatalogVariant { id, modelId, name: String; isBase: Bool; yearStart, yearEnd: Int?; aliases: [String]; updatedAt: Date; image: CatalogImage? }`
  - `struct CatalogSnapshot { version: Int; generatedAt: Date; imageBaseURL: URL; makes: [CatalogMake]; models: [CatalogModel]; variants: [CatalogVariant] }` con `static func decode(_ data: Data) throws -> CatalogSnapshot` (decoder ISO-8601) e `static func bundled() throws -> CatalogSnapshot` (`Bundle.main`, risorsa `catalog-snapshot.json`), `var newestUpdate: Date` (max `updatedAt`), `func imageURL(for: CatalogImage) -> URL`.

- [ ] **Step 1:** test `decodeFixture` (decodifica una stringa JSON inline con 1 marca/1 modello/2 versioni, `bodyType` `station_wagon` → `.stationWagon`, `image` null ammesso), `imageURLConcatena` (`imageBaseURL` + `path`), `newestUpdate`.
- [ ] **Step 2:** implementa; scrivi la fixture nel bundle.
- [ ] **Step 3:** build di verifica → `TEST BUILD SUCCEEDED`.

### Task 5: App — normalizzazione, ricerca e abbinamento carte

**Files:**
- Create: `CarSpot/Services/Catalog/CatalogIndex.swift`, `CarSpot/Services/Catalog/CatalogMatcher.swift`, `CarSpotTests/CatalogMatcherTests.swift`, `CarSpotTests/CatalogSearchTests.swift`

**Interfaces:**
- Consumes: Task 4.
- Produces:
  - `enum CatalogText { static func normalize(_ s: String) -> String }` — minuscole, `folding(.diacriticInsensitive)`, `-`/`_` → spazio, spazi compressi (stesse regole di spazi di `CardCopies.key`).
  - `struct CatalogIndex: Sendable` — `init(_ snapshot: CatalogSnapshot)`; `makes: [CatalogMake]` (alfabetico), `make(id:)`, `model(id:)`, `models(ofMake:) -> [CatalogModel]` (per `popularity` decrescente, poi nome), `variants(ofModel:) -> [CatalogVariant]` (base prima, poi nome), `baseVariant(ofModel:)`, `catalogRarity(of: CatalogVariant) -> Rarity` = `RarityEngine.assess(make: makeName, model: variant.name, year: variant.yearStart ?? model.yearStart).rarity`, `func matches(model: CatalogModel, query: String) -> Bool`, `func suggestions(for query: String, limit: Int = 5) -> [String]` (nomi di marca e "Marca Modello" che iniziano con la query normalizzata).
  - `enum CardMatch: Equatable, Sendable { case variant(id: String), otherVersion(modelId: String), unmatched(makeId: String?) }`
  - `struct CatalogMatcher: Sendable` — `init(index: CatalogIndex)`; `func match(make: String, model: String, year: Int) -> CardMatch` con l'ordine dello spec (marca per nome/alias normalizzato; versione per nome/alias; prefisso di modello più lungo → `otherVersion`; omonimi → anni più vicini a `year`; altrimenti `unmatched(makeId:)`).
- Regola di ricerca: la query si divide in parole normalizzate; un modello corrisponde se **ogni** parola è prefisso di una parola di "marca + modello + alias del modello + nomi delle versioni", oppure (parole ≥ 4 lettere) dista al massimo 1 modifica (Levenshtein) da una di quelle parole.

- [ ] **Step 1:** test (fixture inline): `marcaAlias` — `match(make: "VW", model: "Golf GTI", year: 2019) == .variant(id: "volkswagen-golf-gti")`; `diacritici` — `match(make: "Citroen", model: "C3", …)` trova la Citroën C3; `prefisso` — `"Golf Variant 1.6 TDI"` → `.otherVersion(modelId: "volkswagen-golf")`; `omonimiPerAnno` — "Fiat"/"500" con 1968 → `fiat-500-1957`, con 2015 → `fiat-500`; `fuoriCatalogo` — "Fiat"/"Zzz" → `.unmatched(makeId: "fiat")`, "Marca Ignota"/"X" → `.unmatched(makeId: nil)`; ricerca: `"golff"` trova Golf, `"Dobló"` trova Doblò, `"alfa giulia"` trova Giulia, `"giu"` (prefisso) trova Giulia, `"xq"` niente; `suggestions("fe")` contiene "Ferrari".
- [ ] **Step 2:** implementa; build → `TEST BUILD SUCCEEDED`.

### Task 6: App — costruzione dell'album (filtri, progressi) + harness macOS

**Files:**
- Create: `CarSpot/Services/Catalog/AlbumBuilder.swift`, `CarSpotTests/AlbumBuilderTests.swift`; harness in scratchpad `…/scratchpad/harness/main.swift` (fuori dal repo)

**Interfaces:**
- Consumes: Task 4–5.
- Produces:
  - `struct OwnedCard: Sendable, Hashable { id: UUID; make, model: String; year: Int; rarity: Rarity; capturedAt: Date }`
  - `enum Ownership: CaseIterable { all, found, missing }` (titoli "Tutte", "Trovate", "Da trovare")
  - `struct AlbumFilters: Equatable, Sendable { var ownership = Ownership.all; var rarity: Rarity?; var bodyType: BodyType?; var country: String?; var era: Int? /* decennio, 1970 = "Classiche" (< 1980) */; var query = ""; var isNarrowed: Bool /* pillole o query attive */ }`
  - `struct AlbumVariantRow: Identifiable, Sendable { id: String; name: String; rarity: Rarity; copies: Int; image: CatalogImage?; isFound: Bool; isOtherVersion: Bool; cardIDs: [UUID] }`
  - `struct AlbumModelEntry: Identifiable, Sendable { id: String /* modelId */; makeName, name: String; bodyType: BodyType; rarity: Rarity; isFound: Bool; copies: Int; isNew: Bool; versionsFound, versionsTotal: Int; image: CatalogImage? }` — `rarity`: trovato → la più alta salvata tra le copie; mancante → `catalogRarity` della base. `image`: quella della prima versione trovata che ne ha una, altrimenti della base. `isNew`: prima copia del modello negli ultimi 7 giorni rispetto a `now`. `versionsTotal` conta le versioni del catalogo (le "Altra versione" no).
  - `struct AlbumSection: Identifiable, Sendable { id: String /* makeId o "fuori-catalogo" */; title: String; found, total: Int; models: [AlbumModelEntry]; orphans: [OwnedCard] }`
  - `struct AlbumStats: Equatable, Sendable { modelsFound, makesStarted, makesComplete: Int }`
  - `struct AlbumMatches: Sendable { init(cards: [OwnedCard], matcher: CatalogMatcher) }` — precalcolo (carta → `CardMatch`) da rifare solo quando cambiano le carte.
  - `enum AlbumBuilder { static func build(index: CatalogIndex, matches: AlbumMatches, filters: AlbumFilters, now: Date) -> (sections: [AlbumSection], stats: AlbumStats); static func variantRows(modelId: String, index: CatalogIndex, matches: AlbumMatches) -> [AlbumVariantRow] }`
- Regole: sezioni in ordine alfabetico di marca; marche senza modelli visibili dopo i filtri omesse; `found/total` della sezione e le `stats` contano sempre tutti i modelli della marca (non solo quelli filtrati); le carte `unmatched(makeId:)` vanno in `orphans` della loro marca o della sezione "Fuori catalogo" (ultima); gli orfani si vedono solo con `ownership != .missing` e nessuna pillola attiva (la query sul loro nome sì); le carte `isRepeat` non arrivano qui (le esclude la `@Query`).

- [ ] **Step 1:** test: `statsBase` (2 carte Fiat su 2 modelli, 1 marca completa su fixture con Ferrari a 0 → `modelsFound 2, makesStarted 1, makesComplete …`); `filtroDaTrovare` (solo mancanti, `found/total` invariati); `filtroRarita` sul colore mostrato; `filtroEpocaClassiche` (`era: 1970` → solo `yearStart < 1980`); `nuovaSette giorni` (6 giorni → `isNew`, 8 → no); `rarSalvata` (copia Leggendaria su modello Comune → `.leggendaria`); `altraVersione` (modello trovato, base ancora da trovare in `variantRows`); `orfaniNascostiConPillola`; `marcaVuotaOmessa`.
- [ ] **Step 2:** implementa; build → `TEST BUILD SUCCEEDED`.
- [ ] **Step 3:** harness macOS: `swiftc -parse-as-library` con `Rarity.swift`, `CSColor.swift`, `RarityEngine.swift`, `CardCopies.swift`, i file di `Services/Catalog/` puri e un `main.swift` che riproduce i test principali con `precondition` e misura `AlbumBuilder.build` su un catalogo sintetico di 5.000 modelli / 400 marche / 300 carte (< 50 ms). Output atteso: `OK` e il tempo.

### Task 7: App — servizi locale/remoto, store condiviso, immagini

**Files:**
- Create: `CarSpot/Services/Catalog/CatalogService.swift`, `CarSpot/Services/Catalog/SupabaseCatalogService.swift`, `CarSpot/Services/Catalog/CatalogStore.swift`, `CarSpot/Services/Catalog/CatalogImageLoader.swift`, `CarSpotTests/CatalogMergeTests.swift`

**Interfaces:**
- Consumes: Task 4–6, `SupabaseBackend.shared?.client`.
- Produces:
  - `protocol CatalogService: Sendable { func changes(since: Date) async throws -> CatalogChanges }`; `struct CatalogChanges: Sendable { makes: [CatalogMake]; models: [CatalogModel]; variants: [CatalogVariant]; deletedMakeIds, deletedModelIds, deletedVariantIds: Set<String> }`; `extension CatalogSnapshot { func merging(_ c: CatalogChanges) -> CatalogSnapshot }` (upsert per id, poi rimozioni).
  - `struct SupabaseCatalogService: CatalogService` — tabelle `car_makes/car_models/car_variants`, `.gt("updated_at", since)`, pagine da 1000 con `.range`, righe DTO snake_case → modelli (i campi `image_*` piatti → `CatalogImage?` se `image_path` non è null; `deleted_at` non null → negli insiemi delle cancellate).
  - `@MainActor @Observable final class CatalogStore { static let shared; private(set) var index: CatalogIndex?; private(set) var matcher: CatalogMatcher?; func load() async }` — `load()` una volta sola: snapshot dal bundle o dalla cache su disco (`Application Support/Catalog/catalog.json`) se ha `newestUpdate` più recente; pubblica; poi, se `SupabaseBackend.shared != nil`, chiede `changes(since: newestUpdate)`, unisce, salva la cache, ripubblica. Errori → log `catalog`, nessun messaggio all'utente. Decodifica/merge fuori dal main actor (`@concurrent` o `Task.detached`).
  - `actor CatalogImageLoader { static let shared; func image(for url: URL, maxPixel: Int) async -> UIImage? }` — memoria (`NSCache`) + disco (`Caches/CatalogImages/`), download con `URLSession`, decodifica ridotta con ImageIO (come `SpotCardView`), `nil` su errore.
  - `struct CatalogImageView: View { let image: CatalogImage?; let bodyType: BodyType; var silhouette: Bool; var maxPixel = 400 }` — immagine; con `silhouette` la rende `.renderingMode(.template)` in `CSColor.nested`; senza immagine o in caricamento mostra `Image(systemName: bodyType.symbol)` in `CSColor.nested` (mai spinner).

- [ ] **Step 1:** test `mergeUpsertERimozione` (una versione aggiornata, una cancellata, un modello nuovo).
- [ ] **Step 2:** implementa; build → `TEST BUILD SUCCEEDED`.

### Task 8: App — Collezione album

**Files:**
- Modify (riscrittura): `CarSpot/Features/Collection/CollectionView.swift` (resta `FilterChip` dove serve, firma `CollectionView()` invariata)
- Create: `CarSpot/Features/Collection/AlbumModel.swift` (stato `@Observable @MainActor` della schermata: filtri, sezioni, stats, debounce 150 ms della query), `CarSpot/Features/Collection/AlbumControls.swift` (campo di ricerca, segmentato, pillole a menu), `CarSpot/Features/Collection/AlbumIndexBar.swift`, `CarSpot/Features/Collection/ModelCardView.swift`
- Modify: `CarSpot/DesignSystem/Components/SpotCardView.swift` — estrai bordo/materiale per rarità in una view interna riusabile `RarityFrame(rarity:shape:roll:pitch:compact:)` nello stesso file, senza cambiare l'aspetto di `SpotCardView`.

**Interfaces:**
- Consumes: Task 4–7.
- Produces: `ModelCardView(entry: AlbumModelEntry, style: .grid | .hero, roll: Double = 0, pitch: Double = 0)`.

- [ ] **Step 1:** `ModelCardView` (proporzione 0,7, `CSRadius.card` in `.hero`, raggio 14 in griglia): trovata → base `elevated → surface` con velo della rarità al 16%, `CatalogImageView` (ombra a terra nera 35%), `RarityFrame`, marca come eyebrow nel colore della rarità, nome (max 2 righe), pillole "×N" (copie > 1), "Nuova", "2/5" (versioni > 1); mancante → base `surface`, `CatalogImageView(silhouette: true)`, nome in `inkTertiary`, pallino di `rarity.color` (8 pt) accanto al nome; `.dynamicTypeSize(...DynamicTypeSize.xLarge)`; VoiceOver un elemento: "Marca Modello, Rarità, trovata|da trovare, N versioni su M".
- [ ] **Step 2:** `CollectionView`: `@Query(filter: isRepeat == false)` delle carte → `[OwnedCard]` → `AlbumModel.update(cards:)`; `.task { await CatalogStore.shared.load() }`. Layout dall'alto: `SheetHeader("Collezione")`; `Surface(.hero) { KPIStrip("Modelli trovati", "Marche iniziate", "Complete") }` nascosto mentre la query non è vuota; campo "Cerca marca o modello" (capsula `CSColor.nested`, icona `magnifyingglass`, ✕ per svuotare, `.submitLabel(.search)`, suggerimenti sotto il campo quando ha il focus: max 5 righe, il tocco riempie la query); `Picker` segmentato Tutte/Trovate/Da trovare; pillole `Menu` per Rarità, Carrozzeria, Paese (nome con `Locale.app.localizedString(forRegionCode:)`), Epoca ("Classiche", "Anni '80", "Anni '90", "Anni 2000", "Anni 2010", "Anni 2020") in `ScrollView(.horizontal)`; attiva = piena `CSColor.ink` con testo `inkInverse` e ✕; poi `LazyVGrid` a 3 colonne (`CSSpace.sm`) con `pinnedViews: [.sectionHeaders]`: header = nome marca (`CSFont.title(17)`), barretta 44×4 `accent`, "5/9", sfondo `CSColor.panel`; celle `NavigationLink` → `ModelDetailView(modelId:)` con `.navigationTransition(.zoom)`; orfani in fondo alla sezione con `SpotCardView(compact: true)` → `CardDetailView`. Analytics: `collectionFiltered(filter:)` con `ownership`/pillola come stringa.
- [ ] **Step 3:** `AlbumIndexBar`: lettere iniziali delle sezioni visibili, colonna a destra (`CSFont.micro`, `accent`), tocco/trascinamento → `ScrollViewReader.scrollTo(sectionId, anchor: .top)` + `.sensoryFeedback(.selection)`; `accessibilityAdjustableAction` per passare alla lettera successiva/precedente; nascosto con meno di 6 sezioni.
- [ ] **Step 4:** stati: catalogo non ancora pronto → stessa schermata con header e controlli, al posto della griglia un `Surface(.group)` "Sto preparando l'album…" (al massimo un frame: lo snapshot è nel bundle); nessuna carta → `Surface(.group)` in cima "Cattura la tua prima auto per iniziare l'album" sopra l'album tutto ombre; nessun risultato → `Surface(.group)` con "Nessun modello trovato" e `GhostButton` che toglie l'ultimo filtro ("Togli il filtro SUV") o "Mostra tutte".
- [ ] **Step 5:** build → `TEST BUILD SUCCEEDED`.

### Task 9: App — dettaglio del modello

**Files:**
- Create: `CarSpot/Features/Collection/ModelDetailView.swift`
- Modify: `CarSpot/Features/Collection/CardDetailView.swift` solo se serve un init da `StoredCard` (altrimenti invariato)

**Interfaces:**
- Consumes: `CatalogStore.shared`, `AlbumBuilder.variantRows`, `ModelCardView(style: .hero)`, `MotionManager`.
- Produces: `ModelDetailView(modelId: String)`.

- [ ] **Step 1:** layout (sfondo `CSColor.panel`, come `CardDetailView`): carta `.hero` max 280 pt con inclinazione da `MotionManager` (ferma con Reduce Motion); titolo "Marca Modello" + `RarityBadge`; se mancante "Non l'hai ancora trovata. Fotografala per sbloccare la carta."; `Surface(.group)` "Versioni" (righe con `SurfaceDivider`: miniatura 52 pt o ombra, nome, rarità a parole + pallino, "×N"; "Altra versione" con la foto dell'utente); `Surface(.group)` "Le tue foto" (griglia di miniature dalle `StoredCard` del modello, la più recente prima, tocco → `CardDetailView(card: stored.asSpotCard)`, la foto si carica con `sync?.loadPhotoIfNeeded` come oggi); `Surface(.group)` dati (Carrozzeria, Anni "2016–2020" / "dal 2012", Paese); attribuzione `CSFont.micro` `inkTertiary`: "Immagine: {author} · {license} · Wikimedia Commons" + "modificata" se `modified`, `Link` alla `sourceURL`.
- [ ] **Step 2:** build → `TEST BUILD SUCCEEDED`.

### Task 10: Rifinitura e verifica finale

- [ ] **Step 1:** agent `ui-reviewer` (Sonnet) su `Features/Collection/*` contro DESIGN.md + checklist di `~/.claude/skills/ui-ux-pro-max/references/pro-rules.md`; correggi i finding materiali.
- [ ] **Step 2:** dati peggiori (skill `break-ui` tradotta): nome modello di 40 caratteri, marca con 1 modello e con 150, 0 e 9.999 copie, query di 1 lettera, catalogo senza immagini → nessun layout rotto.
- [ ] **Step 3:** build finale verde; harness macOS `OK`; riepilogo per la sessione principale: file cambiati, stringhe nuove da tradurre, seguiti (AppServices, premio marca, analytics ricerca), licenze delle immagini (conteggi per licenza da `out/attribution.json`), cosa provare sull'iPhone.
