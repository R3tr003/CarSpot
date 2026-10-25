# Profondità, reveal v3, cronologia — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement your task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** blocchi con profondità a gradini, reveal della carta "la foto diventa la carta" con un colore per rarità e nuova/doppione, tab Cattura come cronologia.

**Architecture:** il Task 1 (fondamenta del design system + logica pura dei doppioni) e il Task 6 (trigger XP sul server) li fa la sessione principale. Poi i Task 2–5 girano in **quattro sessioni parallele nella stessa cartella**, ognuna su file diversi. Le interfacce condivise nascono tutte nel Task 1, così nessuna sessione aspetta un'altra.

**Tech Stack:** SwiftUI iOS 26, Swift 6 strict, SwiftData, Swift Testing, Supabase (Postgres).

**Spec:** `docs/superpowers/specs/2026-10-25-depth-reveal-history-design.md` (leggerla prima: contiene valori, tempi, colori e copy).

## Global Constraints

- Leggere `CLAUDE.md`. Colori/spaziature/font solo da `CarSpot/DesignSystem/`; mai `.system(size:)` per testo; `CSPressStyle` per la pressione; `@Environment(\.accessibilityReduceMotion)` rispettato; `Logger` di os; commenti brevi in italiano.
- Liquid Glass nativo resta su tab bar, pulsanti flottanti, X di chiusura, pillole dell'header. I blocchi di contenuto usano `Surface`.
- Vietati: glow/aloni colorati, gradienti arcobaleno, bordi al neon, numeri che rotolano, rimbalzi su UI, fade-up su ogni blocco, pulsazioni in loop.
- Colori rarità: Comune `#B4BCCB`, Rara `#36E2FF`, Epica `#C04BFF`, Leggendaria `#FFC14D` (via `Rarity.color`).
- **Sessioni parallele:** toccare SOLO i file del proprio task. **Non** modificare `CarSpot/Localizable.xcstrings`, `project.pbxproj`, file di altri task. **Non** fare commit, branch, checkout, stash (li fa la sessione principale).
- **Verifica:** solo `xcodebuild -project CarSpot.xcodeproj -scheme CarSpot -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratchpad della sessione>/dd build-for-testing` → `** TEST BUILD SUCCEEDED **`. **Niente simulatori, niente `xcodebuild test`, niente installazioni.** I test unitari li compila e basta.
- Se la build fallisce per un errore in un file di un altro task (sessione ancora al lavoro), non toccarlo: aspetta 1–2 minuti e riprova; se persiste, segnalalo nel riepilogo.
- Copy nuove in italiano con `LocalizedStringKey`/`String(localized:)`; le traduzioni EN le aggiunge la sessione principale alla fine.

## Review Focus

1. **Collezione vuota / prima carta in assoluto** — reveal: nota "Nuova nella collezione · Carta 1", niente "prima <Marca>" duplicato, nessun crash su `fetchCount` = 0. Test in Task 1 (`copyNumber` con array vuoto).
2. **Marca/modello con maiuscole e spazi diversi** ("VW Polo " vs "vw  polo") — devono contare come lo stesso modello. Test in Task 1.
3. **Doppione oltre la decima copia** — XP 0, mai negativo, nessun overflow. Test in Task 1.
4. **Riduci movimento attivo** — reveal senza volo/inclinazione, stato finale corretto, vibrazione presente. Verifica manuale in Task 4 (checklist nel riepilogo).
5. **Chiusura fotocamera senza salvare** (X durante la mira o la conferma) — si resta sulla cronologia, nessuna riga "fresca" evidenziata, nessuna tab vuota. Verifica manuale in Task 5.

---

### Task 1: Fondamenta (sessione principale)

**Files:**
- Modify: `CarSpot/DesignSystem/Theme/CSColor.swift`, `CarSpot/DesignSystem/Theme/CSFont.swift` (eyebrow), `CarSpot/DesignSystem/Theme/Rarity.swift`, `CarSpot/DesignSystem/Components/StatBar.swift`, `CarSpot/DesignSystem/Components/SpotCardView.swift` (solo firma: parametro `copies`)
- Create: `CarSpot/DesignSystem/Components/Surface.swift`, `CarSpot/Services/Game/CardCopies.swift`
- Test: `CarSpotTests/CardCopiesTests.swift`

**Interfaces — Produces:**
- `CSColor.panel` `#0E1014`, `CSColor.group` `#15181E`, `CSColor.hero` `#1A1D24`, `CSColor.nested` `#232731`, `CSColor.success` `#3FC07A`.
- `struct Surface<Content: View>: View` — `init(_ level: Surface.Level = .group, padding: CGFloat? = CSSpace.md, @ViewBuilder content: () -> Content)`; `enum Level { case hero, group }`. Hero: fondo `CSColor.hero`, raggio 20, luce bordo alto bianco 9%, ombra nero 35% r24 y10. Group: `CSColor.group`, raggio 20, luce 6%, nessuna ombra. `padding: nil` = nessun padding (per gruppi di righe).
- `struct SurfaceDivider: View` — 1 pt, bianco 6%, con inset sinistro opzionale `init(inset: CGFloat = 0)`.
- `struct KPIStrip: View` — `init(_ items: [KPIStrip.Item])`, `struct Item: Identifiable { let label: LocalizedStringKey; let value: String }`; dentro `Surface(.group)`, etichetta sopra valore, divisori verticali, cifre tabulari.
- `View.eyebrow(_ color: Color = CSColor.inkSecondary)` usa davvero `color`.
- `Rarity.color: Color` (valori Global Constraints); `primary` = `color`; `gradient` = `[color]` (monocromo, niente più arcobaleno).
- `enum RarityFinish { case matte, metalEdge, foilEdge, fullFoil }`, `Rarity.finish` (Comune→matte, Rara→metalEdge, Epica→foilEdge, Leggendaria→fullFoil).
- `StatBar`: anima il riempimento solo quando `value` cambia dopo la comparsa (non alla prima comparsa).
- `SpotCardView(card:roll:pitch:showStats:compact:copies:)` — nuovo `var copies: Int = 1` (rendering in Task 3).
- `enum CardCopies` (puro): `static func key(make: String, model: String) -> String`; `static func xp(base: Int, copyNumber: Int) -> Int`; `static let duplicateShare = 0.25`; `static func copyNumber(make: String, model: String, capturedAt: Date, among existing: [(make: String, model: String, capturedAt: Date)]) -> Int`; `static func count(make: String, model: String, among: [(make: String, model: String)]) -> Int`; `static let repeatWindow: TimeInterval = 86_400`; `static func isRepeatByPlace(make: String, model: String, area: String, capturedAt: Date, among existing: [(make: String, model: String, area: String, capturedAt: Date)]) -> Bool`. **I chiamanti passano solo carte con `isRepeat == false`** a `copyNumber`/`count`.
- `StoredCard.isRepeat: Bool = false` (migrazione leggera) — ripetizione della stessa auto: 0 punti, fuori da Collezione, copie e obiettivi.
- `ChallengeEngine.today(cards:claimed:day:)` ignora le carte con `isRepeat`.

- [ ] **Step 1: test che falliscono** in `CarSpotTests/CardCopiesTests.swift`:
  `keyNormalizza` → `key("VW ", " Polo")` == `key("vw", "polo")` e `key("Alfa  Romeo","Giulia")` == `key("alfa romeo","giulia")`;
  `xpPrimaCopia` → `xp(base: 20, copyNumber: 1)` == 20;
  `xpDoppioniComune` → copie 2,3,4,5 di base 20 == 5,2,1,0;
  `xpDoppioniLeggendaria` → copie 2…9 di base 260 == 65,32,16,8,4,2,1,0;
  `xpMaiNegativo` → `xp(base: 260, copyNumber: 60)` == 0;
  `copyNumberVuoto` → array vuoto == 1;
  `copyNumberOrdine` → con due Polo precedenti (date anteriori) e una Panda == 3.
- [ ] **Step 2:** `build-for-testing` (Global Constraints) compila con errore "cannot find CardCopies".
- [ ] **Step 3:** implementare `CardCopies` (formula spec: `n == 1 ? base : base*0.25/2^(n−2)` arrotondato per difetto, minimo 0) e il resto delle Interfaces.
- [ ] **Step 4:** `build-for-testing` → `** TEST BUILD SUCCEEDED **`.
- [ ] **Step 5:** commit "Design system: superfici a gradini, colore unico per rarità, CardCopies".

### Task 2: Superfici nelle tab (sessione "superfici")

**Files:** Modify `CarSpot/Features/Today/TodayView.swift`, `CarSpot/Features/Collection/CollectionView.swift`, `CarSpot/Features/Map/TerritoryView.swift`, `CarSpot/Features/Profile/ProfileView.swift`.
**Consumes:** `Surface`, `SurfaceDivider`, `KPIStrip`, `CSColor.*`, `CSColor.success`, `SpotCardView(copies:)`, `CardCopies.count`.

- [ ] **Step 1 Today:** card livello = `Surface(.hero)` (livello grande, "x / y XP" a destra, barra, riga streak + numero carte); i 3 obiettivi = un solo `Surface(.group, padding: nil)` con righe e `SurfaceDivider`; riga completata con spunta e "Fatto" in `CSColor.success`; togliere il fade-in globale di `TodayView`; sezione "Obiettivi del giorno · x di 3".
- [ ] **Step 2 Collezione:** escludere le carte con `isRepeat` (query/filtro) da griglia, statistiche e conteggi; le 3 tile statistiche → un `KPIStrip`; `FilterChip` non selezionato su `CSColor.nested`; nella griglia passare `copies: CardCopies.count(...)` calcolato una volta per render (dizionario per chiave), non per cella.
- [ ] **Step 3 Territorio:** `summaryCard` → `Surface(.hero)`; quartieri → un `Surface(.group, padding: nil)` con righe e divisori. Etichetta "Anteprima · dati di esempio" invariata.
- [ ] **Step 4 Profilo:** blocco livello/XP → `Surface(.hero)`; `statsRow` → `KPIStrip`; `sightingsCard` → `Surface(.group, padding: nil)` con righe e divisori; resta lo sfondo `AsphaltBackground` del profilo.
- [ ] **Step 5:** `build-for-testing` → `** TEST BUILD SUCCEEDED **`. Riepilogo con cosa guardare sull'iPhone per ogni tab. Niente commit.

### Task 3: Materiali della carta e ×N (sessione "carta")

**Files:** Modify `CarSpot/DesignSystem/Components/SpotCardView.swift` (corpo, non la firma), `CarSpot/DesignSystem/Effects/HolographicFoil.swift`, `CarSpot/DesignSystem/Components/RarityBadge.swift`, `CarSpot/Features/Collection/CardDetailView.swift`.
**Consumes:** `Rarity.color`, `Rarity.finish`, `copies`, `Surface`, `CardCopies.count`.

- [ ] **Step 1:** `SpotCardView` disegna la finitura per `rarity.finish` (tabella materiali della spec): bordo opaco 1 pt al 35% / bordo metallico 2 pt con luminosità legata a `roll` / bordo foil monocromo / foil monocromo su tutta la carta + bordo oro. Riflesso speculare radiale tinto `rarity.color` che segue `roll`/`pitch`. Niente glow esterno colorato (togliere l'alone attuale); ombra nera neutra resta. `compact`: solo bordo, niente foil animato.
- [ ] **Step 2:** `HolographicFoil` monocromo: parametri `color: Color`, `roll`, `pitch`, `strength`; nessun arcobaleno.
- [ ] **Step 3:** "×N" sulla carta quando `copies > 1` (pillola piccola in alto a destra, testo `CSFont.micro` tabulare, fondo `CSColor.nested`), con `accessibilityLabel` "N copie".
- [ ] **Step 4:** `RarityBadge` col colore unico (pallino + nome), niente gradiente. `CardDetailView`: passa `copies` (contando le `StoredCard` dello stesso modello via `@Query` + `CardCopies.count`), blocchi informativi in `Surface`.
- [ ] **Step 5:** `build-for-testing` → OK. Riepilogo. Niente commit.

### Task 4: Reveal v3 (sessione "reveal")

**Files:** Modify `CarSpot/Features/Capture/CaptureView.swift`, `CarSpot/Features/Capture/CaptureViewModel.swift`; Create `CarSpot/Features/Capture/CardRevealView.swift` (sposta qui `CardReveal`).
**Consumes:** `SpotCardView(card:roll:pitch:copies:)`, `Rarity.color/finish`, `CardCopies.copyNumber/xp/count`, `Surface`, `MotionManager`.
**Produces:** nessuna interfaccia per altri task. `CaptureView` resta presentata da `RootShellView` come oggi (`fullScreenCover`, si chiude con `dismiss()`).

- [ ] **Step 0 somiglianza foto:** creare `CarSpot/Services/Vision/PhotoSimilarity.swift` — `enum PhotoSimilarity { static let maxDistance: Float; static func isNearDuplicate(_ jpeg: Data, of candidates: [Data]) async -> Bool }` con `VNGenerateImageFeaturePrintRequest` (`@concurrent`, fuori dal main), confronto con al massimo le 10 catture più recenti dello stesso modello (ultimi 7 giorni). Soglia iniziale in costante commentata "da tarare su device". Errore di Vision → `false` (non penalizza).
- [ ] **Step 1 VM:** in `persist`, decidere `isRepeat` = `CardCopies.isRepeatByPlace(...)` (tra le carte non ripetute) **oppure** `PhotoSimilarity.isNearDuplicate`; salvare `StoredCard.isRepeat`. Se ripetizione: 0 XP, 0 valuta, nessun `PlayerStore.award`. Altrimenti calcolare `copyNumber` (solo tra non ripetute) e `xp = CardCopies.xp(base: rarity.xpReward, copyNumber:)`, `currency = xp / 4`; passarli a `PlayerStore.award` e ad analytics (`xpGained`). Esporre al view: `revealInfo` con `isDuplicate`, `copyNumber`, `cardNumber` (totale carte dopo il salvataggio), `isNewMake`, `xpGained`, livello prima/dopo e frazioni.
- [ ] **Step 2 sfondo:** dalla fase `.processing` in poi la foto (già anonimizzata, mai l'originale) resta a schermo intero come sfondo, scurita ~70% e sfocata ≤ 6 pt; il pannello di conferma usa `Surface`.
- [ ] **Step 3 reveal:** sequenza della spec (volo 0–560 ms molla senza rimbalzo con transizione geometrica dalla foto a schermo intero alla finestra foto della carta; vibrazione unica all'atterraggio con intensità per rarità; auto‑inclinazione 7–9° solo da Rara in su; testi con sfasamento 70 ms; nota nuova/doppione con pila di 2 carte dietro per i doppioni; riga XP statica + barra livello che avanza una volta). Inclinazione col dito 1:1 con resistenza oltre ~16° e ritorno a molla critica; giroscopio su device. Tocco sullo sfondo = stato finale. Riduci movimento = dissolvenze.
- [ ] **Step 4 azioni:** "Cattura un'altra" (secondaria, `vm.reset()`) e "Fatto" (primaria, `dismiss()`). Copy: "Nuova nella collezione", "Carta N · prima <Marca>", "La tua Nª <Modello>", "+N XP", "Livello L · x/y". Ripetizione: nota "Già vista qui" + "Questa auto l'hai già catturata: nessun punto", niente pila, niente riga XP né barra.
- [ ] **Step 5:** `build-for-testing` → OK. Riepilogo con checklist manuale (4 rarità × nuova/doppione, Riduci movimento). Niente commit.

### Task 5: Cronologia nella tab Cattura (sessione "cronologia")

**Files:** Modify `CarSpot/Features/Root/RootShellView.swift`; Create `CarSpot/Features/Capture/CaptureHistoryView.swift`.
**Consumes:** `Surface`, `SurfaceDivider`, `CSColor.panel`, `Rarity.color`, `CardCopies.copyNumber`, `CardDetailView(card:)`, `SpotCard` (mappatura da `StoredCard` come fa `CollectionView`).

- [ ] **Step 1 tab:** la tab `.capture` ha contenuto `CaptureHistoryView` e la selezione la raggiunge davvero (togliere il binding che la intercetta); quando la selezione diventa `.capture` per un tocco sulla tab → `showCapture = true`. Alla chiusura della `fullScreenCover` si resta su `.capture`. `-startTab capture` continua ad aprire la fotocamera. `presentationBackground(CSColor.panel)`.
- [ ] **Step 2 vista:** `SheetHeader("Cattura")`, bottone primario "Scatta una foto" (apre la fotocamera tramite una closure/env passata da `RootShellView`), riga riassunto (carte, modelli distinti, ultima cattura relativa); sezioni per giorno ("Oggi", "Ieri", poi data localizzata) con numero di catture; righe come da spec (miniatura con bordo interno 2 pt `rarity.color`, marca, modello, "quartiere · ora", rarità con pallino, "Nuova" se `copyNumber == 1` altrimenti "2ª", "3ª"… calcolato solo tra le non ripetute; le carte con `isRepeat` mostrano "Già vista · nessun punto" in grigio); `NavigationStack` propria con `matchedTransitionSource`/`.navigationTransition(.zoom)` verso `CardDetailView` come in `CollectionView`.
- [ ] **Step 3 riga fresca:** righe con `capturedAt` negli ultimi 10 s all'apparizione hanno un velo `rarity.color` al 10% che svanisce in ~3 s (una volta; niente con Riduci movimento).
- [ ] **Step 4 vuoto:** "Nessuna cattura" + "Ogni auto che fotografi compare qui, dalla più recente." + bottone.
- [ ] **Step 5:** `build-for-testing` → OK. Riepilogo con verifiche manuali (Review Focus 5). Niente commit.

### Task 6: XP doppioni sul server (sessione principale)

**Files:** Create `supabase/migrations/<versione>_0009_duplicate_xp.sql`.

- [ ] **Step 0 ripetizioni:** colonna `cards.is_repeat boolean not null default false` (scrivibile dal client in insert, mai riportabile a false); trigger *before insert* che la mette a true se esiste una carta dello stesso owner con stessa chiave modello, stesso `spotted_area` e `captured_at` nelle 24 ore precedenti. Sync: `CloudStore`/`SupabaseCloudStore`/`SyncService` inviano e leggono `is_repeat` ↔ `StoredCard.isRepeat`.
- [ ] **Step 1:** nuova versione di `private.award_card()`: se `new.is_repeat` → nessun premio; altrimenti base per rarità (20/55/130/260); `n` = 1 + numero di carte non ripetute dello stesso `owner_id` con `lower(regexp_replace(trim(make),'\s+',' ','g'))` e idem `model` uguali e `id <> new.id`; `xp = case when n = 1 then base else floor(base * 0.25 / power(2, n - 2)) end`; `grant_reward(owner, xp)` (la valuta segue come oggi). `security definer`, `search_path = ''`.
- [ ] **Step 2:** applicare con MCP `apply_migration` sul progetto `rdezjqbxqekteextolvh`, allineare il nome file alla versione registrata, poi `get_advisors` security + performance.
- [ ] **Step 3:** verifica SQL: in una transazione con `rollback`, inserire 3 carte uguali per un owner di prova e controllare che l'XP aggiunto sia base, 25%, 12%.
- [ ] **Step 4:** commit "Server: XP decrescente per i doppioni".

### Chiusura (sessione principale)

- [ ] Rivedere i diff delle quattro sessioni, `build-for-testing` complessiva, traduzioni EN delle stringhe nuove nel catalogo, aggiornare `DESIGN.md` (superfici, colore unico per rarità, regola motion) e lo stato in `CLAUDE.md`, commit.
